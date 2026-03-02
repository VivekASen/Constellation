import Foundation
import SwiftData
import NaturalLanguage

/// Deterministic, on-device theme extraction.
/// No external LLM calls; uses weighted lexical signals + semantic canonicalization.
final class ThemeExtractor {
    static let shared = ThemeExtractor()

    private let thresholdDefaultsKey = "theme.semanticMatchThreshold"

    private let canonicalThemes: Set<String> = [
        "space-exploration", "sci-fi", "survival", "dystopia", "time-travel",
        "coming-of-age", "family-drama", "political-intrigue", "crime-investigation",
        "mystery", "war", "romance", "revenge", "friendship", "identity",
        "artificial-intelligence", "power-struggles", "psychological-thriller",
        "adventure", "heroism", "isolation", "corruption", "redemption",
        "moral-ambiguity", "social-commentary", "technology", "human-nature",
        "leadership", "sacrifice", "justice"
    ]

    /// Theme signal map can be expanded over time for better precision.
    private let themeSignals: [String: Set<String>] = [
        "space-exploration": ["space", "astronaut", "orbit", "mars", "galaxy", "cosmos", "interstellar", "spacecraft", "deep space"],
        "sci-fi": ["science fiction", "sci fi", "scifi", "futuristic", "cyberpunk", "future tech", "alien"],
        "survival": ["survival", "stranded", "endurance", "wilderness", "rescue", "catastrophe"],
        "dystopia": ["dystopia", "dystopian", "totalitarian", "post apocalyptic", "collapse"],
        "time-travel": ["time travel", "time loop", "temporal", "paradox", "alternate timeline"],
        "coming-of-age": ["coming of age", "adolescence", "growing up", "teen", "self discovery"],
        "family-drama": ["family", "parent", "siblings", "domestic", "family conflict"],
        "political-intrigue": ["politics", "political", "government", "election", "senate", "intrigue"],
        "crime-investigation": ["crime", "detective", "investigation", "forensic", "murder case", "police"],
        "mystery": ["mystery", "whodunit", "unsolved", "clues", "secret"],
        "war": ["war", "wwii", "world war", "battle", "military", "soldier", "frontline"],
        "romance": ["romance", "romantic", "love", "relationship", "affair"],
        "revenge": ["revenge", "vengeance", "payback", "retribution"],
        "friendship": ["friendship", "friends", "companionship", "bond"],
        "identity": ["identity", "self", "belonging", "who am i"],
        "artificial-intelligence": ["ai", "artificial intelligence", "machine intelligence", "android", "robot", "sentient"],
        "power-struggles": ["power struggle", "succession", "control", "dominance", "rivalry"],
        "psychological-thriller": ["psychological", "mind game", "obsession", "paranoia", "unreliable"],
        "adventure": ["adventure", "expedition", "quest", "journey", "discovery"],
        "heroism": ["hero", "heroic", "bravery", "courage", "savior"],
        "isolation": ["isolation", "alone", "solitude", "abandonment"],
        "corruption": ["corruption", "bribery", "abuse of power", "cover up"],
        "redemption": ["redemption", "atonement", "second chance", "forgiveness"],
        "moral-ambiguity": ["moral ambiguity", "ethical dilemma", "gray area", "compromise"],
        "social-commentary": ["social commentary", "satire", "class", "society", "inequality"],
        "technology": ["technology", "innovation", "surveillance", "digital", "algorithm"],
        "human-nature": ["human nature", "instinct", "behavior", "morality"],
        "leadership": ["leadership", "command", "captain", "strategy", "responsibility"],
        "sacrifice": ["sacrifice", "selfless", "loss", "tradeoff"],
        "justice": ["justice", "law", "court", "truth", "accountability"]
    ]

