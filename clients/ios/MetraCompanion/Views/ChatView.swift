import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var banner: String?
    /// Settles speaking back to attend after a text reply (voice I/O can own this later).
    @Published private(set) var presenceMood: PresenceMood = .attend

    @Published private(set) var session: Session
    /// Last presence cue from policy events (consume-only; no uncued Playful walks).
    @Published private(set) var lastPresenceCue: PresenceCue?

    private let opsURL: () -> String
    private var sendTask: Task<Void, Never>?
    private var speakSettleTask: Task<Void, Never>?
    /// Bumps on each send/cancel so a finishing Task cannot clear a newer send.
    private var sendGeneration: Int = 0
    /// Company spark-or-quiet state (caps restrict; default deny; no auto-emit in text chat yet).
    private var sparkQuiet = SparkQuietRuntime()

    init(opsURL: @escaping () -> String = {
        UserDefaults.standard.string(forKey: "opsBaseURL") ?? ""
    }) {
        self.opsURL = opsURL
        self.session = Session.fresh()
    }

    /// Presence consumes policy events only.
    func consumePresenceEvent(_ event: PresencePolicyEvent) {
        lastPresenceCue = PresenceCueMap.consume(event)
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        banner = nil
        messages.append(Message(sessionId: session.sessionId, role: .user, text: text))
        draft = ""
        isSending = true
        setPresence(.listening)
        consumePresenceEvent(.listening)

        sendTask?.cancel()
        sendGeneration += 1
        let generation = sendGeneration
        let sessionIdAtSend = session.sessionId
        let turnIdAtSend = session.beginTurn()
        // User turn closes quiet episode for spark-or-quiet (new silence window may open later).
        sparkQuiet.endQuietEpisode()
        sendTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // Sync MainActor cleanup - only if we are still the active generation.
                if self.sendGeneration == generation {
                    self.isSending = false
                    self.sendTask = nil
                }
            }

            let client = OpsAskClient(
                baseURLString: self.opsURL(),
                deviceToken: DeviceTokenStore.stubToken()
            )

            do {
                try Task.checkCancellation()
                let reply = try await client.ask(
                    session: self.session,
                    text: text,
                    turnId: turnIdAtSend
                )
                try Task.checkCancellation()
                guard self.session.sessionId == sessionIdAtSend else { return }

                // Live activeTurn only - send-time snapshots would ignore background invalidation.
                let episodeActive = self.session.ephemeralEpisode?.active
                let decision = ConversationPolicyGate.staleRoute(
                    responseConversationId: reply.conversationId,
                    responseTurnId: reply.turnId,
                    responseRetention: reply.retentionClass,
                    responseExecution: reply.executionTarget,
                    active: self.session.activeTurn,
                    ephemeralEpisodeActive: episodeActive
                )
                guard decision.isAccept else {
                    self.banner = AskClientError.staleRouteDropped.errorDescription
                    self.consumePresenceEvent(.ephemeralEnded)
                    self.setPresence(.attend)
                    return
                }

                if reply.message.sessionId != self.session.sessionId {
                    // Server rotated conversation id - start a fresh Session.
                    self.session = Session.fresh()
                }
                if var turn = self.session.activeTurn {
                    if let ret = reply.retentionClass { turn.retentionClass = ret }
                    if let exec = reply.executionTarget { turn.executionTarget = exec }
                    self.session.activeTurn = turn
                }
                if let ret = reply.retentionClass {
                    if ret == .ephemeral {
                        if self.session.ephemeralEpisode?.active == true {
                            var ep = self.session.ephemeralEpisode!
                            ep.touch()
                            self.session.ephemeralEpisode = ep
                        } else {
                            self.session.ephemeralEpisode = EphemeralEpisode.start(
                                conversationId: self.session.sessionId
                            )
                        }
                    } else if var ep = self.session.ephemeralEpisode {
                        ep.applyBoundary(
                            intentLeavesRelational: true,
                            policyLeavesCompany: ret == .normal || ret == .refuse,
                            appBackgrounded: false,
                            explicitClear: false
                        )
                        self.session.ephemeralEpisode = ep.active ? ep : nil
                    }
                }
                self.messages.append(reply.message)
                if reply.retentionClass == .ephemeral {
                    self.consumePresenceEvent(.ephemeralActive)
                    self.sparkQuiet.companySilenceAllowed = true
                    self.sparkQuiet.beginQuietEpisodeIfNeeded()
                } else {
                    self.sparkQuiet.companySilenceAllowed = false
                    self.sparkQuiet.endQuietEpisode()
                }
                // Brief speaking beat, then attend - text mode is not ongoing speech.
                self.consumePresenceEvent(.speaking)
                self.setPresence(.speaking, settleToAttendAfter: 1.6)
            } catch is CancellationError {
                guard self.session.sessionId == sessionIdAtSend else { return }
                self.banner = "Send cancelled."
                self.messages.append(
                    Message(
                        sessionId: sessionIdAtSend,
                        role: .system,
                        text: "Send cancelled."
                    )
                )
                self.setPresence(.attend)
            } catch let error as AskClientError {
                guard self.session.sessionId == sessionIdAtSend else { return }
                self.banner = error.errorDescription
                self.messages.append(
                    Message(
                        sessionId: sessionIdAtSend,
                        role: .system,
                        text: error.errorDescription ?? "Request failed."
                    )
                )
                self.setPresence(.attend)
            } catch {
                guard self.session.sessionId == sessionIdAtSend else { return }
                self.banner = error.localizedDescription
                self.messages.append(
                    Message(
                        sessionId: sessionIdAtSend,
                        role: .system,
                        text: error.localizedDescription
                    )
                )
                self.setPresence(.attend)
            }
        }
    }

    func cancelSend() {
        sendGeneration += 1
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        setPresence(.attend)
    }

    func newSession() {
        cancelSend()
        session.clearEphemeral(reason: "explicit_clear")
        session = Session.fresh()
        sparkQuiet = SparkQuietRuntime()
        messages.removeAll()
        banner = nil
        draft = ""
        consumePresenceEvent(.deskAttend)
        setPresence(.attend)
    }

    /// Called when the app returns to foreground after Tailscale / background.
    func handleSceneActive() {
        if isSending, sendTask == nil {
            isSending = false
            setPresence(.attend)
        }
    }

    /// Ephemeral episode ends on background; activeTurn cleared so in-flight HTTP
    /// completions cannot display (request may still finish - display is impossible).
    func handleSceneBackground() {
        session.invalidateOnBackground()
        sparkQuiet.companySilenceAllowed = false
        sparkQuiet.endQuietEpisode()
        consumePresenceEvent(.ephemeralEnded)
    }

    private func setPresence(_ mood: PresenceMood, settleToAttendAfter: TimeInterval? = nil) {
        speakSettleTask?.cancel()
        speakSettleTask = nil
        presenceMood = mood
        guard let delay = settleToAttendAfter else { return }
        speakSettleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if self.presenceMood == .speaking, !self.isSending {
                    self.presenceMood = .attend
                }
            }
        }
    }
}

