import Foundation

@Observable
final class StatsStore {
    var totalWords: Int = 0
    var totalSessions: Int = 0
    var totalRecordingSeconds: Double = 0
    var wordsToday: Int = 0
    private var todayKey: String = ""

    var averageWPM: Double {
        guard totalRecordingSeconds > 5 else { return 0 }
        return Double(totalWords) / (totalRecordingSeconds / 60.0)
    }

    var formattedRecordingTime: String {
        let total = Int(totalRecordingSeconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 { return "\(hrs)h \(mins)m" }
        if mins > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }

    init() {
        let d = UserDefaults.standard
        totalWords = d.integer(forKey: "stats.totalWords")
        totalSessions = d.integer(forKey: "stats.totalSessions")
        totalRecordingSeconds = d.double(forKey: "stats.totalRecordingSeconds")

        let today = Self.todayString()
        todayKey = d.string(forKey: "stats.todayKey") ?? today
        wordsToday = todayKey == today ? d.integer(forKey: "stats.wordsToday") : 0
        todayKey = today
    }

    func recordSession(text: String, durationSeconds: Double) {
        let words = text.split(whereSeparator: \.isWhitespace).count
        totalWords += words
        totalSessions += 1
        totalRecordingSeconds += durationSeconds

        let today = Self.todayString()
        if todayKey != today {
            wordsToday = 0
            todayKey = today
        }
        wordsToday += words
        save()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(totalWords, forKey: "stats.totalWords")
        d.set(totalSessions, forKey: "stats.totalSessions")
        d.set(totalRecordingSeconds, forKey: "stats.totalRecordingSeconds")
        d.set(wordsToday, forKey: "stats.wordsToday")
        d.set(todayKey, forKey: "stats.todayKey")
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
