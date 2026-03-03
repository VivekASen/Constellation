import Foundation

/// Deterministic collection synthesis.
/// Produces concise, reliable insights without LLM dependencies.
final class SynthesisEngine {
    static let shared = SynthesisEngine()

    private init() {}

    func generateCollectionInsight(
        collectionName: String,
        movies: [Movie],
        tvShows: [TVShow],
        books: [Book]
    ) async -> String {
        guard !movies.isEmpty || !tvShows.isEmpty || !books.isEmpty else {
            return "Add a few items to this collection, then generate an insight."
        }

        let allThemes = ThemeExtractor.shared.normalizeThemes(movies.flatMap(\.themes) + tvShows.flatMap(\.themes) + books.flatMap(\.themes))
        let themeCounts = Dictionary(grouping: allThemes, by: { $0 }).mapValues(\.count)
        let topThemes = themeCounts.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }

        let primaryThemes = topThemes.prefix(3).map { $0.key.replacingOccurrences(of: "-", with: " ") }
        let primaryThemeText = primaryThemes.isEmpty ? "mixed topics" : primaryThemes.joined(separator: ", ")

        let movieThemeSet = Set(ThemeExtractor.shared.normalizeThemes(movies.flatMap(\.themes)))
        let showThemeSet = Set(ThemeExtractor.shared.normalizeThemes(tvShows.flatMap(\.themes)))
        let bookThemeSet = Set(ThemeExtractor.shared.normalizeThemes(books.flatMap(\.themes)))
        let crossMediaThemes = movieThemeSet.intersection(showThemeSet).union(movieThemeSet.intersection(bookThemeSet)).union(showThemeSet.intersection(bookThemeSet))
            .sorted()
            .prefix(2)
            .map { $0.replacingOccurrences(of: "-", with: " ") }

        let ratedItems = (movies.map(\.rating) + tvShows.map(\.rating) + books.map(\.rating)).compactMap { $0 }
        let avgRating = ratedItems.isEmpty ? nil : ratedItems.reduce(0, +) / Double(ratedItems.count)

        let opening = "\(collectionName) clusters around \(primaryThemeText)."

        let bridge: String
        if let firstCross = crossMediaThemes.first {
            bridge = "A strong cross-media bridge appears around \(firstCross), linking your movies and TV picks."
        } else if !movies.isEmpty && !tvShows.isEmpty && !books.isEmpty {
            bridge = "Movies, TV, and books are all represented, but with mostly distinct theme clusters right now."
        } else if !movies.isEmpty {
            bridge = "This collection is movie-heavy, which gives you a clear format focus."
        } else if !tvShows.isEmpty {
            bridge = "This collection is TV-heavy, which gives you a clear format focus."
        } else {
            bridge = "This collection is book-heavy, which gives you a clear format focus."
        }

        let qualityLine: String
        if let avgRating {
            qualityLine = "Your rated items average \(String(format: "%.1f", avgRating))/5, suggesting a solid fit with your taste."
        } else {
            qualityLine = "Add ratings to watched items so this collection can surface stronger quality signals."
        }

        let nextDirection = recommendationDirection(
            movies: movies,
            tvShows: tvShows,
            books: books,
            topTheme: topThemes.first?.key
        )

        return "\(opening) \(bridge) \(qualityLine) \(nextDirection)"
    }

    private func recommendationDirection(movies: [Movie], tvShows: [TVShow], books: [Book], topTheme: String?) -> String {
        if movies.isEmpty {
            return "Next, add one movie that reinforces this collection's strongest theme."
        }
        if tvShows.isEmpty {
            return "Next, add one TV show that reinforces this collection's strongest theme."
        }
        if books.isEmpty {
            return "Next, add one book that reinforces this collection's strongest theme."
        }

        if let topTheme {
            let readable = topTheme.replacingOccurrences(of: "-", with: " ")
            return "Next, add one title that deepens \(readable) while introducing a new creator or director."
        }

        return "Next, add one title that sharpens a specific theme to increase coherence."
    }
}