/// Chat body for the Metra home (no own navigation chrome).
struct ChatPanel: View {
    @ObservedObject var model: ChatViewModel
    var composerFocused: FocusState<Bool>.Binding

    @Environment(\.colorScheme) private var colorScheme

    private let bottomAnchorId = "chat-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorId)
                }
                .padding()
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: composerFocused.wrappedValue) { _, focused in
                if focused {
                    // Keyboard animation needs a beat before scroll.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            .onTapGesture {
                composerFocused.wrappedValue = false
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
    }

    private var composerBar: some View {
        VStack(spacing: 0) {
            if let banner = model.banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Metra...", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused(composerFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if !model.isSending {
                            model.send()
                        }
                    }

                if model.isSending {
                    Button("Cancel") {
                        model.cancelSend()
                    }
                    .font(.footnote.weight(.semibold))
                } else {
                    Button {
                        model.send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(MetraBrand.accent(for: colorScheme))
                    }
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MetraBrand.surface(for: colorScheme))
        }
    }
}

struct ChatView: View {
    @StateObject private var model = ChatViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        ChatPanel(model: model, composerFocused: $focused)
    }
}

private struct MessageBubble: View {
    let message: Message
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(background)
                .foregroundStyle(message.role == .system ? Color.secondary : MetraBrand.primaryText(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var background: Color {
        switch message.role {
        case .user: MetraBrand.userBubble(for: colorScheme)
        case .assistant: MetraBrand.assistantBubble(for: colorScheme)
        case .system: Color.orange.opacity(0.12)
        }
    }
}

#Preview {
    ChatView()
}
