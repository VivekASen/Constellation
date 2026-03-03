import Foundation
import NaturalLanguage

final class LocalThemeCandidateScorer {
    static let shared = LocalThemeCandidateScorer()

    private lazy var sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)

    private init() {}

    func shortlist(for request: ThemeMatchRequest, limit: Int = 80, catalogLimit: Int? = nil) -> [String] {
        let cappedLimit = max(10, min(limit, 200))
        let queryText = buildQueryText(from: request)
        let queryTokens = tokenize(queryText)

        let entries: [TopThemeCatalog.Entry]
        if let catalogLimit {
            entries = Array(TopThemeCatalog.shared.entries.prefix(max(1, catalogLimit)))
        } else {
            entries = TopThemeCatalog.shared.entries
        }
        guard !entries.isEmpty else { return [] }

        let lexicalScored: [(entry: TopThemeCatalog.Entry, score: Double)] = entries.compactMap { entry in
            let score = lexicalScore(entry: entry, queryText: queryText, queryTokens: queryTokens)
            return score > 0 ? (entry, score) : nil
        }

        let lexicalPool: [(entry: TopThemeCatalog.Entry, score: Double)]
        if lexicalScored.isEmpty {
            lexicalPool = Array(entries.prefix(300)).map { ($0, 0.01) }
        } else {
            lexicalPool = Array(
                lexicalScored
                    .sorted { $0.score > $1.score }
                    .prefix(300)
            )
        }

        let ranked = lexicalPool.map { item -> (String, Double) in
            let semantic = semanticScore(query: queryText, theme: item.entry.canonical)
            let final = (item.score * 0.68) + (semantic * 0.32)
            return (item.entry.canonical, final)
        }
        .sorted { $0.1 > $1.1 }

        var seen = Set<String>()
        var result: [String] = []
        for (theme, _) in ranked {
            guard !seen.contains(theme) else { continue }
            seen.insert(theme)
            result.append(theme)
            if result.count == cappedLimit { break }
        }

        if result.count < cappedLimit {
            for entry in entries {
                guard !seen.contains(entry.canonical) else { continue }
                seen.insert(entry.canonical)
                result.append(entry.canonical)
                if result.count == cappedLimit { break }
            }
        }

        return result
    }

    private func buildQueryText(from request: ThemeMatchRequest) -> String {
        let year = request.year.map(String.init) ?? ""
        let genres = request.genres.joined(separator: " ")
        return [request.title, year, request.overview ?? "", request.notes ?? "", genres]
            .joined(separator: " ")
            .lowercased()
    }

    private func lexicalScore(entry: TopThemeCatalog.Entry, queryText: String, queryTokens: Set<String>) -> Double {
        if queryText.isEmpty { return 0 }

        let overlap = queryTokens.intersection(entry.tokens).count
        var score = 0.0

        if overlap > 0 {
            score += (Double(overlap) * 2.2) / Double(max(entry.tokens.count, 1))
        }

        let phrase = entry.normalized.replacingOccurrences(of: "-", with: " ")
        if queryText.contains(phrase) {
            score += 1.8
        }

        if entry.tokens.count >= 2 {
            let joined = entry.tokens.joined(separator: " ")
            if queryText.contains(joined) {
                score += 0.8
            }
        }

        return score
    }

    private func semanticScore(query: String, theme: String) -> Double {
        let themePhrase = theme.replacingOccurrences(of: "-", with: " ")
        guard let embedding = sentenceEmbedding else {
            return jaccard(query, themePhrase)
        }

        let distance = embedding.distance(between: query, and: themePhrase)
        if !distance.isFinite {
            return jaccard(query, themePhrase)
        }

        return exp(-max(0, distance))
    }

    private func jaccard(_ left: String, _ right: String) -> Double {
        let l = tokenize(left)
        let r = tokenize(right)
        let union = l.union(r)
        guard !union.isEmpty else { return 0 }
        return Double(l.intersection(r).count) / Double(union.count)
    }

    private func tokenize(_ text: String) -> Set<String> {
        Set(
            text
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map { $0.lowercased() }
                .filter { $0.count >= 3 }
        )
    }
}
