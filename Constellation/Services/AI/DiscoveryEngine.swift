//
//  DiscoveryEngine.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import Foundation
import SwiftData

class DiscoveryEngine {
    static let shared = DiscoveryEngine()
    private let deterministicUnderstanding = DeterministicQueryUnderstandingEngine.shared
    
    private init() {}
    
    func discover(
        interest: String,
        userMovies: [Movie],
        userTVShows: [TVShow],
        excludedMovieIDs: Set<Int> = [],
        excludedTVIDs: Set<Int> = []
    ) async -> DiscoveryResult {
        _ = userMovies
        _ = userTVShows
        let understanding = await understandQuery(interest)
        let preferredMode = preferredMediaMode(from: interest)
        let rawTaste = (try? await TasteDiveService.shared.similar(query: interest, type: nil, limit: 20)) ?? []

        var movies: [TMDBMovie] = []
        var tvShows: [TMDBTVShow] = []
        var movieReasons: [Int: String] = [:]
        var tvReasons: [Int: String] = [:]
        var movieCoherence: [Int: Double] = [:]
        var tvCoherence: [Int: Double] = [:]
        var movieSemantic: [Int: Double] = [:]
        var tvSemantic: [Int: Double] = [:]
        var movieScore: [Int: Double] = [:]
        var tvScore: [Int: Double] = [:]

        for item in rawTaste {
            let mediaKind = parseTasteType(item.type)
            switch mediaKind {
            case .movieOnly where preferredMode != .tvOnly:
                let movie = syntheticMovie(from: item.name)
                guard !excludedMovieIDs.contains(movie.id) else { continue }
                guard !movies.contains(where: { $0.id == movie.id }) else { continue }
                movies.append(movie)
                movieReasons[movie.id] = "Taste graph match"
                movieCoherence[movie.id] = 1.0
                movieSemantic[movie.id] = 1.0
                movieScore[movie.id] = 1.0
            case .tvOnly where preferredMode != .movieOnly:
                let show = syntheticTVShow(from: item.name)
                guard !excludedTVIDs.contains(show.id) else { continue }
                guard !tvShows.contains(where: { $0.id == show.id }) else { continue }
                tvShows.append(show)
                tvReasons[show.id] = "Taste graph match"
                tvCoherence[show.id] = 1.0
                tvSemantic[show.id] = 1.0
                tvScore[show.id] = 1.0
            default:
                continue
            }
        }

        // Fallback for cases where TasteDive does not label item type.
        if movies.isEmpty && preferredMode != .tvOnly {
            for item in rawTaste.prefix(8) {
                let movie = syntheticMovie(from: item.name)
                guard !excludedMovieIDs.contains(movie.id) else { continue }
                guard !movies.contains(where: { $0.id == movie.id }) else { continue }
                movies.append(movie)
                movieReasons[movie.id] = "Taste graph match"
                movieCoherence[movie.id] = 1.0
                movieSemantic[movie.id] = 1.0
                movieScore[movie.id] = 1.0
            }
        }

        return DiscoveryResult(
            query: interest,
            understanding: understanding,
            inLibraryMovies: [],
            inLibraryTVShows: [],
            recommendations: movies,
            tvRecommendations: tvShows,
            movieRecommendationReasons: movieReasons,
            tvRecommendationReasons: tvReasons,
            movieRecommendationCoherence: movieCoherence,
            tvRecommendationCoherence: tvCoherence,
            movieRecommendationSemantic: movieSemantic,
            tvRecommendationSemantic: tvSemantic,
            movieRecommendationScore: movieScore,
            tvRecommendationScore: tvScore,
            followUpQuestions: [],
            connections: []
        )
    }
    
    private func understandQuery(_ query: String) async -> QueryUnderstanding {
        // Deterministic local parsing keeps discovery fast and free on phone.
        let parsed = deterministicUnderstanding.understand(query)
        return enrichUnderstanding(parsed, for: query)
    }
    
