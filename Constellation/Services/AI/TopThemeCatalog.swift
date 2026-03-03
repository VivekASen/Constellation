import Foundation

final class TopThemeCatalog {
    static let shared = TopThemeCatalog()

    struct Entry {
        let canonical: String
        let normalized: String
        let tokens: Set<String>
    }

    let themes: [String]
    let entries: [Entry]
    private let normalizedToTheme: [String: String]

    private init() {
        let loaded = Self.loadThemesFromBundle()
        self.themes = loaded.isEmpty ? Self.fallbackThemes : loaded

        var map: [String: String] = [:]
        var builtEntries: [Entry] = []
        for theme in themes {
            let normalized = Self.normalize(theme)
            map[normalized] = theme
            builtEntries.append(
                Entry(
                    canonical: theme,
                    normalized: normalized,
                    tokens: Set(normalized.split(separator: "-").map(String.init))
                )
            )
        }
        self.normalizedToTheme = map
        self.entries = builtEntries
    }

    func canonicalTheme(for candidate: String) -> String? {
        normalizedToTheme[Self.normalize(candidate)]
    }

    func coreThemes(limit: Int = 500) -> [String] {
        Array(themes.prefix(max(1, limit)))
    }

    private static func loadThemesFromBundle() -> [String] {
        let bundle = Bundle.main
        let candidateURLs: [URL?] = [
            bundle.url(forResource: "top_themes_library", withExtension: "txt"),
            bundle.url(forResource: "top_themes_library", withExtension: "txt", subdirectory: "Themes"),
            bundle.url(forResource: "top_themes_library", withExtension: "txt", subdirectory: "Resources/Themes"),
            bundle.url(forResource: "top_themes_library", withExtension: "txt", subdirectory: "Resources"),
            bundle.url(forResource: "top_themes_1000", withExtension: "txt"),
            bundle.url(forResource: "top_themes_1000", withExtension: "txt", subdirectory: "Themes"),
            bundle.url(forResource: "top_themes_1000", withExtension: "txt", subdirectory: "Resources/Themes"),
            bundle.url(forResource: "top_themes_1000", withExtension: "txt", subdirectory: "Resources")
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                let parsed = parseThemeFile(contents)
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }

        return []
    }

    private static func parseThemeFile(_ contents: String) -> [String] {
        var seen = Set<String>()
        var items: [String] = []

        for rawLine in contents.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let normalized = normalize(trimmed)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            items.append(trimmed)
        }

        return items
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^\p{L}\p{N}-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static let fallbackThemes: [String] = [
        "identity", "belonging", "justice", "corruption", "friendship", "family", "love", "loss", "grief", "redemption",
        "revenge", "survival", "hope", "despair", "power", "ambition", "betrayal", "loyalty", "forgiveness", "sacrifice"
    ]
}
