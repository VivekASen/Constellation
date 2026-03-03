import Foundation

final class ThemeExtractor {
    static let shared = ThemeExtractor()

    private let maxThemes = 5
    private let coreThemeLimit = 500

    private init() {}

    func extractThemes(from movie: Movie) async -> [String] {
        let request = ThemeMatchRequest(
            mediaType: "movie",
            title: movie.title,
            year: movie.year,
            overview: movie.overview,
            genres: movie.genres,
            notes: movie.notes
        )

        let shortlist = LocalThemeCandidateScorer.shared.shortlist(for: request, limit: 60, catalogLimit: coreThemeLimit)
        let matched = await GeminiThemeMatcherService.shared.matchThemes(
            from: request,
            candidateThemes: shortlist,
            maxThemes: maxThemes
        )

        let normalized = normalizeThemes(matched)
        if !normalized.isEmpty {
            return normalized
        }

        // If Gemini returns nothing, fall back to local scorer output first.
        let shortlistFallback = normalizeThemes(Array(shortlist.prefix(maxThemes)))
        if !shortlistFallback.isEmpty {
            return shortlistFallback
        }

        return fallbackThemes(fromGenres: movie.genres)
    }

    func extractThemes(from show: TVShow) async -> [String] {
        let request = ThemeMatchRequest(
            mediaType: "tv",
            title: show.title,
            year: show.year,
            overview: show.overview,
            genres: show.genres,
            notes: show.notes
        )

        let shortlist = LocalThemeCandidateScorer.shared.shortlist(for: request, limit: 60, catalogLimit: coreThemeLimit)
        let matched = await GeminiThemeMatcherService.shared.matchThemes(
            from: request,
            candidateThemes: shortlist,
            maxThemes: maxThemes
        )

        let normalized = normalizeThemes(matched)
        if !normalized.isEmpty {
            return normalized
        }

        let shortlistFallback = normalizeThemes(Array(shortlist.prefix(maxThemes)))
        if !shortlistFallback.isEmpty {
            return shortlistFallback
        }

        return fallbackThemes(fromGenres: show.genres)
    }

    func extractThemes(from book: Book) async -> [String] {
        let request = ThemeMatchRequest(
            mediaType: "book",
            title: book.title,
            year: book.year,
            overview: book.overview,
            genres: book.genres,
            notes: book.notes
        )

        let shortlist = LocalThemeCandidateScorer.shared.shortlist(for: request, limit: 60, catalogLimit: coreThemeLimit)
        let matched = await GeminiThemeMatcherService.shared.matchThemes(
            from: request,
            candidateThemes: shortlist,
            maxThemes: maxThemes
        )

        let normalized = normalizeThemes(matched)
        if !normalized.isEmpty {
            return normalized
        }

        let shortlistFallback = normalizeThemes(Array(shortlist.prefix(maxThemes)))
        if !shortlistFallback.isEmpty {
            return shortlistFallback
        }

        return fallbackThemes(fromGenres: book.genres)
    }

    func extractThemesFromText(_ text: String, context: String = "") async -> [String] {
        let seedTitle = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : context

        let request = ThemeMatchRequest(
            mediaType: "text",
            title: seedTitle,
            year: nil,
            overview: text,
            genres: [],
            notes: nil
        )

        let shortlist = LocalThemeCandidateScorer.shared.shortlist(for: request, limit: 60, catalogLimit: coreThemeLimit)
        let matched = await GeminiThemeMatcherService.shared.matchThemes(
            from: request,
            candidateThemes: shortlist,
            maxThemes: maxThemes
        )

        let normalized = normalizeThemes(matched)
        if !normalized.isEmpty {
            return normalized
        }

        return normalizeThemes(Array(shortlist.prefix(maxThemes)))
    }

    func normalizeThemes(_ themes: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for raw in themes {
            let cleaned = cleanTag(raw)
            guard cleaned.count >= 3, cleaned.count <= 64 else { continue }
            let canonical = TopThemeCatalog.shared.canonicalTheme(for: cleaned) ?? cleaned
            guard !seen.contains(canonical) else { continue }
            seen.insert(canonical)
            normalized.append(canonical)
            if normalized.count == maxThemes { break }
        }

        return normalized
    }

    private func cleanTag(_ raw: String) -> String {
        var value = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        value = value.replacingOccurrences(of: #"[^\p{L}\p{N}-]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func fallbackThemes(fromGenres genres: [String]) -> [String] {
        let mappings: [(needle: String, theme: String)] = [
            ("science-fiction", "technology"),
            ("sci-fi", "technology"),
            ("drama", "identity"),
            ("crime", "justice"),
            ("mystery", "mystery"),
            ("thriller", "fear"),
            ("romance", "love"),
            ("war", "war"),
            ("adventure", "adventure"),
            ("history", "legacy"),
            ("documentary", "social-commentary"),
            ("animation", "family"),
            ("family", "family"),
            ("fantasy", "discovery"),
            ("horror", "fear"),
            ("action", "survival"),
            ("comedy", "friendship")
        ]

        let normalizedGenres = genres.map(cleanTag)
        var picks: [String] = []

        for genre in normalizedGenres {
            for mapping in mappings where genre.contains(mapping.needle) {
                picks.append(mapping.theme)
            }
        }

        return normalizeThemes(picks)
    }
}