    private let genreBoosts: [String: [String]] = [
        "science fiction": ["sci-fi", "space-exploration", "artificial-intelligence", "technology"],
        "sci fi": ["sci-fi", "space-exploration", "artificial-intelligence", "technology"],
        "crime": ["crime-investigation", "mystery", "justice"],
        "mystery": ["mystery", "crime-investigation"],
        "war": ["war", "heroism", "sacrifice", "leadership"],
        "history": ["war", "power-struggles", "leadership"],
        "romance": ["romance", "family-drama"],
        "thriller": ["psychological-thriller", "moral-ambiguity", "mystery"],
        "adventure": ["adventure", "heroism", "survival"],
        "drama": ["moral-ambiguity", "identity", "family-drama", "human-nature"],
        "documentary": ["social-commentary", "justice", "technology"]
    ]

    private let stopTokens: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "about", "their",
        "movie", "show", "series", "story", "episode", "season", "film", "new", "old",
        "very", "just", "more", "less", "over", "under", "after", "before"
    ]

    private lazy var sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)

    // Live-tunable threshold via Settings.
    var semanticMatchThreshold: Double {
        let stored = UserDefaults.standard.object(forKey: thresholdDefaultsKey) as? Double
        let value = stored ?? 0.79
        return min(max(value, 0.60), 0.95)
    }

    func setSemanticMatchThreshold(_ value: Double) {
        let clamped = min(max(value, 0.60), 0.95)
        UserDefaults.standard.set(clamped, forKey: thresholdDefaultsKey)
    }

    private init() {}

    func extractThemes(from movie: Movie) async -> [String] {
        let tmdbKeywords: [String]
        if let tmdbID = movie.tmdbID {
            tmdbKeywords = (try? await TMDBService.shared.getMovieKeywords(movieID: tmdbID)) ?? []
        } else {
            tmdbKeywords = []
        }

        return deterministicExtract(
            title: movie.title,
            overview: movie.overview,
            genres: movie.genres,
            notes: movie.notes,
            metadataTokens: [movie.director ?? "", String(movie.year ?? 0)] + tmdbKeywords
        )
    }

    func extractThemes(from show: TVShow) async -> [String] {
        let tmdbKeywords: [String]
        if let tmdbID = show.tmdbID {
            tmdbKeywords = (try? await TMDBService.shared.getTVKeywords(tvID: tmdbID)) ?? []
        } else {
            tmdbKeywords = []
        }

        return deterministicExtract(
            title: show.title,
            overview: show.overview,
            genres: show.genres,
            notes: show.notes,
            metadataTokens: [show.creator ?? "", String(show.year ?? 0)] + tmdbKeywords
        )
    }

    func extractThemesFromText(_ text: String, context: String = "") async -> [String] {
        deterministicExtract(
            title: context,
            overview: text,
            genres: [],
            notes: nil,
            metadataTokens: []
        )
    }

    func normalizeThemes(_ themes: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for raw in themes {
            let cleaned = cleanTag(raw)
            guard cleaned.count > 2, cleaned.count < 40 else { continue }

            let normalized: String
            if canonicalThemes.contains(cleaned) {
                normalized = cleaned
            } else if let matchedCanonical = bestCanonicalMatch(for: cleaned) {
                normalized = matchedCanonical
            } else {
                normalized = cleaned
            }

            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }

        return Array(result.prefix(7))
    }

    private func deterministicExtract(
        title: String,
        overview: String?,
        genres: [String],
        notes: String?,
        metadataTokens: [String]
    ) -> [String] {
        let combined = [title, overview ?? "", notes ?? "", metadataTokens.joined(separator: " ")]
            .joined(separator: " ")
        let normalizedText = normalize(combined)
        let tokens = tokenize(normalizedText)
        let nounCandidates = extractNounCandidates(from: combined)

        var scores: [String: Double] = [:]

        for (theme, signals) in themeSignals {
            var score = 0.0
            for signal in signals {
                let key = normalize(signal)
                if key.contains(" ") {
                    if normalizedText.contains(key) {
                        score += key.count > 10 ? 1.7 : 1.4
                    }
                } else {
                    let hits = tokens.filter { $0 == key }.count
                    if hits > 0 {
                        score += min(2.0, 0.85 + Double(hits) * 0.45)
                    }
                }
            }
            if score > 0 {
                scores[theme, default: 0] += score
            }
        }

        for genre in genres {
            let normalizedGenre = normalize(genre)
            for (pattern, boostedThemes) in genreBoosts where normalizedGenre.contains(pattern) {
                for theme in boostedThemes {
                    scores[theme, default: 0] += 0.9
                }
            }
        }

        for candidate in nounCandidates {
            if let matched = bestCanonicalMatch(for: candidate) {
                scores[matched, default: 0] += 0.55
            }
        }

        var ranked = scores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)

        if ranked.count < 3 {
            let fallback = fallbackThemes(from: tokens, genres: genres)
            ranked.append(contentsOf: fallback)
        }

        let normalized = normalizeThemes(ranked)
        if normalized.count >= 3 { return Array(normalized.prefix(7)) }

        let extra = fallbackThemes(from: tokens, genres: genres)
        return normalizeThemes(normalized + extra)
    }

    private func fallbackThemes(from tokens: [String], genres: [String]) -> [String] {
        var themes: [String] = []

        for genre in genres {
            let normalizedGenre = cleanTag(genre)
            if let mapped = bestCanonicalMatch(for: normalizedGenre) {
                themes.append(mapped)
            }
        }

        let significant = tokens
            .filter { $0.count >= 4 && !stopTokens.contains($0) }
            .prefix(8)
            .map { cleanTag($0) }

        for token in significant {
            if let mapped = bestCanonicalMatch(for: token) {
                themes.append(mapped)
            } else {
                themes.append(token)
            }
        }

        return themes
    }

    private func extractNounCandidates(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var nouns: [String] = []
        let range = text.startIndex..<text.endIndex
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
            guard let tag else { return true }
            if tag == .noun {
                let token = String(text[tokenRange])
                let cleaned = cleanTag(token)
                if cleaned.count >= 4 && !stopTokens.contains(cleaned) {
                    nouns.append(cleaned)
                }
            }
            return true
        }

        return Array(NSOrderedSet(array: nouns)) as? [String] ?? []
    }

    private func tokenize(_ normalizedText: String) -> [String] {
        normalizedText
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanTag(_ raw: String) -> String {
        var value = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "_", with: "-")

        value = value.replacingOccurrences(of: #"[^\p{L}\p{N}\s-]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        value = value.replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return value
    }

    private func bestCanonicalMatch(for candidate: String) -> String? {
        let candidatePhrase = candidate.replacingOccurrences(of: "-", with: " ")
        var bestTag: String?
        var bestScore = 0.0

        for canonical in canonicalThemes {
            let canonicalPhrase = canonical.replacingOccurrences(of: "-", with: " ")
            let score = semanticSimilarity(candidatePhrase, canonicalPhrase)

            if score > bestScore {
                bestScore = score
                bestTag = canonical
            }
        }

        guard let bestTag, bestScore >= semanticMatchThreshold else {
            return nil
        }

        return bestTag
    }

    private func semanticSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }

        if let embedding = sentenceEmbedding {
            let distance = embedding.distance(between: a, and: b)
            if distance.isFinite {
                return max(0.0, 1.0 - distance)
            }
        }

        return jaccardSimilarity(a, b)
    }

    private func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let aSet = Set(a.split(separator: " ").map(String.init))
        let bSet = Set(b.split(separator: " ").map(String.init))
        guard !aSet.isEmpty || !bSet.isEmpty else { return 0.0 }

        let intersection = aSet.intersection(bSet).count
        let union = aSet.union(bSet).count
        return union == 0 ? 0.0 : Double(intersection) / Double(union)
    }
}
