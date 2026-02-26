import Foundation

struct ReplacementRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var pattern: String = ""
    var replacement: String = ""
    var isEnabled: Bool = true
}

@Observable
final class ReplacementStore {
    var rules: [ReplacementRule] = []

    init() { load() }

    func apply(to text: String) -> String {
        var result = text
        for rule in rules where rule.isEnabled && !rule.pattern.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: rule.pattern)
            result = result.replacingOccurrences(
                of: "\\b\(escaped)\\b",
                with: rule.replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    func addRule() {
        rules.append(ReplacementRule())
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: "replacementRules")
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "replacementRules"),
              let decoded = try? JSONDecoder().decode([ReplacementRule].self, from: data) else { return }
        rules = decoded
    }
}