    private func findIntelligentMovieMatches(
        understanding: QueryUnderstanding,
        in movies: [Movie]
    ) -> [Movie] {
        let queryThemes = Set(ThemeExtractor.shared.normalizeThemes(understanding.themes))
        let queryGenres = understanding.genres.map(normalizeForCompare)
        
        return movies.filter { movie in
            let movieThemes = Set(ThemeExtractor.shared.normalizeThemes(movie.themes))
            let themeMatch = !movieThemes.isDisjoint(with: queryThemes)
            
            let genreMatch = movie.genres.contains { movieGenre in
                let normalizedMovieGenre = normalizeForCompare(movieGenre)
                return queryGenres.contains(normalizedMovieGenre)
            }
            
            let suggestionMatch = understanding.suggestions.contains { suggestion in
                movie.title.lowercased().contains(suggestion.lowercased()) ||
                suggestion.lowercased().contains(movie.title.lowercased())
            }
            
            return themeMatch || genreMatch || suggestionMatch
        }
    }
    
    private func findIntelligentTVMatches(
        understanding: QueryUnderstanding,
        in shows: [TVShow]
    ) -> [TVShow] {
        let queryThemes = Set(ThemeExtractor.shared.normalizeThemes(understanding.themes))
        let queryGenres = understanding.genres.map(normalizeForCompare)
        
        return shows.filter { show in
            let showThemes = Set(ThemeExtractor.shared.normalizeThemes(show.themes))
            let themeMatch = !showThemes.isDisjoint(with: queryThemes)
            
            let genreMatch = show.genres.contains { showGenre in
                let normalizedShowGenre = normalizeForCompare(showGenre)
                return queryGenres.contains(normalizedShowGenre)
            }
            
            let suggestionMatch = understanding.suggestions.contains { suggestion in
                show.title.lowercased().contains(suggestion.lowercased()) ||
                suggestion.lowercased().contains(show.title.lowercased())
            }
            
            return themeMatch || genreMatch || suggestionMatch
        }
    }
    
    private func generateFollowUpQuestions(
        understanding: QueryUnderstanding,
        movieMatches: [Movie],
        tvMatches: [TVShow],
        movieRecommendations: [TMDBMovie],
        tvRecommendations: [TMDBTVShow]
    ) -> [FollowUpQuestion] {
        var questions: [FollowUpQuestion] = []
        
        if movieRecommendations.count > 2 || tvRecommendations.count > 2 || !tvMatches.isEmpty {
            questions.append(FollowUpQuestion(
                text: "What format are you in the mood for?",
                options: ["Movies", "TV Shows", "Documentaries", "Any"]
            ))
        }
        
        if understanding.isGenre {
            questions.append(FollowUpQuestion(
                text: "What vibe are you looking for?",
                options: ["Action-packed", "Thoughtful", "Fun & light", "Dark & serious"]
            ))
        }
        
        if let firstMovie = movieMatches.first {
            questions.append(FollowUpQuestion(
                text: "Want more like \(firstMovie.title)?",
                options: ["Yes", "No, surprise me"]
            ))
        } else if let firstShow = tvMatches.first {
            questions.append(FollowUpQuestion(
                text: "Want more like \(firstShow.title)?",
                options: ["Yes", "No, surprise me"]
            ))
        }
        
        return questions
    }
    
