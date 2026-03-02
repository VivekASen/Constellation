import Foundation

/// External topic expansion for discover queries.
/// Uses lightweight Wikipedia endpoints to broaden term coverage without LLMs.
final class TopicKnowledgeService {
    static let shared = TopicKnowledgeService()
    private init() {}
    private let awardsCache = AwardsSignalCache()

    private let stopTokens: Set<String> = [
        "the", "and", "with", "from", "about", "into", "over", "under", "your", "show", "movie",
        "movies", "tv", "series", "suggest", "suggestions", "more", "like", "that", "this", "for",
        "what", "when", "where", "which", "only", "watch", "watched"
    ]
    private let awardTerms: [String] = [
        "academy award", "academy awards", "oscar", "oscars",
        "golden globe", "golden globes",
        "bafta", "primetime emmy", "emmy award", "emmy awards",
        "won best picture", "nominated for"
    ]

    func expandTerms(for query: String) async -> [String] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var terms = Set<String>()
        terms.insert(normalizedQuery)
        terms.formUnion(seedTokens(from: normalizedQuery))

        let wikiTitles = await fetchWikipediaTitles(search: normalizedQuery)
        for title in wikiTitles.prefix(5) {
            let normalizedTitle = normalize(title)
            guard !normalizedTitle.isEmpty else { continue }
            terms.insert(normalizedTitle)
        }

        if let topTitle = wikiTitles.first {
            let summaryTerms = await fetchWikipediaSummaryTerms(title: topTitle)
            terms.formUnion(summaryTerms)
        }

        let ranked = terms
            .filter { !$0.isEmpty && $0.count >= 3 }
            .filter { !$0.allSatisfy(\.isNumber) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs < rhs }
                return lhs.count > rhs.count
            }

        return Array(ranked.prefix(10)).map { term in
            term.split(separator: " ").map { String($0).capitalized }.joined(separator: " ")
        }
    }

    func hasAwardsSignal(title: String, year: Int?, mediaHint: String) async -> Bool {
        let key = normalize([title, year.map(String.init) ?? "", mediaHint].joined(separator: "|"))
        if let cached = await awardsCache.get(key: key) {
            return cached
        }

        let awardSearches = [
            "\(title) \(year.map(String.init) ?? "") \(mediaHint)",
            "\(title) \(mediaHint)",
            title
        ]

        var hasSignal = false
        for search in awardSearches {
            let titles = await fetchWikipediaTitles(search: search)
            guard let best = titles.first else { continue }
            let summaryTerms = await fetchWikipediaSummaryTerms(title: best)
            let summaryText = summaryTerms.joined(separator: " ")
            if awardTerms.contains(where: { summaryText.contains(normalize($0)) }) {
                hasSignal = true
                break
            }
        }

        await awardsCache.set(key: key, value: hasSignal)
        return hasSignal
    }

    private func seedTokens(from normalizedQuery: String) -> Set<String> {
        Set(
            normalizedQuery
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 4 && !stopTokens.contains($0) }
        )
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchWikipediaTitles(search: String) async -> [String] {
        let escaped = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://en.wikipedia.org/w/api.php?action=opensearch&search=\(escaped)&limit=8&namespace=0&format=json"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            if let payload = try JSONSerialization.jsonObject(with: data) as? [Any],
               payload.count > 1,
               let titles = payload[1] as? [String] {
                return titles
            }
            return []
        } catch {
            return []
        }
    }

    private func fetchWikipediaSummaryTerms(title: String) async -> Set<String> {
        let escapedTitle = title
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let urlString = "https://en.wikipedia.org/api/rest_v1/page/summary/\(escapedTitle)"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let extract = json["extract"] as? String else {
                return []
            }
            let tokens = normalize(extract)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 5 && !stopTokens.contains($0) }
            return Set(tokens.prefix(12))
        } catch {
            return []
        }
    }
}

private actor AwardsSignalCache {
    private var store: [String: Bool] = [:]

    func get(key: String) -> Bool? {
        store[key]
    }

    func set(key: String, value: Bool) {
        store[key] = value
    }
}
