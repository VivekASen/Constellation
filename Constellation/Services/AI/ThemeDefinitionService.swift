import Foundation

struct ThemeExplanation: Codable, Equatable {
    let summary: String
    let deepDive: String
    let connectionHint: String
    let watchFor: String
}

final class ThemeDefinitionService {
    static let shared = ThemeDefinitionService()

    private let definitions: [String: ThemeExplanation]

    private init() {
        self.definitions = Self.loadDefinitionsFromBundle()
    }

    func definition(for theme: String) -> String {
        let normalized = normalize(theme)
        if let explanation = definitions[normalized] {
            return explanation.summary
        }
        return "A recurring narrative idea focused on \(normalized.replacingOccurrences(of: "-", with: " "))."
    }

    func explanation(for theme: String, contextTitles: [String] = []) async -> ThemeExplanation {
        _ = contextTitles
        let normalized = normalize(theme)
        if let explanation = definitions[normalized] {
            return explanation
        }
        return fallbackExplanation(for: normalized)
    }

    private func fallbackExplanation(for theme: String) -> ThemeExplanation {
        let readable = theme.replacingOccurrences(of: "-", with: " ")
        return ThemeExplanation(
            summary: "\(readable.capitalized) appears when a story turns this pressure point into a defining test of values.",
            deepDive: "The theme becomes meaningful when choices around \(readable) produce consequences that reshape identity, trust, or power.",
            connectionHint: "Stories connect under this theme when they stage the same underlying tradeoff, even if the setting and genre differ.",
            watchFor: "Watch for turning points where preserving one value requires sacrificing another."
        )
    }

    private static func loadDefinitionsFromBundle() -> [String: ThemeExplanation] {
        let bundle = Bundle.main
        let candidateURLs: [URL?] = [
            bundle.url(forResource: "theme_definitions_library", withExtension: "json"),
            bundle.url(forResource: "theme_definitions_library", withExtension: "json", subdirectory: "Themes"),
            bundle.url(forResource: "theme_definitions_library", withExtension: "json", subdirectory: "Resources/Themes"),
            bundle.url(forResource: "theme_definitions_library", withExtension: "json", subdirectory: "Resources")
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([String: ThemeExplanation].self, from: data),
               !decoded.isEmpty {
                return decoded
            }
        }

        return [:]
    }

    private func normalize(_ raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^\p{L}\p{N}-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
