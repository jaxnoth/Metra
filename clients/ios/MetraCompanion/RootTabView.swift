import SwiftUI

/// Phase 1 shell: one Metra home (presence + chat / voice). Settings is gear-only.
struct RootTabView: View {
    @StateObject private var model = ChatViewModel()
    @AppStorage("opsBaseURL") private var opsBaseURL: String = ""
    /// Voice layout nearly fills the screen (STT/TTS).
    @AppStorage("voiceLayoutPreview") private var voiceLayoutPreview: Bool = false
    @FocusState private var composerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    private var surface: PresenceSurface {
        voiceLayoutPreview ? .voice : .chat
    }

    var body: some View {
        NavigationStack {
            Group {
                if surface == .voice {
                    voiceHome
                } else {
                    chatHome
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MetraBrand.canvas(for: colorScheme).ignoresSafeArea())
            .animation(.easeInOut(duration: 0.25), value: surface)
            .navigationTitle("Metra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MetraBrand.canvas(for: colorScheme), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if surface == .chat {
                        Button("New") {
                            composerFocused = false
                            model.newSession()
                        }
                    } else {
                        Button("New") {
                            model.newSession()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            composerFocused = false
                            if model.isListeningVoice {
                                model.toggleVoiceListen()
                            }
                            voiceLayoutPreview.toggle()
                        } label: {
                            Image(systemName: voiceLayoutPreview ? "text.bubble" : "waveform.circle.fill")
                                .accessibilityLabel(voiceLayoutPreview ? "Chat layout" : "Voice layout")
                        }
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                                .accessibilityLabel("Settings")
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Done") {
                        composerFocused = false
                    }
                    Spacer()
                }
            }
            .tint(MetraBrand.accent(for: colorScheme))
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.handleSceneActive()
                } else if phase == .background {
                    model.handleSceneBackground()
                    composerFocused = false
                }
            }
        }
    }

    /// Text chat: desk-sized presence (~128pt) + composer. Face never hides.
    private var chatHome: some View {
        VStack(spacing: 0) {
            PresenceChrome(mood: model.presenceMood, surface: .chat)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if opsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Set Ops URL via the gear before chatting.")
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.yellow.opacity(0.2))
            }

            ChatPanel(model: model, composerFocused: $composerFocused)
        }
    }

    /// Voice surface: face nearly fills the screen; tap mic to talk.
    private var voiceHome: some View {
        ZStack {
            MetraBrand.canvas(for: .dark)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                PresenceChrome(mood: model.presenceMood, surface: .voice)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)

                if let banner = model.banner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                if !model.voiceCaption.isEmpty {
                    Text(model.voiceCaption)
                        .font(.body)
                        .foregroundStyle(MetraBrand.signalTealBright)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 20)
                }

                HStack(spacing: 28) {
                    if model.isSending {
                        Button("Cancel") {
                            model.cancelSend()
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.orange)
                    }

                    Button {
                        model.toggleVoiceListen()
                    } label: {
                        Image(systemName: model.isListeningVoice ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(
                                model.isListeningVoice
                                    ? Color.orange
                                    : MetraBrand.signalTealBright
                            )
                            .accessibilityLabel(model.isListeningVoice ? "Stop listening" : "Start listening")
                    }
                    .disabled(model.isSending && !model.isListeningVoice)
                }
                .padding(.bottom, 28)
            }
        }
    }
}

#Preview {
    RootTabView()
}
