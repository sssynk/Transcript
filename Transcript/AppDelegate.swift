import AppKit
import AVFoundation
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel!
    let state = AppState()
    let audioEngine = AudioEngine()
    let hotkeyManager = HotkeyManager()
    let statsStore = StatsStore()
    let replacementStore = ReplacementStore()
    private var isRecording = false
    private var dismissTask: Task<Void, Never>?
    private var recordingStartTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeyManager.checkAccessibility()
        requestPermissions()
        setupOverlay()
        setupHotkey()
    }

    private func requestPermissions() {
        AVAudioApplication.requestRecordPermission { granted in
            print("[Transcript] Microphone permission: \(granted)")
            if !granted {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "Microphone Access Required"
                    alert.informativeText = "Transcript needs microphone access to record your voice.\n\nGrant permission in System Settings → Privacy & Security → Microphone."
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "Open System Settings")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                }
            }
        }

        SFSpeechRecognizer.requestAuthorization { status in
            print("[Transcript] Speech recognition permission: \(status.rawValue)")
            if status != .authorized {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "Speech Recognition Required"
                    alert.informativeText = "Transcript needs speech recognition permission to transcribe your voice.\n\nGrant access in System Settings → Privacy & Security → Speech Recognition."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    private func setupOverlay() {
        overlayPanel = OverlayPanel(state: state)
    }

    private func setupHotkey() {
        hotkeyManager.onHotkeyDown = { [weak self] in
            self?.startDictation()
        }
        hotkeyManager.onHotkeyUp = { [weak self] in
            self?.stopDictation()
        }
        hotkeyManager.start()
    }

    // MARK: - Dictation flow

    private func startDictation() {
        guard !isRecording else { return }
        isRecording = true

        dismissTask?.cancel()
        dismissTask = nil

        audioEngine.cancel()

        state.phase = .recording
        recordingStartTime = Date()
        overlayPanel.show()

        if let errorMsg = audioEngine.start(state: state) {
            state.phase = .error(errorMsg)
            isRecording = false
            scheduleDismiss(after: 2.5)
        }
    }

    private func stopDictation() {
        guard isRecording else { return }
        isRecording = false

        state.phase = .processing

        audioEngine.stop { [weak self] text in
            guard let self else { return }

            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let duration = Date().timeIntervalSince(self.recordingStartTime ?? Date())
                let processed = self.processText(text)
                self.statsStore.recordSession(text: processed, durationSeconds: duration)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(processed, forType: .string)

                self.state.phase = .success("Pasted")
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    self.simulatePaste()
                }
            } else {
                self.state.phase = .error("No speech detected")
            }

            self.scheduleDismiss(after: 1.5)
        }
    }

    // MARK: - Text processing (reads settings from UserDefaults, not @Observable)

    private func processText(_ raw: String) -> String {
        var text = replacementStore.apply(to: raw)

        let shouldDeStutter = UserDefaults.standard.object(forKey: "removeStuttering") as? Bool ?? true
        if shouldDeStutter {
            text = Self.deStutter(text)
        }

        let styleRaw = UserDefaults.standard.string(forKey: "outputStyle") ?? "Formal"
        if let style = OutputStyle(rawValue: styleRaw) {
            text = Self.applyStyle(style, to: text)
        }

        return text
    }

    private static let allowedDuplicates: Set<String> = [
        "that", "had", "very", "really", "so", "bye"
    ]

    private static func deStutter(_ text: String) -> String {
        var words = text.components(separatedBy: " ")
        var i = 1
        while i < words.count {
            let cur = words[i].lowercased().trimmingCharacters(in: .punctuationCharacters)
            let prev = words[i - 1].lowercased().trimmingCharacters(in: .punctuationCharacters)
            if !cur.isEmpty && cur == prev && !allowedDuplicates.contains(cur) {
                words.remove(at: i)
            } else {
                i += 1
            }
        }
        return words.joined(separator: " ")
    }

    private static func applyStyle(_ style: OutputStyle, to text: String) -> String {
        switch style {
        case .formal:
            return text
        case .noCapitals:
            return text.lowercased()
        case .casual:
            var result = text.lowercased()
            result = result.replacingOccurrences(
                of: "(?<![0-9])\\.(?![0-9])",
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            return result.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Clipboard & paste

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.state.phase = .idle
            self.overlayPanel.hide()
        }
    }
}