    private func findConnections(inMovies movies: [Movie], tvShows: [TVShow]) -> [Connection] {
        var connections: [Connection] = []
        
        for i in 0..<movies.count {
            for j in (i + 1)..<movies.count {
                let movie1 = movies[i]
                let movie2 = movies[j]
                
                if let dir1 = movie1.director, let dir2 = movie2.director, dir1 == dir2 {
                    connections.append(Connection(
                        from: movie1.title,
                        to: movie2.title,
                        reason: "Same director: \(dir1)"
                    ))
                }
                
                let sharedThemes = Set(ThemeExtractor.shared.normalizeThemes(movie1.themes))
                    .intersection(Set(ThemeExtractor.shared.normalizeThemes(movie2.themes)))
                
                if let theme = sharedThemes.first {
                    connections.append(Connection(
                        from: movie1.title,
                        to: movie2.title,
                        reason: "Both explore \(theme)"
                    ))
                }
            }
        }
        
        for i in 0..<tvShows.count {
            for j in (i + 1)..<tvShows.count {
                let show1 = tvShows[i]
                let show2 = tvShows[j]
                
                if let creator1 = show1.creator, let creator2 = show2.creator, creator1 == creator2 {
                    connections.append(Connection(
                        from: show1.title,
                        to: show2.title,
                        reason: "Same creator: \(creator1)"
                    ))
                }
                
                let sharedThemes = Set(ThemeExtractor.shared.normalizeThemes(show1.themes))
                    .intersection(Set(ThemeExtractor.shared.normalizeThemes(show2.themes)))
                
                if let theme = sharedThemes.first {
                    connections.append(Connection(
                        from: show1.title,
                        to: show2.title,
                        reason: "Both explore \(theme)"
                    ))
                }
            }
        }
        
        for movie in movies {
            for show in tvShows {
                let sharedThemes = Set(ThemeExtractor.shared.normalizeThemes(movie.themes))
                    .intersection(Set(ThemeExtractor.shared.normalizeThemes(show.themes)))
                
                if let theme = sharedThemes.first {
                    connections.append(Connection(
                        from: movie.title,
                        to: show.title,
                        reason: "Cross-media overlap: \(theme)"
                    ))
                }
            }
        }
        
        return Array(connections.prefix(12))
    }
    
