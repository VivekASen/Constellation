import Foundation

/// Deterministic parser for discovery intent.
/// No external LLM required.
final class DeterministicQueryUnderstandingEngine {
    static let shared = DeterministicQueryUnderstandingEngine()
    private init() {}

    private let genreKeywords: [String: Set<String>] = [
        "action": ["action", "combat", "fight", "warfare", "explosive"],
        "adventure": ["adventure", "expedition", "journey", "quest"],
        "animation": ["animation", "animated", "anime", "cartoon"],
        "comedy": ["comedy", "funny", "humor", "laugh"],
        "crime": ["crime", "detective", "investigation", "gangster", "mafia"],
        "documentary": ["documentary", "doc", "docuseries", "non fiction", "nonfiction"],
        "drama": ["drama", "dramatic", "character study"],
        "family": ["family", "kids", "children"],
        "fantasy": ["fantasy", "magic", "wizard", "dragon"],
        "history": ["history", "historical", "period"],
        "horror": ["horror", "scary", "terror", "supernatural"],
        "mystery": ["mystery", "whodunit", "murder mystery"],
        "romance": ["romance", "romantic", "love story"],
        "science fiction": ["science fiction", "sci fi", "scifi", "futuristic", "cyberpunk"],
        "thriller": ["thriller", "suspense", "intense"],
        "war": ["war", "ww2", "wwii", "world war", "military", "battle"]
    ]

    private let themeKeywords: [String: Set<String>] = [
        "world-war-ii": ["ww2", "wwii", "world war 2", "world war ii", "second world war"],
        "ancient-rome": ["ancient rome", "roman empire", "roman republic", "rome", "caesar"],
        "bees": ["bee", "bees", "beekeeping", "hive", "pollination", "honey bee", "honeybee"],
        "space-exploration": ["space", "astronaut", "cosmos", "mars", "galaxy"],
        "artificial-intelligence": ["ai", "artificial intelligence", "android", "robot"],
        "time-travel": ["time travel", "time machine", "temporal", "paradox"],
        "political-intrigue": ["political", "intrigue", "government", "election", "senate"],
        "crime-investigation": ["crime", "detective", "investigation", "forensic"],
        "mystery": ["mystery", "whodunit", "unsolved"],
        "survival": ["survival", "stranded", "survive"],
        "history": ["history", "historical", "period"],
        "nature": ["nature", "wildlife", "environment"]
    ]

    private let themeSeedTitles: [String: [String]] = [
        "world-war-ii": ["Saving Private Ryan", "Band of Brothers", "The Pianist", "Dunkirk", "The Pacific"],
        "ancient-rome": ["Gladiator", "Rome", "Spartacus", "Julius Caesar", "The Eagle"],
        "bees": ["More Than Honey", "Honeyland", "The Pollinators", "Bee Movie"],
        "space-exploration": ["Interstellar", "The Martian", "Apollo 13", "For All Mankind", "The Expanse"],
        "artificial-intelligence": ["Ex Machina", "Her", "Westworld", "Blade Runner 2049"],
        "time-travel": ["Dark", "Looper", "12 Monkeys", "Predestination"],
        "crime-investigation": ["True Detective", "Sherlock", "Zodiac", "Mindhunter"]
    ]

    func understand(_ rawQuery: String) -> QueryUnderstanding {
        let normalized = normalize(rawQuery)
        let tokens = tokenSet(normalized)

        var matchedGenres: Set<String> = []
        var matchedThemes: Set<String> = []

        for (genre, keywords) in genreKeywords where containsAny(normalized, tokens: tokens, keywords: keywords) {
            matchedGenres.insert(genre)
        }

        for (theme, keywords) in themeKeywords where containsAny(normalized, tokens: tokens, keywords: keywords) {
            matchedThemes.insert(theme)
        }

        if matchedThemes.isEmpty && matchedGenres.isEmpty {
            let significant = tokens.filter { $0.count >= 4 }
            if let first = significant.first {
                matchedThemes.insert(first.replacingOccurrences(of: " ", with: "-"))
            }
        }

        var suggestions: [String] = []
        for theme in matchedThemes.sorted() {
            suggestions.append(contentsOf: themeSeedTitles[theme] ?? [])
        }
        suggestions = Array(NSOrderedSet(array: suggestions)) as? [String] ?? []

        let mood: String
        if matchedGenres.contains("documentary") {
            mood = "informative and grounded"
        } else if matchedGenres.contains("thriller") || matchedGenres.contains("mystery") {
            mood = "tense and investigative"
        } else if matchedGenres.contains("science fiction") {
            mood = "thoughtful and speculative"
        } else {
            mood = normalized
        }

        return QueryUnderstanding(
            themes: matchedThemes.sorted(),
            genres: matchedGenres.sorted(),
            mood: mood,
            isGenre: !matchedGenres.isEmpty && matchedThemes.isEmpty,
            suggestions: suggestions
        )
    }

    private func containsAny(_ normalized: String, tokens: Set<String>, keywords: Set<String>) -> Bool {
        for keyword in keywords {
            let key = normalize(keyword)
            if key.contains(" ") {
                if normalized.contains(key) { return true }
            } else if tokens.contains(key) {
                return true
            }
        }
        return false
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "refine:", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "preference:", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSet(_ normalized: String) -> Set<String> {
        Set(normalized.split(separator: " ").map(String.init))
    }
}
