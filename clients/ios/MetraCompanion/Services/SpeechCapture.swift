import AVFoundation
import Foundation
import Speech

/// Tap-to-talk speech recognition.
/// Not @MainActor: AVAudioEngine + permission callbacks are safer off the main actor.
final class SpeechCapture: NSObject, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case onDeviceRequired
        case invalidAudioFormat
        case noSpeech
        case engine(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Microphone or speech recognition permission denied."
            case .recognizerUnavailable:
                return "Speech recognition unavailable on this device."
            case .onDeviceRequired:
                return "On-device speech recognition is required. Enable cloud speech in Settings only if you accept Apple cloud STT, or install on-device assets."
            case .invalidAudioFormat:
                return "Microphone audio format not ready. Try again."
            case .noSpeech:
                return "No speech heard."
            case .engine(let msg):
                return msg
            }
        }
    }

    /// UserDefaults key - when true, cloud STT may be used if on-device assets are missing.
    static let allowCloudSpeechKey = "allowCloudSpeechRecognition"

    private let audioEngine = AVAudioEngine()
    private let stateLock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var latestPartial: String = ""
    private var listening = false

    var isListening: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return listening
    }

    func requestAuthorizations() async -> Bool {
        let micOk = await requestMicrophonePermission()
        guard micOk else { return false }

        let speechOk = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        // Permissions only - do not activate AVAudioSession here (steals AirPods on open / first mic grant).
        return speechOk
    }

    /// Configure session for mic capture without forcing the built-in speaker.
    private func activateCaptureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // No .defaultToSpeaker - that yanks playback from AirPods to the phone earpiece/speaker.
        // .allowBluetooth (HFP) for AirPods mic; do not combine .allowBluetoothA2DP with .measurement
        // (iOS rejects that option set). A2DP playback belongs on SpeechSpeak's playAndRecord/.default.
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.duckOthers, .allowBluetooth]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func releaseCaptureSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        return await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Start listening. Call `stop()` to finish and get the transcript.
    func start() throws {
        stateLock.lock()
        let already = listening
        stateLock.unlock()
        guard !already else { return }

        latestPartial = ""

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw CaptureError.recognizerUnavailable
        }
        self.recognizer = recognizer

        do {
            try activateCaptureSession()
        } catch {
            throw CaptureError.engine(error.localizedDescription)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Default fail-closed: on-device only. Cloud STT requires explicit Settings opt-in.
        let allowCloud = UserDefaults.standard.bool(forKey: Self.allowCloudSpeechKey)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = !allowCloud
        } else if allowCloud {
            request.requiresOnDeviceRecognition = false
        } else {
            self.request = nil
            releaseCaptureSession()
            throw CaptureError.onDeviceRequired
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.request = nil
            releaseCaptureSession()
            throw CaptureError.invalidAudioFormat
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.request = nil
            releaseCaptureSession()
            throw CaptureError.engine(error.localizedDescription)
        }

        stateLock.lock()
        listening = true
        stateLock.unlock()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.stateLock.lock()
                self.latestPartial = result.bestTranscription.formattedString
                self.stateLock.unlock()
            }
            if error != nil {
                self.stateLock.lock()
                let wasListening = self.listening
                self.listening = false
                self.stateLock.unlock()
                guard wasListening else { return }
                if self.audioEngine.isRunning {
                    self.audioEngine.stop()
                }
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.request = nil
                self.task = nil
                self.recognizer = nil
                self.releaseCaptureSession()
            }
        }
    }

    /// Stop capture and return final (or best partial) transcript.
    func stop() -> String {
        stateLock.lock()
        let wasListening = listening
        listening = false
        let partial = latestPartial
        latestPartial = ""
        stateLock.unlock()

        guard wasListening else {
            return partial.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        request?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.finish()
        task = nil
        request = nil
        recognizer = nil
        releaseCaptureSession()

        return partial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cancel() {
        stateLock.lock()
        let wasListening = listening
        listening = false
        latestPartial = ""
        let activeTask = task
        task = nil
        stateLock.unlock()

        activeTask?.cancel()
        guard wasListening else { return }

        request?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        recognizer = nil
        releaseCaptureSession()
    }
}
