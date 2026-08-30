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

    private let opsURL: () -> String
    private var sendTask: Task<Void, Never>?
    private var speakSettleTask: Task<Void, Never>?
    /// Bumps on each send/cancel so a finishing Task cannot clear a newer send.
    private var sendGeneration: Int = 0

    init(opsURL: @escaping () -> String = {
        UserDefaults.standard.string(forKey: "opsBaseURL") ?? ""
    }) {
        self.opsURL = opsURL
        self.session = Session.fresh()
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        banner = nil
        messages.append(Message(sessionId: session.sessionId, role: .user, text: text))
        draft = ""
        isSending = true
        setPresence(.listening)

        sendTask?.cancel()
        sendGeneration += 1
        let generation = sendGeneration
        let sessionIdAtSend = session.sessionId
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
                let reply = try await client.ask(session: self.session, text: text)
                try Task.checkCancellation()
                guard self.session.sessionId == sessionIdAtSend else { return }
                if reply.sessionId != self.session.sessionId {
                    self.session = Session(sessionId: reply.sessionId)
                }
                self.messages.append(reply)
                // Brief speaking beat, then attend - text mode is not ongoing speech.
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
        session = Session.fresh()
        messages.removeAll()
        banner = nil
        draft = ""
        setPresence(.attend)
    }

    /// Called when the app returns to foreground after Tailscale / background.
    func handleSceneActive() {
        if isSending, sendTask == nil {
            isSending = false
            setPresence(.attend)
        }
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
