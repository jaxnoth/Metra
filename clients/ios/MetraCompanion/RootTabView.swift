import SwiftUI

/// Phase 1 shell: one Metra home (presence + chat). Settings is gear-only.
struct RootTabView: View {
    @StateObject private var model = ChatViewModel()
    @AppStorage("opsBaseURL") private var opsBaseURL: String = ""
    /// Trial preview until real voice I/O lands - voice surface nearly fills the screen.
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
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            composerFocused = false
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
                    // Leading Done - trailing sits on top of the send control.
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
                    // Do not cancel Ask on background - brief Tailscale/Settings hops must not abort.
                    // Explicit Cancel / New session still cancel. URLSession timeout remains the bound.
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

    /// Voice surface: face nearly fills the screen. STT/TTS still later.
    private var voiceHome: some View {
        ZStack {
            MetraBrand.canvas(for: .dark)
                .ignoresSafeArea()

            PresenceChrome(mood: model.presenceMood, surface: .voice)
                .padding(.horizontal, 12)
                .padding(.bottom, 24)

            VStack {
                Spacer()
                Text("Voice layout preview - full STT/TTS later")
                    .font(.caption)
                    .foregroundStyle(MetraBrand.signalTealBright.opacity(0.8))
                    .padding(.bottom, 12)
            }
        }
    }
}

#Preview {
    RootTabView()
}
