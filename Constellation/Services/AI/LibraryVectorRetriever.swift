import Foundation
import NaturalLanguage

/// Local vector retrieval layer for library + watchlist context.
/// This is intentionally provider-agnostic so we can swap in Qdrant/Typesense later.
final class LibraryVectorRetriever {
    static let shared = LibraryVectorRetriever()

    private let watchlistDefaultsKey = "discover.watchlist.embeddingItems"
    private lazy var sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)

    private init() {}

    func retrieve(
        query: String,
        understanding: QueryUnderstanding,
        userMovies: [Movie],
        userTVShows: [TVShow],
        maxNeighbors: Int = 10
    ) -> VectorRetrievalSnapshot {
        let documents = buildDocuments(
            understanding: understanding,
            userMovies: userMovies,
            userTVShows: userTVShows,
            watchlist: loadWatchlistItems()
        )

        let queryText = queryAnchorText(query: query, understanding: understanding)
        let neighbors = documents
            .map { document in
                VectorNeighbor(
                    documentID: document.documentID,
                    title: document.title,
                    mediaType: document.mediaType,
                    source: document.source,
                    score: similarity(queryText, document.vectorText)
                )
            }
            .sorted { $0.score > $1.score }

        return VectorRetrievalSnapshot(
            queryText: queryText,
            neighbors: Array(neighbors.prefix(maxNeighbors)),
            anchorTerms: anchorTerms(from: Array(neighbors.prefix(6)))
        )
    }

    func coherenceScore(
        queryText: String,
        candidateTitle: String,
        candidateOverview: String?,
        candidateGenres: [String] = [],
        snapshot: VectorRetrievalSnapshot
    ) -> Double {
        let candidateText = [candidateTitle, candidateOverview ?? "", candidateGenres.joined(separator: " ")]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !candidateText.isEmpty else { return 0 }

        let querySimilarity = similarity(queryText, candidateText)
        let anchorSimilarity = similarity(snapshot.anchorTerms.joined(separator: " "), candidateText)
        let nearestLibrarySimilarity = snapshot.neighbors.first.map { similarity($0.title, candidateTitle) } ?? 0

        // Blend direct intent fit with library-neighborhood fit.
        let blended = (0.65 * querySimilarity) + (0.25 * anchorSimilarity) + (0.10 * nearestLibrarySimilarity)
        return min(max(blended, 0), 1)
    }

    private func buildDocuments(
        understanding: QueryUnderstanding,
        userMovies: [Movie],
        userTVShows: [TVShow],
        watchlist: [WatchlistEmbeddingItem]
    ) -> [VectorDocument] {
        let movieDocs = userMovies.map { movie in
            VectorDocument(
                documentID: "movie:\(movie.id.uuidString)",
                title: movie.title,
                vectorText: [
                    movie.title,
                    movie.overview ?? "",
                    movie.notes ?? "",
                    movie.genres.joined(separator: " "),
                    movie.themes.joined(separator: " ")
                ].joined(separator: " "),
                mediaType: .movie,
                source: .library
            )
        }

        let tvDocs = userTVShows.map { show in
            VectorDocument(
                documentID: "tv:\(show.id.uuidString)",
                title: show.title,
                vectorText: [
                    show.title,
                    show.overview ?? "",
                    show.notes ?? "",
                    show.genres.joined(separator: " "),
                    show.themes.joined(separator: " ")
                ].joined(separator: " "),
                mediaType: .tv,
                source: .library
            )
        }

        let watchlistDocs = watchlist.map { item in
            VectorDocument(
                documentID: "watchlist:\(item.id)",
                title: item.title,
                vectorText: [
                    item.title,
                    item.overview ?? "",
                    item.genres.joined(separator: " "),
                    item.themes.joined(separator: " ")
                ].joined(separator: " "),
                mediaType: item.mediaType,
                source: .watchlist
            )
        }

        var documents = movieDocs + tvDocs + watchlistDocs

        // If the library is sparse, seed with current intent so coherence checks remain stable.
        if documents.isEmpty {
            let fallbackText = [understanding.themes.joined(separator: " "), understanding.genres.joined(separator: " "), understanding.mood]
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackText.isEmpty {
                documents = [
                    VectorDocument(
                        documentID: "intent:fallback",
                        title: fallbackText,
                        vectorText: fallbackText,
                        mediaType: .unknown,
                        source: .library
                    )
                ]
            }
        }

        return documents
    }

    private func queryAnchorText(query: String, understanding: QueryUnderstanding) -> String {
        let normalizedQuery = query
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "refine:", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "preference:", with: " ", options: .caseInsensitive)

        return [
            normalizedQuery,
            understanding.themes.joined(separator: " "),
            understanding.genres.joined(separator: " "),
            understanding.mood
        ]
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func anchorTerms(from neighbors: [VectorNeighbor]) -> [String] {
        let raw = neighbors
            .flatMap { neighbor in
                neighbor.title.lowercased()
                    .split(separator: " ")
                    .map(String.init)
            }
            .filter { $0.count >= 3 }
            .filter { !$0.allSatisfy(\.isNumber) }

        var counts: [String: Int] = [:]
        raw.forEach { counts[$0, default: 0] += 1 }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(8)
            .map(\.key)
    }

    private func similarity(_ a: String, _ b: String) -> Double {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        let lexical = lexicalSimilarity(left, right)
        if let embedding = sentenceEmbedding {
            let distance = embedding.distance(between: left, and: right)
            if distance.isFinite {
                // Exponential transform is more stable for sentence distances than (1 - distance).
                let semantic = exp(-max(0, distance))
                return min(max((semantic * 0.82) + (lexical * 0.18), 0), 1)
            }
        }

        return lexical
    }

    private func lexicalSimilarity(_ left: String, _ right: String) -> Double {
        let leftTokens = Set(left.lowercased().split(separator: " ").map(String.init))
        let rightTokens = Set(right.lowercased().split(separator: " ").map(String.init))
        let intersection = leftTokens.intersection(rightTokens).count
        let union = leftTokens.union(rightTokens).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func loadWatchlistItems() -> [WatchlistEmbeddingItem] {
        guard let data = UserDefaults.standard.data(forKey: watchlistDefaultsKey),
              let decoded = try? JSONDecoder().decode([WatchlistEmbeddingItem].self, from: data) else {
            return []
        }
        return decoded
    }
}

struct VectorRetrievalSnapshot {
    let queryText: String
    let neighbors: [VectorNeighbor]
    let anchorTerms: [String]
}

struct VectorNeighbor {
    let documentID: String
    let title: String
    let mediaType: VectorMediaType
    let source: VectorSourceType
    let score: Double
}

private struct VectorDocument {
    let documentID: String
    let title: String
    let vectorText: String
    let mediaType: VectorMediaType
    let source: VectorSourceType
}

enum VectorMediaType: String, Codable {
    case movie
    case tv
    case podcast
    case article
    case book
    case unknown
}

enum VectorSourceType: String, Codable {
    case library
    case watchlist
}

struct WatchlistEmbeddingItem: Codable {
    let id: String
    let title: String
    let overview: String?
    let genres: [String]
    let themes: [String]
    let mediaType: VectorMediaType
}
