import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var banner: String?
    @Published private(set) var presenceMood: PresenceMood = .attend
    @Published private(set) var isListeningVoice: Bool = false
    /// Last voice transcript or reply caption for the voice surface.
    @Published private(set) var voiceCaption: String = ""

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
    private let speechCapture = SpeechCapture()
    private let speechSpeak = SpeechSpeak.shared

    private var speakRepliesEnabled: Bool {
        if UserDefaults.standard.object(forKey: "speakReplies") == nil { return true }
        return UserDefaults.standard.bool(forKey: "speakReplies")
    }

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
        guard !text.isEmpty else { return }
        draft = ""
        send(text: text, inputModality: "text", speakReply: speakRepliesEnabled)
    }

    /// Tap-to-talk: start or stop listening, then Ask with voice modality.
    func toggleVoiceListen() {
        if isListeningVoice {
            finishVoiceListenAndSend()
        } else {
            startVoiceListen()
        }
    }

    private func startVoiceListen() {
        guard !isSending else { return }
        speechSpeak.stop()
        banner = "Requesting mic…"
        Task { @MainActor in
            let ok = await speechCapture.requestAuthorizations()
            guard ok else {
                self.banner = SpeechCapture.CaptureError.notAuthorized.errorDescription
                self.setPresence(.attend)
                return
            }
            // Let permission sheets dismiss before starting the audio engine.
            try? await Task.sleep(nanoseconds: 250_000_000)
            do {
                try speechCapture.start()
                self.isListeningVoice = true
                self.voiceCaption = "Listening…"
                self.banner = nil
                self.setPresence(.listening)
                self.consumePresenceEvent(.listening)
            } catch {
                self.banner = error.localizedDescription
                self.isListeningVoice = false
                self.setPresence(.attend)
            }
        }
    }

    private func finishVoiceListenAndSend() {
        let text = speechCapture.stop()
        isListeningVoice = false
        guard !text.isEmpty else {
            voiceCaption = ""
            banner = SpeechCapture.CaptureError.noSpeech.errorDescription
            setPresence(.attend)
            return
        }
        voiceCaption = text
        send(text: text, inputModality: "voice", speakReply: true)
    }

    func send(text: String, inputModality: String, speakReply: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        banner = "Waiting on Ops…"
        messages.append(Message(sessionId: session.sessionId, role: .user, text: trimmed))
        isSending = true
        // Mic-only uses .listening; Ask wait is .thinking (was stuck-looking "listening").
        setPresence(.thinking)
        speechSpeak.stop()

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
                deviceToken: DeviceTokenStore.tokenForRequests()
            )

            do {
                try Task.checkCancellation()
                let reply = try await client.ask(
                    session: self.session,
                    text: trimmed,
                    turnId: turnIdAtSend,
                    inputModality: inputModality
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
                self.voiceCaption = reply.message.text
                self.banner = nil
                if reply.retentionClass == .ephemeral {
                    self.consumePresenceEvent(.ephemeralActive)
                    self.sparkQuiet.companySilenceAllowed = true
                    self.sparkQuiet.beginQuietEpisodeIfNeeded()
                } else {
                    self.sparkQuiet.companySilenceAllowed = false
                    self.sparkQuiet.endQuietEpisode()
                }
                if speakReply {
                    self.consumePresenceEvent(.speaking)
                    self.setPresence(.speaking)
                    if let note = self.speechSpeak.lastResolveNote {
                        self.banner = note
                    }
                    let gen = generation
                    self.speechSpeak.speak(reply.message.text) { [weak self] in
                        guard let self else { return }
                        if self.sendGeneration == gen, self.presenceMood == .speaking, !self.isSending {
                            self.setPresence(.attend)
                        }
                    }
                } else {
                    self.consumePresenceEvent(.speaking)
                    self.setPresence(.speaking, settleToAttendAfter: 1.6)
                }
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
        if isListeningVoice {
            speechCapture.cancel()
            isListeningVoice = false
        }
        speechSpeak.stop()
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
        voiceCaption = ""
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
        if isListeningVoice {
            speechCapture.cancel()
            isListeningVoice = false
        }
        speechSpeak.stop()
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