    private func normalizeForCompare(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func enrichUnderstanding(_ understanding: QueryUnderstanding, for query: String) -> QueryUnderstanding {
        let cleanSuggestions = understanding.suggestions
            .map(normalizeForCompare)
            .filter { $0.count >= 4 }
            .map {
                $0.split(separator: " ").map { String($0).capitalized }.joined(separator: " ")
            }
        var suggestions = cleanSuggestions
        if suggestions.isEmpty {
            suggestions = [query]
        }
        
        let themes = understanding.themes.isEmpty
            ? ThemeExtractor.shared.normalizeThemes([normalizeForCompare(query)])
            : understanding.themes
        
        let mood = understanding.mood.isEmpty ? normalizeForCompare(query) : understanding.mood
        
        return QueryUnderstanding(
            themes: themes,
            genres: understanding.genres.map(normalizeForCompare),
            mood: mood,
            isGenre: understanding.isGenre,
            suggestions: suggestions
        )
    }

    private func mergeMovieRecommendations(
        base: [TMDBMovie],
        taste: [ScoredMovieRecommendation]
    ) -> [ScoredMovieRecommendation] {
        var seen = Set<Int>()
        var merged: [ScoredMovieRecommendation] = []

        for item in taste.sorted(by: { $0.score > $1.score }) where seen.insert(item.movie.id).inserted {
            merged.append(item)
        }
        for movie in base where seen.insert(movie.id).inserted {
            merged.append(
                ScoredMovieRecommendation(
                    movie: movie,
                    reason: "Matched against your topic and viewing profile",
                    score: defaultScore(voteAverage: movie.voteAverage, voteCount: movie.voteCount),
                    coherence: 0.24,
                    semantic: 0.18
                )
            )
        }

        return merged
    }

    private func mergeTVRecommendations(
        base: [TMDBTVShow],
        taste: [ScoredTVRecommendation]
    ) -> [ScoredTVRecommendation] {
        var seen = Set<Int>()
        var merged: [ScoredTVRecommendation] = []

        for item in taste.sorted(by: { $0.score > $1.score }) where seen.insert(item.show.id).inserted {
            merged.append(item)
        }
        for show in base where seen.insert(show.id).inserted {
            merged.append(
                ScoredTVRecommendation(
                    show: show,
                    reason: "Matched against your topic and viewing profile",
                    score: defaultScore(voteAverage: show.voteAverage, voteCount: show.voteCount),
                    coherence: 0.24,
                    semantic: 0.18
                )
            )
        }

        return merged
    }

    private func fetchTasteDiveCandidates(
        interest: String,
        understanding: QueryUnderstanding,
        preferredMode: PreferredDiscoveryMediaMode
    ) async -> TasteCandidateBundle {
        let seedQueries = Array(
            NSOrderedSet(array: [interest] + understanding.suggestions.prefix(3))
        ) as? [String] ?? [interest]

        var rawTasteResults: [TasteDiveResult] = []
        for seed in seedQueries.prefix(2) {
            switch preferredMode {
            case .movieOnly:
                let results = (try? await TasteDiveService.shared.similar(query: seed, type: .movie, limit: 10)) ?? []
                rawTasteResults.append(contentsOf: results)
            case .tvOnly:
                let results = (try? await TasteDiveService.shared.similar(query: seed, type: .show, limit: 10)) ?? []
                rawTasteResults.append(contentsOf: results)
            case .any:
                let movieResults = (try? await TasteDiveService.shared.similar(query: seed, type: .movie, limit: 8)) ?? []
                let showResults = (try? await TasteDiveService.shared.similar(query: seed, type: .show, limit: 8)) ?? []
                rawTasteResults.append(contentsOf: movieResults)
                rawTasteResults.append(contentsOf: showResults)
            }
        }

        let dedupedTaste = dedupeTasteResults(rawTasteResults)
        guard !dedupedTaste.isEmpty else { return TasteCandidateBundle(movies: [], tvShows: []) }

        let personalTerms = personalPreferenceTerms(from: understanding)
        var movieBoosts: [ScoredMovieRecommendation] = []
        var tvBoosts: [ScoredTVRecommendation] = []

        for taste in dedupedTaste.prefix(8) {
            let hint = parseTasteType(taste.type)

            if preferredMode != .tvOnly, hint != .tvOnly,
               let movie = await resolveMovieCandidate(from: taste.name) {
                let score = blendedTasteScore(
                    title: movie.title,
                    overview: movie.overview,
                    voteAverage: movie.voteAverage,
                    voteCount: movie.voteCount,
                    personalTerms: personalTerms,
                    sourceBoost: 1.35
                )
                movieBoosts.append(
                    ScoredMovieRecommendation(
                        movie: movie,
                        reason: "Taste graph match: \(taste.name)",
                        score: score,
                        coherence: min(0.92, 0.30 + score / 12.0),
                        semantic: min(0.92, 0.24 + score / 14.0)
                    )
                )
            }

            if preferredMode != .movieOnly, hint != .movieOnly,
               let show = await resolveTVCandidate(from: taste.name) {
                let score = blendedTasteScore(
                    title: show.title,
                    overview: show.overview,
                    voteAverage: show.voteAverage,
                    voteCount: show.voteCount,
                    personalTerms: personalTerms,
                    sourceBoost: 1.35
                )
                tvBoosts.append(
                    ScoredTVRecommendation(
                        show: show,
                        reason: "Taste graph match: \(taste.name)",
                        score: score,
                        coherence: min(0.92, 0.30 + score / 12.0),
                        semantic: min(0.92, 0.24 + score / 14.0)
                    )
                )
            }
        }

        return TasteCandidateBundle(
            movies: dedupeScoredMovies(movieBoosts),
            tvShows: dedupeScoredTVShows(tvBoosts)
        )
    }

    private func fetchTasteDiveCandidatesStrict(
        interest: String,
        understanding: QueryUnderstanding,
        preferredMode: PreferredDiscoveryMediaMode
    ) async -> TasteCandidateBundle {
        let seedQueries = Array(
            NSOrderedSet(array: [interest] + understanding.suggestions.prefix(3))
        ) as? [String] ?? [interest]

        var rawTasteResults: [TasteDiveResult] = []
        for seed in seedQueries.prefix(2) {
            switch preferredMode {
            case .movieOnly:
                let results = (try? await TasteDiveService.shared.similar(query: seed, type: .movie, limit: 10)) ?? []
                rawTasteResults.append(contentsOf: results)
            case .tvOnly:
                let results = (try? await TasteDiveService.shared.similar(query: seed, type: .show, limit: 10)) ?? []
                rawTasteResults.append(contentsOf: results)
            case .any:
                let movieResults = (try? await TasteDiveService.shared.similar(query: seed, type: .movie, limit: 8)) ?? []
                let showResults = (try? await TasteDiveService.shared.similar(query: seed, type: .show, limit: 8)) ?? []
                rawTasteResults.append(contentsOf: movieResults)
                rawTasteResults.append(contentsOf: showResults)
            }
        }

        let dedupedTaste = dedupeTasteResults(rawTasteResults)
        guard !dedupedTaste.isEmpty else { return TasteCandidateBundle(movies: [], tvShows: []) }

        let personalTerms = personalPreferenceTerms(from: understanding)
        var movieBoosts: [ScoredMovieRecommendation] = []
        var tvBoosts: [ScoredTVRecommendation] = []

        for taste in dedupedTaste {
            let hint = parseTasteType(taste.type)

            if preferredMode != .tvOnly, hint != .tvOnly,
               let movie = await resolveMovieCandidate(from: taste.name, minSimilarity: 0.52) {
                let score = blendedTasteScore(
                    title: movie.title,
                    overview: movie.overview,
                    voteAverage: movie.voteAverage,
                    voteCount: movie.voteCount,
                    personalTerms: personalTerms,
                    sourceBoost: 1.35
                )
                movieBoosts.append(
                    ScoredMovieRecommendation(
                        movie: movie,
                        reason: "Taste graph match: \(taste.name)",
                        score: score,
                        coherence: min(0.92, 0.34 + score / 12.0),
                        semantic: min(0.92, 0.28 + score / 14.0)
                    )
                )
            }

            if preferredMode != .movieOnly, hint != .movieOnly,
               let show = await resolveTVCandidate(from: taste.name, minSimilarity: 0.52) {
                let score = blendedTasteScore(
                    title: show.title,
                    overview: show.overview,
                    voteAverage: show.voteAverage,
                    voteCount: show.voteCount,
                    personalTerms: personalTerms,
                    sourceBoost: 1.35
                )
                tvBoosts.append(
                    ScoredTVRecommendation(
                        show: show,
                        reason: "Taste graph match: \(taste.name)",
                        score: score,
                        coherence: min(0.92, 0.34 + score / 12.0),
                        semantic: min(0.92, 0.28 + score / 14.0)
                    )
                )
            }
        }

        return TasteCandidateBundle(
            movies: dedupeScoredMoviesInOrder(movieBoosts),
            tvShows: dedupeScoredTVShowsInOrder(tvBoosts)
        )
    }

    private func dedupeTasteResults(_ results: [TasteDiveResult]) -> [TasteDiveResult] {
        var seen = Set<String>()
        return results.filter { item in
            let key = normalizeForCompare(item.name)
            guard !key.isEmpty else { return false }
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func resolveMovieCandidate(from title: String, minSimilarity: Double = 0.72) async -> TMDBMovie? {
        let results = (try? await TMDBService.shared.searchMovies(query: title, page: 1)) ?? []
        let best = results
            .filter { ($0.voteCount ?? 0) >= 40 || ($0.voteAverage ?? 0) >= 6.8 }
            .sorted { lhs, rhs in
                let lhsSim = normalizedTitleSimilarity(title, lhs.title)
                let rhsSim = normalizedTitleSimilarity(title, rhs.title)
                if lhsSim != rhsSim { return lhsSim > rhsSim }
                let l = defaultScore(voteAverage: lhs.voteAverage, voteCount: lhs.voteCount)
                let r = defaultScore(voteAverage: rhs.voteAverage, voteCount: rhs.voteCount)
                return l > r
            }
            .first
        guard let best else { return nil }

        guard normalizedTitleSimilarity(title, best.title) >= minSimilarity else {
            return nil
        }
        return best
    }

    private func resolveTVCandidate(from title: String, minSimilarity: Double = 0.72) async -> TMDBTVShow? {
        let results = (try? await TMDBService.shared.searchTVShows(query: title, page: 1)) ?? []
        let best = results
            .filter { ($0.voteCount ?? 0) >= 30 || ($0.voteAverage ?? 0) >= 6.8 }
            .sorted { lhs, rhs in
                let lhsSim = normalizedTitleSimilarity(title, lhs.title)
                let rhsSim = normalizedTitleSimilarity(title, rhs.title)
                if lhsSim != rhsSim { return lhsSim > rhsSim }
                let l = defaultScore(voteAverage: lhs.voteAverage, voteCount: lhs.voteCount)
                let r = defaultScore(voteAverage: rhs.voteAverage, voteCount: rhs.voteCount)
                return l > r
            }
            .first
        guard let best else { return nil }

        guard normalizedTitleSimilarity(title, best.title) >= minSimilarity else {
            return nil
        }
        return best
    }

    private func defaultScore(voteAverage: Double?, voteCount: Int?) -> Double {
        (voteAverage ?? 0) * 0.86 + log10(Double(max(voteCount ?? 1, 1)))
    }

    private func personalPreferenceTerms(from understanding: QueryUnderstanding) -> Set<String> {
        let raw = understanding.themes + understanding.genres + understanding.suggestions
        let normalized = raw
            .map(normalizeForCompare)
            .flatMap { $0.split(separator: " ").map(String.init) }
            .filter { $0.count > 2 }
        return Set(normalized)
    }

    private func blendedTasteScore(
        title: String,
        overview: String?,
        voteAverage: Double?,
        voteCount: Int?,
        personalTerms: Set<String>,
        sourceBoost: Double
    ) -> Double {
        let popularity = defaultScore(voteAverage: voteAverage, voteCount: voteCount)
        let text = normalizeForCompare(title + " " + (overview ?? ""))
        let overlap = personalTerms.reduce(into: 0) { acc, term in
            if text.contains(term) { acc += 1 }
        }
        let personal = min(Double(overlap) * 0.4, 2.8)
        return popularity + personal + sourceBoost
    }

    private func dedupeScoredMovies(_ items: [ScoredMovieRecommendation]) -> [ScoredMovieRecommendation] {
        var seen = Set<Int>()
        return items
            .sorted(by: { $0.score > $1.score })
            .filter { seen.insert($0.movie.id).inserted }
    }

    private func dedupeScoredTVShows(_ items: [ScoredTVRecommendation]) -> [ScoredTVRecommendation] {
        var seen = Set<Int>()
        return items
            .sorted(by: { $0.score > $1.score })
            .filter { seen.insert($0.show.id).inserted }
    }

    private func parseTasteType(_ raw: String?) -> TasteTypeHint {
        guard let value = raw?.lowercased() else { return .unknown }
        if value.contains("movie") { return .movieOnly }
        if value.contains("show") || value.contains("tv") { return .tvOnly }
        return .unknown
    }

    private func normalizedTitleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(
            normalizeForCompare(lhs)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 }
        )
        let right = Set(
            normalizeForCompare(rhs)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 }
        )
        guard !left.isEmpty && !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        let jaccard = union == 0 ? 0 : Double(intersection) / Double(union)
        let containment = Double(intersection) / Double(min(left.count, right.count))
        return max(jaccard, containment * 0.9)
    }

