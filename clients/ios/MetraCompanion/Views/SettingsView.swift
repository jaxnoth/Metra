import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("opsBaseURL") private var opsBaseURL: String = ""
    @AppStorage("visionMode") private var visionMode: Bool = true
    @AppStorage("voiceLabel") private var voiceLabel: String = "Siri Voice 4"
    @AppStorage("voiceLayoutPreview") private var voiceLayoutPreview: Bool = false
    @AppStorage("speakReplies") private var speakReplies: Bool = true
    @AppStorage(SpeakVoicePreference.storageKey) private var speakVoicePreferenceRaw: String =
        SpeakVoicePreference.metra.rawValue

    @State private var deviceTokenPreview: String = ""
    @State private var devicePairStatus: String = ""
    @State private var metaStatus: String = ""
    @State private var metaProbeBusy: Bool = false
    @State private var pairBusy: Bool = false
    @State private var resolvedVoiceSummary: String = ""

    private var speakVoicePreference: Binding<SpeakVoicePreference> {
        Binding(
            get: { SpeakVoicePreference(rawValue: speakVoicePreferenceRaw) ?? .metra },
            set: { speakVoicePreferenceRaw = $0.rawValue }
        )
    }

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
                Button(metaProbeBusy ? "Checking…" : "Check Ops reach") {
                    Task { await probeOpsMeta() }
                }
                .disabled(metaProbeBusy || opsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !metaStatus.isEmpty {
                    Text(metaStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Mode") {
                Toggle("Vision mode", isOn: $visionMode)
                    .disabled(true)
                Text("Vision-only. Asks use Vision + Company posture (max personality). Bounded later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Voice") {
                Toggle("Voice layout", isOn: $voiceLayoutPreview)
                Toggle("Speak replies", isOn: $speakReplies)
                Picker("Speak voice", selection: speakVoicePreference) {
                    ForEach(SpeakVoicePreference.allCases) { pref in
                        Text(pref.settingsLabel).tag(pref)
                    }
                }
                .onChange(of: speakVoicePreferenceRaw) { _, _ in
                    refreshResolvedVoice()
                }
                TextField("Voice label", text: $voiceLabel)
                if !resolvedVoiceSummary.isEmpty {
                    Text(resolvedVoiceSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Preview speak voice") {
                    refreshResolvedVoice()
                    SpeechSpeak.shared.previewIdentityLine()
                }
                Text(voiceHelpFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Device identity") {
                Text(deviceIdentitySummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !deviceTokenPreview.isEmpty {
                    Text(deviceTokenPreview)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button(pairBusy ? "Pairing…" : "Pair with Ops (WhoIs)") {
                    Task { await pairWithOps() }
                }
                .disabled(pairBusy || opsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !devicePairStatus.isEmpty {
                    Text(devicePairStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Reset to local stub token") {
                    DeviceTokenStore.clear()
                    deviceTokenPreview = DeviceTokenStore.stubToken()
                    devicePairStatus = "Local stub restored. Pair with Ops when on Tailscale."
                }
                Text("Pair uses Tailscale WhoIs on the Ops host, then stores a host-minted device token in Keychain. First-seen nodes may need Approve on Ops Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshDeviceIdentity()
            refreshResolvedVoice()
        }
    }

    private var deviceIdentitySummary: String {
        let token = DeviceTokenStore.read()
        if token == nil || token?.isEmpty == true {
            return "No device token yet."
        }
        if DeviceTokenStore.isStub(token) {
            return "Local stub only - Ask works for smoke; Pair with Ops for WhoIs revoke."
        }
        return "Host-minted device token (WhoIs pair)."
    }

    @MainActor
    private func refreshDeviceIdentity() {
        deviceTokenPreview = DeviceTokenStore.read() ?? ""
    }

    @MainActor
    private func pairWithOps() async {
        pairBusy = true
        defer { pairBusy = false }
        let label = UIDevice.current.name
        do {
            let result = try await OpsAskClient.pairWithOps(baseURLString: opsBaseURL, label: label)
            switch result {
            case .paired(let deviceId, _, let message):
                refreshDeviceIdentity()
                devicePairStatus = "\(message) deviceId=\(deviceId)"
            case .pending(let requestId, let message):
                devicePairStatus = "\(message) requestId=\(requestId). Approve on Ops Settings, then Pair again."
            }
        } catch {
            devicePairStatus = error.localizedDescription
        }
    }

    private var voiceHelpFooter: String {
        switch SpeakVoicePreference(rawValue: speakVoicePreferenceRaw) ?? .metra {
        case .metra:
            return "Metra prefers Siri Voice 4 (enhanced). Download it under Settings → Accessibility → Spoken Content → Voices if needed. Toolbar waveform toggles voice layout."
        case .system:
            return "System default uses the Spoken Content / language voice for this phone. Apple does not let apps read the exact Siri & Search voice setting. Change Siri or Spoken Content voices in iOS Settings, then Preview here."
        }
    }

    @MainActor
    private func refreshResolvedVoice() {
        _ = SpeechSpeak.shared.resolveMetraVoice()
        let name = SpeechSpeak.shared.lastResolvedVoiceName
        let note = SpeechSpeak.shared.lastResolveNote ?? ""
        resolvedVoiceSummary = note.isEmpty ? "Resolved: \(name)" : note
        let pref = SpeakVoicePreference(rawValue: speakVoicePreferenceRaw) ?? .metra
        if voiceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || voiceLabel == "Siri Voice 4"
            || voiceLabel.hasPrefix("Metra:")
            || voiceLabel.hasPrefix("System")
        {
            voiceLabel = pref == .metra
                ? (name.contains("4") ? "Siri Voice 4" : name)
                : name
        }
    }

    @MainActor
    private func probeOpsMeta() async {
        metaProbeBusy = true
        defer { metaProbeBusy = false }
        do {
            let result = try await OpsAskClient.probeMeta(baseURLString: opsBaseURL)
            if let warning = result.statusMessage {
                metaStatus = warning
            } else {
                metaStatus = "Ops reachable. Serve OK. Ask engine looks healthy."
            }
        } catch let error as AskClientError {
            metaStatus = error.errorDescription ?? "Ops probe failed."
        } catch {
            metaStatus = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
