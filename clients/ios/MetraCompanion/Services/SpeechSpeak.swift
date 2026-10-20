import AVFoundation
import Foundation

/// Speak voice preference stored in AppStorage / UserDefaults (`speakVoicePreference`).
enum SpeakVoicePreference: String, CaseIterable, Identifiable {
    /// Metra identity lock: Siri Voice 4 family (female, enhanced when installed).
    case metra
    /// Closest public API to "whatever Siri / Spoken Content uses" for this language.
    /// Apple does not expose the exact Siri & Search voice pick to third-party apps.
    case system

    var id: String { rawValue }

    var settingsLabel: String {
        switch self {
        case .metra: return "Metra (Voice 4)"
        case .system: return "System default"
        }
    }

    static let storageKey = "speakVoicePreference"

    static var current: SpeakVoicePreference {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? SpeakVoicePreference.metra.rawValue
        return SpeakVoicePreference(rawValue: raw) ?? .metra
    }
}

/// Speaks Metra replies via on-device AVSpeechSynthesizer.
/// Default identity: Siri Voice 4 - see plans/ios-voice-identity.plan.md. Optional system default.
@MainActor
final class SpeechSpeak: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechSpeak()

    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceSeq: UInt64 = 0
    private var activeUtteranceId: UInt64 = 0
    private var onFinished: (() -> Void)?

    /// Last resolve note for Settings (which voice + why).
    private(set) var lastResolveNote: String?

    /// Display name of the voice last resolved for speak.
    private(set) var lastResolvedVoiceName: String = ""

    /// Identifier of the voice last resolved (for Settings / diagnostics).
    private(set) var lastResolvedVoiceId: String = ""

    override private init() {
        super.init()
        synthesizer.delegate = self
        // Do not touch AVAudioSession here - grabbing .playback on launch steals AirPods → speaker.
    }

    /// Resolve the active speak voice for the current Settings preference.
    /// Returns nil when no voices are installed (utterance uses system pick).
    func resolveMetraVoice() -> AVSpeechSynthesisVoice? {
        switch SpeakVoicePreference.current {
        case .system:
            return resolveSystemDefaultVoice()
        case .metra:
            return resolveMetraIdentityVoice()
        }
    }

    /// Metra identity lock: Siri Voice 4 family - female, enhanced when installed.
    private func resolveMetraIdentityVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let english = voices.filter { isEnglish($0) && !isNoveltyOrVeto($0) }
        let ranked = english
            .map { (voice: $0, score: scoreMetra($0)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.voice.name < rhs.voice.name
            }

        if let best = ranked.first, best.score > 0 {
            return remember(best.voice, note: metraNote(for: best.voice))
        }
        return rememberLanguageFallback(notePrefix: "No suitable English voice")
    }

    /// System default: language voice Apple would pick, preferring enhanced Siri-family for that locale.
    /// Does not force Voice 4 or female - follows installed Siri/Spoken Content pool for the device language.
    private func resolveSystemDefaultVoice() -> AVSpeechSynthesisVoice? {
        let preferredLang = preferredSpeakLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { !isNoveltyOrVeto($0) }

        let sameLang = voices.filter {
            $0.language.lowercased() == preferredLang.lowercased()
                || $0.language.lowercased().hasPrefix(preferredLang.lowercased().prefix(2) + "-")
        }

        let ranked = sameLang
            .map { (voice: $0, score: scoreSystem($0, preferredLang: preferredLang)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.voice.name < rhs.voice.name
            }

        if let best = ranked.first, best.score > 0 {
            let q = qualityLabel(best.voice)
            return remember(
                best.voice,
                note: "System default: \(best.voice.name) (\(q), \(best.voice.language)). Matches Spoken Content / language default - not a private read of Siri & Search."
            )
        }

        if let system = AVSpeechSynthesisVoice(language: preferredLang) {
            return remember(
                system,
                note: "System default: \(system.name) (\(qualityLabel(system)), \(system.language))."
            )
        }
        return rememberLanguageFallback(notePrefix: "System default unavailable")
    }

    private func remember(_ voice: AVSpeechSynthesisVoice, note: String) -> AVSpeechSynthesisVoice {
        lastResolvedVoiceName = voice.name
        lastResolvedVoiceId = voice.identifier
        lastResolveNote = note
        return voice
    }

    private func rememberLanguageFallback(notePrefix: String) -> AVSpeechSynthesisVoice? {
        let lang = preferredSpeakLanguageCode()
        let installed = AVSpeechSynthesisVoice.speechVoices()
        if let fallback = AVSpeechSynthesisVoice(language: lang)
            ?? AVSpeechSynthesisVoice(language: "en-US")
            ?? installed.first(where: { $0.language.lowercased().hasPrefix("en") })
            ?? installed.first
        {
            return remember(fallback, note: "\(notePrefix) - using \(fallback.name) (\(fallback.language)).")
        }
        lastResolvedVoiceName = "(none)"
        lastResolvedVoiceId = ""
        lastResolveNote = "\(notePrefix) - no speech voices installed."
        return nil
    }

    private func metraNote(for voice: AVSpeechSynthesisVoice) -> String {
        let q = qualityLabel(voice)
        if isVoiceFourCandidate(voice) {
            return "Metra: \(voice.name) (\(q))."
        }
        if voice.gender == .female {
            return "Metra: Siri Voice 4 not matched - using \(voice.name) (\(q)). Install Voice 4 under Spoken Content → Voices."
        }
        return "Metra: weak match - using \(voice.name) (\(q)). Install an enhanced English Siri voice under Spoken Content."
    }

    private func preferredSpeakLanguageCode() -> String {
        if let id = Locale.preferredLanguages.first, !id.isEmpty {
            // AVSpeech wants BCP-47 like en-US; preferredLanguages is usually that.
            return id
        }
        return Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    }

    func stop() {
        utteranceSeq += 1
        activeUtteranceId = 0
        onFinished = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        releaseSpeakSession()
    }

    /// Speak text; calls onFinished on the main actor when that utterance ends (or is cancelled).
    func speak(_ text: String, onFinished: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onFinished?()
            return
        }
        stop()
        utteranceSeq += 1
        let id = utteranceSeq
        activeUtteranceId = id
        self.onFinished = onFinished

        activateSpeakSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        let voice = resolveMetraVoice()
        if let voice {
            utterance.voice = voice
            // Metra mode: tiny lift for warmth. System mode: leave pitch alone so it tracks Siri/default.
            if SpeakVoicePreference.current == .metra {
                utterance.pitchMultiplier = voice.gender == .male ? 1.08 : 1.03
            } else {
                utterance.pitchMultiplier = 1.0
            }
        } else {
            utterance.pitchMultiplier = 1.0
        }
        // Slightly under default rate - compact voices read less "machine-gun robotic".
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    /// Activate only while speaking; keep AirPods / Bluetooth as the preferred route.
    private func activateSpeakSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: [])
        } catch {
            // Speak may still work on the default route; do not force speaker.
        }
    }

    private func releaseSpeakSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Short Settings preview of the resolved speak voice.
    func previewIdentityLine() {
        speak("Hey - Metra here. This is how I sound on this phone.")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishIfActive()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.finishIfActive()
        }
    }

    private func finishIfActive() {
        guard activeUtteranceId != 0 else { return }
        activeUtteranceId = 0
        let cb = onFinished
        onFinished = nil
        releaseSpeakSession()
        cb?()
    }

    // MARK: - Scoring

    private func scoreMetra(_ voice: AVSpeechSynthesisVoice) -> Int {
        var s = 0
        let name = voice.name.lowercased()
        let id = voice.identifier.lowercased()

        switch voice.quality {
        case .premium: s += 100
        case .enhanced: s += 70
        default: s += 5
        }

        switch voice.gender {
        case .female: s += 45
        case .unspecified: s += 8
        case .male: s -= 60
        @unknown default: break
        }

        if id.contains("siri") || name.contains("siri") { s += 35 }
        if isVoiceFourCandidate(voice) { s += 55 }

        let lang = voice.language.lowercased()
        if lang.hasPrefix("en-us") { s += 20 }
        else if lang.hasPrefix("en-au") { s += 18 } // same-family lower register alternate
        else if lang.hasPrefix("en-gb") || lang.hasPrefix("en-ie") { s += 12 }
        else if lang.hasPrefix("en") { s += 8 }

        // Prefer known natural female en voices when Siri numbering is absent from AV names.
        for token in ["nicky", "zoe", "samantha", "karen", "moira", "tessa", "fiona", "kate", "serena"] {
            if name.contains(token) || id.contains(token) { s += 15; break }
        }
        for token in ["aaron", "daniel", "alex", "fred", "ralph", "bruce", "albert", "lee", "oliver", "arthur", "gordon", "rishi"] {
            if name.contains(token) || id.contains(token) { s -= 40; break }
        }

        if voice.voiceTraits.contains(.isPersonalVoice) { s -= 200 } // opt-in only later
        return s
    }

    /// System mode: quality + Siri-family + exact language match. No gender / Voice 4 lock.
    private func scoreSystem(_ voice: AVSpeechSynthesisVoice, preferredLang: String) -> Int {
        var s = 0
        let name = voice.name.lowercased()
        let id = voice.identifier.lowercased()
        let lang = voice.language.lowercased()
        let pref = preferredLang.lowercased()

        switch voice.quality {
        case .premium: s += 100
        case .enhanced: s += 70
        default: s += 10
        }

        if lang == pref { s += 40 }
        else if lang.hasPrefix(String(pref.prefix(2))) { s += 15 }

        if id.contains("siri") || name.contains("siri") { s += 30 }

        if voice.voiceTraits.contains(.isPersonalVoice) { s -= 200 }
        return s
    }

    private func isEnglish(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.language.lowercased().hasPrefix("en")
    }

    private func isVoiceFourCandidate(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let name = voice.name.lowercased()
        let id = voice.identifier.lowercased()
        if name.contains("voice 4") || name.contains("voice4") { return true }
        // Some builds expose "Siri Voice 4" / trailing " 4" on Siri-family names.
        if (name.contains("siri") || id.contains("siri")) && (name.hasSuffix(" 4") || name.contains(" 4 ") || id.contains("_4") || id.contains(".4.")) {
            return true
        }
        // Identifier patterns seen on Spoken Content installs (locale-dependent).
        if id.contains("siri") && (id.contains("voice4") || id.contains("voice_4") || id.contains("en-us_4")) {
            return true
        }
        return false
    }

    private func isNoveltyOrVeto(_ voice: AVSpeechSynthesisVoice) -> Bool {
        let name = voice.name.lowercased()
        let id = voice.identifier.lowercased()
        let banned = [
            "zarvox", "whisper", "superstar", "bells", "organ", "cellos", "good news",
            "bad news", "pipe organ", "trinoids", "boing", "bubbles", "junior", "grandma",
            "grandpa", "kathy", "princess", "sandy", "shelley", "wobble"
        ]
        return banned.contains { name.contains($0) || id.contains($0) }
    }

    private func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "premium"
        case .enhanced: return "enhanced"
        default: return "compact"
        }
    }
}