    private func dedupeScoredMoviesInOrder(_ items: [ScoredMovieRecommendation]) -> [ScoredMovieRecommendation] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.movie.id).inserted }
    }

    private func dedupeScoredTVShowsInOrder(_ items: [ScoredTVRecommendation]) -> [ScoredTVRecommendation] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.show.id).inserted }
    }

    private func syntheticMovie(from title: String) -> TMDBMovie {
        TMDBMovie(
            id: syntheticID(type: "movie", title: title),
            title: title,
            overview: nil,
            posterPath: nil,
            releaseDate: nil,
            voteAverage: nil,
            voteCount: nil,
            genreIDs: nil
        )
    }

    private func syntheticTVShow(from title: String) -> TMDBTVShow {
        TMDBTVShow(
            id: syntheticID(type: "show", title: title),
            name: title,
            overview: nil,
            posterPath: nil,
            firstAirDate: nil,
            voteAverage: nil,
            voteCount: nil,
            genreIDs: nil
        )
    }

    private func syntheticID(type: String, title: String) -> Int {
        let input = "\(type)-\(normalizeForCompare(title))"
        var hash: UInt64 = 1469598103934665603
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Int(truncatingIfNeeded: hash & 0x7FFF_FFFF)
    }
}

private enum PreferredDiscoveryMediaMode {
    case any
    case movieOnly
    case tvOnly
}

