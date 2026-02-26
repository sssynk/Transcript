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

        let shouldDetectQuotations = UserDefaults.standard.object(forKey: "detectQuotations") as? Bool ?? false
        if shouldDetectQuotations {
            text = Self.detectLikelyQuotations(in: text)
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

    private static let speechVerbs: Set<String> = [
        "say", "says", "said", "tell", "tells", "told", "ask", "asks", "asked",
        "reply", "replies", "replied", "whisper", "whispers", "whispered",
        "shout", "shouts", "shouted", "yell", "yells", "yelled",
        "write", "writes", "wrote", "text", "texts", "texted",
        "message", "messages", "messaged", "goes", "went"
    ]

    private static let beVerbs: Set<String> = ["am", "is", "are", "was", "were", "be", "been", "being"]
    private static let quoteRecipients: Set<String> = ["me", "him", "her", "them", "us", "you"]
    private static let indirectOpeners: Set<String> = ["that", "if", "whether"]
    private static let discourseBoundaries: Set<String> = ["because", "since", "although", "though", "while"]
    private static let conjunctionBoundaries: Set<String> = ["and", "but", "then"]
    private static let likelySubjects: Set<String> = ["i", "you", "he", "she", "they", "we", "it"]
    private static let interjections: Set<String> = [
        "oh", "hey", "nah", "bro", "wow", "yo", "omg", "please", "no", "yes", "yeah", "yep", "nope", "wait"
    ]
    private static let imperativeStarters: Set<String> = [
        "go", "stop", "look", "listen", "wait", "come", "leave", "tell", "give", "take", "hold", "watch", "read", "check"
    ]
    private static let conversationalPronouns: Set<String> = [
        "i", "you", "me", "my", "mine", "your", "yours", "we", "us", "our", "ours"
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

    private static func detectLikelyQuotations(in text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return text }

        struct QuoteCandidate {
            let introducerEnd: Int
            let range: Range<Int>
        }

        var tokens = compact.split(separator: " ").map(String.init)
        guard tokens.count > 2 else { return compact }

        var candidates: [QuoteCandidate] = []
        var i = 0

        while i < tokens.count {
            let introducerLength = speechIntroducerLength(in: tokens, at: i)
            guard introducerLength > 0 else {
                i += 1
                continue
            }

            let introducerEnd = i + introducerLength - 1
            let start = adjustedQuoteStart(in: tokens, after: introducerEnd + 1)
            guard start < tokens.count else {
                i = introducerEnd + 1
                continue
            }

            if tokens[start].contains("\"") {
                i = start + 1
                continue
            }

            let firstWord = normalizedToken(tokens[start])
            if indirectOpeners.contains(firstWord) {
                i = start + 1
                continue
            }

            let end = quoteEnd(in: tokens, start: start)
            guard end > start else {
                i = start + 1
                continue
            }

            let range = start..<end
            if quoteScore(in: tokens, range: range) >= 2 {
                candidates.append(QuoteCandidate(introducerEnd: introducerEnd, range: range))
                i = end
            } else {
                i = start + 1
            }
        }

        guard !candidates.isEmpty else { return compact }

        for candidate in candidates {
            tokens[candidate.introducerEnd] = ensureIntroPunctuation(on: tokens[candidate.introducerEnd])

            let start = candidate.range.lowerBound
            let end = candidate.range.upperBound - 1
            if !tokens[start].hasPrefix("\"") {
                tokens[start] = "\"" + tokens[start]
            }

            let preferredEnding: Character = candidate.range.upperBound < tokens.count ? "," : "."
            tokens[end] = ensureClosingQuote(on: tokens[end], preferredPunctuation: preferredEnding)
        }

        return tokens.joined(separator: " ")
    }

    private static func speechIntroducerLength(in tokens: [String], at index: Int) -> Int {
        guard index < tokens.count else { return 0 }
        let current = normalizedToken(tokens[index])
        if speechVerbs.contains(current) {
            return 1
        }

        if beVerbs.contains(current), index + 1 < tokens.count, normalizedToken(tokens[index + 1]) == "like" {
            return 2
        }

        return 0
    }

    private static func adjustedQuoteStart(in tokens: [String], after index: Int) -> Int {
        guard index < tokens.count else { return index }
        var start = index
        if normalizedToken(tokens[start]) == "to",
           start + 1 < tokens.count,
           quoteRecipients.contains(normalizedToken(tokens[start + 1])) {
            start += 2
        } else if quoteRecipients.contains(normalizedToken(tokens[start])) {
            start += 1
        }
        return start
    }

    private static func quoteEnd(in tokens: [String], start: Int) -> Int {
        let maxWindow = 18
        let limit = min(tokens.count, start + maxWindow)
        var idx = start

        while idx < limit {
            if idx > start {
                if hasSentenceEnding(tokens[idx]) {
                    return idx + 1
                }

                if speechIntroducerLength(in: tokens, at: idx) > 0 {
                    return idx
                }

                let word = normalizedToken(tokens[idx])
                if discourseBoundaries.contains(word) {
                    return idx
                }

                if conjunctionBoundaries.contains(word), shouldBreakAtConjunction(in: tokens, index: idx) {
                    return idx
                }
            }
            idx += 1
        }

        return limit
    }

    private static func shouldBreakAtConjunction(in tokens: [String], index: Int) -> Bool {
        guard index + 1 < tokens.count else { return false }
        let next = normalizedToken(tokens[index + 1])
        if likelySubjects.contains(next) {
            return true
        }

        if speechIntroducerLength(in: tokens, at: index + 1) > 0 {
            return true
        }

        if index + 2 < tokens.count,
           likelySubjects.contains(next),
           speechIntroducerLength(in: tokens, at: index + 2) > 0 {
            return true
        }

        return false
    }

    private static func quoteScore(in tokens: [String], range: Range<Int>) -> Int {
        let words = tokens[range]
            .map { normalizedToken($0) }
            .filter { !$0.isEmpty }

        guard let first = words.first else { return Int.min }

        var score = 0
        if words.count <= 12 {
            score += 2
        } else if words.count <= 18 {
            score += 1
        } else {
            score -= 2
        }

        if indirectOpeners.contains(first) {
            score -= 4
        }

        if interjections.contains(first) || words.contains(where: interjections.contains) {
            score += 1
        }

        if imperativeStarters.contains(first) {
            score += 2
        }

        if words.contains(where: conversationalPronouns.contains) {
            score += 1
        }

        if words.contains(where: discourseBoundaries.contains) {
            score -= 1
        }

        return score
    }

    private static func normalizedToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(CharacterSet(charactersIn: "\"'")))
            .lowercased()
    }

    private static func hasSentenceEnding(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
    }

    private static func hasTrailingMark(_ token: String, marks: Set<Character>) -> Bool {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard let last = trimmed.last else { return false }
        return marks.contains(last)
    }

    private static func ensureIntroPunctuation(on token: String) -> String {
        let existing: Set<Character> = [",", ":", ";", ".", "!", "?"]
        if hasTrailingMark(token, marks: existing) {
            return token
        }
        return token + ","
    }

    private static func ensureClosingQuote(on token: String, preferredPunctuation: Character) -> String {
        var core = token
        if core.hasSuffix("\"") {
            core.removeLast()
        }

        let endings: Set<Character> = [".", "!", "?", ","]
        if !hasTrailingMark(core, marks: endings) {
            core.append(preferredPunctuation)
        }

        core.append("\"")
        return core
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
