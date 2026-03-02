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
    private let recommendationEngine = RecommendationEngineV2.shared
    private let deterministicUnderstanding = DeterministicQueryUnderstandingEngine.shared
    private let minimumSuggestionCount = 4
    
    private init() {}
    
    func discover(
        interest: String,
        userMovies: [Movie],
        userTVShows: [TVShow],
        excludedMovieIDs: Set<Int> = [],
        excludedTVIDs: Set<Int> = []
    ) async -> DiscoveryResult {
        let understanding = await understandQuery(interest)
        let preferredMode = preferredMediaMode(from: interest)
        
        let recommendationResult = await recommendationEngine.recommend(
            query: interest,
            understanding: understanding,
            userMovies: userMovies,
            userTVShows: userTVShows,
            excludedMovieIDs: excludedMovieIDs,
            excludedTVIDs: excludedTVIDs
        )
        
        let movieMatches = findIntelligentMovieMatches(understanding: understanding, in: userMovies)
        let tvMatches = findIntelligentTVMatches(understanding: understanding, in: userTVShows)

        let movieLibraryIDs = Set(userMovies.compactMap(\.tmdbID))
        let tvLibraryIDs = Set(userTVShows.compactMap(\.tmdbID))

        var movieRecommendations = recommendationResult.movies.map(\.movie).filter { !excludedMovieIDs.contains($0.id) }
        var tvRecommendations = recommendationResult.tvShows.map(\.show).filter { !excludedTVIDs.contains($0.id) }
        var movieReasons = Dictionary(
            uniqueKeysWithValues: recommendationResult.movies
                .filter { !excludedMovieIDs.contains($0.movie.id) }
                .map { ($0.movie.id, $0.reasons.joined(separator: " • ")) }
        )
        var tvReasons = Dictionary(
            uniqueKeysWithValues: recommendationResult.tvShows
                .filter { !excludedTVIDs.contains($0.show.id) }
                .map { ($0.show.id, $0.reasons.joined(separator: " • ")) }
        )
        var movieCoherence = Dictionary(
            uniqueKeysWithValues: recommendationResult.movies
                .filter { !excludedMovieIDs.contains($0.movie.id) }
                .map { ($0.movie.id, $0.coherenceEvidence) }
        )
        var tvCoherence = Dictionary(
            uniqueKeysWithValues: recommendationResult.tvShows
                .filter { !excludedTVIDs.contains($0.show.id) }
                .map { ($0.show.id, $0.coherenceEvidence) }
        )
        var movieSemantic = Dictionary(
            uniqueKeysWithValues: recommendationResult.movies
                .filter { !excludedMovieIDs.contains($0.movie.id) }
                .map { ($0.movie.id, $0.semanticEvidence) }
        )
        var tvSemantic = Dictionary(
            uniqueKeysWithValues: recommendationResult.tvShows
                .filter { !excludedTVIDs.contains($0.show.id) }
                .map { ($0.show.id, $0.semanticEvidence) }
        )
        var movieScore = Dictionary(
            uniqueKeysWithValues: recommendationResult.movies
                .filter { !excludedMovieIDs.contains($0.movie.id) }
                .map { ($0.movie.id, $0.score) }
        )
        var tvScore = Dictionary(
            uniqueKeysWithValues: recommendationResult.tvShows
                .filter { !excludedTVIDs.contains($0.show.id) }
                .map { ($0.show.id, $0.score) }
        )

        switch preferredMode {
        case .movieOnly:
            if movieRecommendations.count < minimumSuggestionCount, let popularMovies = try? await TMDBService.shared.getPopularMovies() {
                for movie in popularMovies {
                    guard movieRecommendations.count < minimumSuggestionCount else { break }
                    guard !movieLibraryIDs.contains(movie.id) else { continue }
                    guard !excludedMovieIDs.contains(movie.id) else { continue }
                    guard !movieRecommendations.contains(where: { $0.id == movie.id }) else { continue }
                    movieRecommendations.append(movie)
                    movieReasons[movie.id] = "Popular recommendation related to your search"
                    movieCoherence[movie.id] = 0.20
                    movieSemantic[movie.id] = 0.12
                    movieScore[movie.id] = 0.28
                }
            }
        case .tvOnly:
            if tvRecommendations.count < minimumSuggestionCount, let popularTV = try? await TMDBService.shared.getPopularTVShows() {
                for show in popularTV {
                    guard tvRecommendations.count < minimumSuggestionCount else { break }
                    guard !tvLibraryIDs.contains(show.id) else { continue }
                    guard !excludedTVIDs.contains(show.id) else { continue }
                    guard !tvRecommendations.contains(where: { $0.id == show.id }) else { continue }
                    tvRecommendations.append(show)
                    tvReasons[show.id] = "Popular recommendation related to your search"
                    tvCoherence[show.id] = 0.20
                    tvSemantic[show.id] = 0.12
                    tvScore[show.id] = 0.28
                }
            }
        case .any:
            if movieRecommendations.count + tvRecommendations.count < minimumSuggestionCount {
                if let popularMovies = try? await TMDBService.shared.getPopularMovies() {
                    for movie in popularMovies {
                        guard movieRecommendations.count + tvRecommendations.count < minimumSuggestionCount else { break }
                        guard !movieLibraryIDs.contains(movie.id) else { continue }
                        guard !excludedMovieIDs.contains(movie.id) else { continue }
                        guard !movieRecommendations.contains(where: { $0.id == movie.id }) else { continue }
                        movieRecommendations.append(movie)
                        movieReasons[movie.id] = "Popular recommendation related to your search"
                        movieCoherence[movie.id] = 0.20
                        movieSemantic[movie.id] = 0.12
                        movieScore[movie.id] = 0.28
                    }
                }

                if movieRecommendations.count + tvRecommendations.count < minimumSuggestionCount,
                   let popularTV = try? await TMDBService.shared.getPopularTVShows() {
                    for show in popularTV {
                        guard movieRecommendations.count + tvRecommendations.count < minimumSuggestionCount else { break }
                        guard !tvLibraryIDs.contains(show.id) else { continue }
                        guard !excludedTVIDs.contains(show.id) else { continue }
                        guard !tvRecommendations.contains(where: { $0.id == show.id }) else { continue }
                        tvRecommendations.append(show)
                        tvReasons[show.id] = "Popular recommendation related to your search"
                        tvCoherence[show.id] = 0.20
                        tvSemantic[show.id] = 0.12
                        tvScore[show.id] = 0.28
                    }
                }
            }
        }
        
        let questions = generateFollowUpQuestions(
            understanding: understanding,
            movieMatches: movieMatches,
            tvMatches: tvMatches,
            movieRecommendations: movieRecommendations,
            tvRecommendations: tvRecommendations
        )
        
        return DiscoveryResult(
            query: interest,
            understanding: understanding,
            inLibraryMovies: movieMatches,
            inLibraryTVShows: tvMatches,
            recommendations: movieRecommendations,
            tvRecommendations: tvRecommendations,
            movieRecommendationReasons: movieReasons,
            tvRecommendationReasons: tvReasons,
            movieRecommendationCoherence: movieCoherence,
            tvRecommendationCoherence: tvCoherence,
            movieRecommendationSemantic: movieSemantic,
            tvRecommendationSemantic: tvSemantic,
            movieRecommendationScore: movieScore,
            tvRecommendationScore: tvScore,
            followUpQuestions: questions,
            connections: findConnections(inMovies: movieMatches, tvShows: tvMatches)
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