private extension DiscoveryEngine {
    func preferredMediaMode(from interest: String) -> PreferredDiscoveryMediaMode {
        let value = interest.lowercased()
        let hasMovieOnly = value.contains("movie only")
            || value.contains("movies only")
            || value.contains("films only")
        let hasTVOnly = value.contains("tv only")
            || value.contains("tv shows only")
            || value.contains("show only")
            || value.contains("series only")

        if hasMovieOnly && !hasTVOnly { return .movieOnly }
        if hasTVOnly && !hasMovieOnly { return .tvOnly }
        return .any
    }
}

struct QueryUnderstanding {
    let themes: [String]
    let genres: [String]
    let mood: String
    let isGenre: Bool
    let suggestions: [String]
}

struct UnderstandingJSON: Codable {
    let themes: [String]
    let genres: [String]
    let mood: String
    let isGenre: Bool
    let suggestions: [String]
}

struct DiscoveryResult {
    let query: String
    let understanding: QueryUnderstanding
    let inLibraryMovies: [Movie]
    let inLibraryTVShows: [TVShow]
    let recommendations: [TMDBMovie]
    let tvRecommendations: [TMDBTVShow]
    let movieRecommendationReasons: [Int: String]
    let tvRecommendationReasons: [Int: String]
    let movieRecommendationCoherence: [Int: Double]
    let tvRecommendationCoherence: [Int: Double]
    let movieRecommendationSemantic: [Int: Double]
    let tvRecommendationSemantic: [Int: Double]
    let movieRecommendationScore: [Int: Double]
    let tvRecommendationScore: [Int: Double]
    let followUpQuestions: [FollowUpQuestion]
    let connections: [Connection]
    
    var hasResults: Bool {
        !inLibraryMovies.isEmpty || !inLibraryTVShows.isEmpty || !recommendations.isEmpty || !tvRecommendations.isEmpty
    }
}

struct FollowUpQuestion {
    let text: String
    let options: [String]
}

struct Connection {
    let from: String
    let to: String
    let reason: String
}

private enum TasteTypeHint {
    case movieOnly
    case tvOnly
    case unknown
}

private struct TasteCandidateBundle {
    let movies: [ScoredMovieRecommendation]
    let tvShows: [ScoredTVRecommendation]
}

private struct ScoredMovieRecommendation {
    let movie: TMDBMovie
    let reason: String
    let score: Double
    let coherence: Double
    let semantic: Double
}

private struct ScoredTVRecommendation {
    let show: TMDBTVShow
    let reason: String
    let score: Double
    let coherence: Double
    let semantic: Double
}
