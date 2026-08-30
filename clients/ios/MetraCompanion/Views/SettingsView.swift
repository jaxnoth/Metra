import SwiftUI

struct SettingsView: View {
    @AppStorage("opsBaseURL") private var opsBaseURL: String = ""
    @AppStorage("visionMode") private var visionMode: Bool = true
    @AppStorage("voiceLabel") private var voiceLabel: String = "Siri Voice 4"
    @AppStorage("voiceLayoutPreview") private var voiceLayoutPreview: Bool = false

    @State private var deviceTokenPreview: String = ""

    var body: some View {
        Form {
            Section("Ops host") {
                TextField("https://jumpbox...ts.net", text: $opsBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("Enter the Tailscale MagicDNS / Serve HTTPS URL. Confirm it opens in Safari on this phone first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Mode") {
                Toggle("Vision mode", isOn: $visionMode)
                    .disabled(true)
                Text("Phase 1 is Vision-only. Bounded comes later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Voice") {
                TextField("Voice label", text: $voiceLabel)
                Toggle("Voice layout preview", isOn: $voiceLayoutPreview)
                Text("Chat keeps the desk-sized face. Voice layout nearly fills the screen. Full STT/TTS later - preview is layout only. Toolbar waveform toggles the same setting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Device token (stub)") {
                Text(deviceTokenPreview.isEmpty ? "(none)" : deviceTokenPreview)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Button("Ensure stub token in Keychain") {
                    deviceTokenPreview = DeviceTokenStore.stubToken()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            deviceTokenPreview = DeviceTokenStore.read() ?? ""
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
