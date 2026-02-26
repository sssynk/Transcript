import SwiftUI

enum TranscriptPhase: Equatable {
    case idle
    case recording
    case processing
    case success(String)
    case error(String)
}

enum OutputStyle: String, CaseIterable {
    case formal = "Formal"
    case noCapitals = "No Capitals"
    case casual = "Casual"
}

@Observable
final class AppState {
    var phase: TranscriptPhase = .idle
    var audioLevels: [CGFloat] = Array(repeating: 0, count: 5)

    var selectedDeviceUID: String = "" {
        didSet { UserDefaults.standard.set(selectedDeviceUID, forKey: "selectedMicUID") }
    }

    private var smoothedLevel: CGFloat = 0

    init() {
        selectedDeviceUID = UserDefaults.standard.string(forKey: "selectedMicUID") ?? ""
    }

    var isVisible: Bool {
        phase != .idle
    }

    func pushLevel(_ raw: CGFloat) {
        smoothedLevel = smoothedLevel * 0.3 + raw * 0.7
        audioLevels.removeFirst()
        audioLevels.append(smoothedLevel)
    }

    func resetLevels() {
        smoothedLevel = 0
        audioLevels = Array(repeating: 0, count: 5)
    }
}
