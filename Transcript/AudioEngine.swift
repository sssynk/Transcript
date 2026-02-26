import AudioToolbox
import AVFoundation
import Speech

final class AudioEngine {
    private var engine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private var completion: ((String?) -> Void)?
    private var lastResult: String?
    private var tapCallCount = 0

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()
    }

    /// Returns an error message on failure, nil on success.
    func start(state: AppState) -> String? {
        cleanup()
        state.resetLevels()

        let micPerm = AVAudioApplication.shared.recordPermission
        print("[Transcript] Mic record permission: \(micPerm == .granted ? "granted" : micPerm == .denied ? "DENIED" : "undetermined")")
        if micPerm == .denied {
            return "Microphone access denied — grant it in System Settings → Privacy → Microphone"
        }
        if micPerm == .undetermined {
            return "Microphone permission needed — relaunch the app"
        }

        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            print("[Transcript] Speech not authorized (status \(authStatus.rawValue))")
            return "Grant Speech Recognition permission in System Settings"
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            print("[Transcript] Speech recognizer unavailable")
            return "Speech recognizer unavailable"
        }

        var newEngine = AVAudioEngine()

        let defaultDev = AudioDeviceManager.defaultInputDevice()
        print("[Transcript] System default input: \(defaultDev?.name ?? "none") (\(defaultDev?.uid ?? ""))")

        if !state.selectedDeviceUID.isEmpty,
           let deviceID = AudioDeviceManager.deviceID(forUID: state.selectedDeviceUID) {
            print("[Transcript] Using selected device UID: \(state.selectedDeviceUID)")
            if !setInputDevice(deviceID, on: newEngine) {
                print("[Transcript] Device set failed — falling back to system default")
                newEngine = AVAudioEngine()
            }
        } else {
            print("[Transcript] Using system default device")
        }

        let inputNode = newEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("[Transcript] Bad audio format: \(format)")
            return "No usable microphone found"
        }

        print("[Transcript] Format: \(format.sampleRate) Hz, \(format.channelCount) ch")
        print("[Transcript] On-device supported: \(speechRecognizer.supportsOnDeviceRecognition)")

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        self.recognitionRequest = request
        self.engine = newEngine

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false

            if let error {
                print("[Transcript] Recognition callback error: \(error)")
            }
            if let text {
                print("[Transcript] Partial: \"\(text)\" (final=\(isFinal))")
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text {
                    self.lastResult = text
                    if isFinal { self.invokeCompletion(text) }
                }
                if error != nil && !isFinal {
                    self.invokeCompletion(self.lastResult)
                }
            }
        }

        guard recognitionTask != nil else {
            print("[Transcript] Failed to create recognition task")
            return "Could not start speech recognition"
        }

        tapCallCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak state] buffer, _ in
            request.append(buffer)

            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(1, count)))
            let level = CGFloat(min(1, max(0, Double(rms) * 5)))

            if let self {
                self.tapCallCount += 1
                if self.tapCallCount == 1 || self.tapCallCount == 10 || self.tapCallCount == 100 {
                    print("[Transcript] Audio RMS @ tap \(self.tapCallCount): \(rms) (level: \(level))")
                }
            }

            Task { @MainActor in
                state?.pushLevel(level)
            }
        }

        newEngine.prepare()
        do {
            try newEngine.start()
            print("[Transcript] Engine started")
            return nil
        } catch {
            print("[Transcript] Engine start failed: \(error)")
            cleanup()
            return "Microphone error: \(error.localizedDescription)"
        }
    }

    func stop(completion: @escaping @MainActor (String?) -> Void) {
        self.completion = completion

        if let engine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            self?.invokeCompletion(self?.lastResult)
        }
    }

    func cancel() {
        cleanup()
    }

    private func invokeCompletion(_ text: String?) {
        guard let completion else { return }
        self.completion = nil
        completion(text)
    }

    @discardableResult
    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) -> Bool {
        var id = deviceID
        guard let audioUnit = engine.inputNode.audioUnit else {
            print("[Transcript] No audio unit on input node")
            return false
        }
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            print("[Transcript] setInputDevice failed: \(status)")
            return false
        }
        return true
    }

    private func cleanup() {
        if let engine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        lastResult = nil
        completion = nil
    }
}
