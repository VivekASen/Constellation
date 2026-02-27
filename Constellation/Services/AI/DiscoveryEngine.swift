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
    
    private init() {}
    
    func discover(interest: String, userMovies: [Movie], userTVShows: [TVShow]) async -> DiscoveryResult {
        let understanding = await understandQuery(interest)
        
        let recommendations = await getSmartRecommendations(
            query: interest,
            understanding: understanding,
            userMovies: userMovies
        )
        
        let movieMatches = findIntelligentMovieMatches(understanding: understanding, in: userMovies)
        let tvMatches = findIntelligentTVMatches(understanding: understanding, in: userTVShows)
        
        let questions = generateFollowUpQuestions(
            understanding: understanding,
            movieMatches: movieMatches,
            tvMatches: tvMatches,
            recommendations: recommendations
        )
        
        return DiscoveryResult(
            query: interest,
            understanding: understanding,
            inLibraryMovies: movieMatches,
            inLibraryTVShows: tvMatches,
            recommendations: recommendations,
            followUpQuestions: questions,
            connections: findConnections(inMovies: movieMatches, tvShows: tvMatches)
        )
    }
    
    private func understandQuery(_ query: String) async -> QueryUnderstanding {
        let prompt = """
        A user searched for: "\(query)"
        
        Analyze what they are looking for. Return a JSON object with:
        {
          "themes": ["theme1", "theme2"],
          "genres": ["genre1", "genre2"],
          "mood": "description of mood/vibe",
          "isGenre": true/false,
          "suggestions": ["popular example 1", "example 2", "example 3"]
        }
        
        JSON:
        """
        
        do {
            let response = try await callOllamaForJSON(prompt: prompt)
            return parseUnderstanding(response)
        } catch {
            print("Understanding error: \(error)")
            return QueryUnderstanding(
                themes: [query.lowercased()],
                genres: [],
                mood: "",
                isGenre: false,
                suggestions: []
            )
        }
    }
    
    private func getSmartRecommendations(
        query: String,
        understanding: QueryUnderstanding,
        userMovies: [Movie]
    ) async -> [TMDBMovie] {
        var allResults: [TMDBMovie] = []
        
        for suggestion in understanding.suggestions.prefix(3) {
            if let results = try? await TMDBService.shared.searchMovies(query: suggestion) {
                allResults.append(contentsOf: results.prefix(3))
            }
        }
        
        for genre in understanding.genres.prefix(2) {
            if let results = try? await TMDBService.shared.searchMovies(query: genre) {
                allResults.append(contentsOf: results.prefix(3))
            }
        }
        
        let userTMDBIds = Set(userMovies.compactMap { $0.tmdbID })
        
        let unique = Dictionary(grouping: allResults, by: { $0.id })
            .compactMap { $0.value.first }
            .filter { !userTMDBIds.contains($0.id) }
        
        return Array(unique.sorted {
            ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0)
        }.prefix(8))
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
        recommendations: [TMDBMovie]
    ) -> [FollowUpQuestion] {
        var questions: [FollowUpQuestion] = []
        
        if recommendations.count > 3 || !tvMatches.isEmpty {
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
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func callOllamaForJSON(prompt: String) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "llama3.2",
            "prompt": prompt,
            "stream": false,
            "format": "json"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return result.response
    }
    
    private func parseUnderstanding(_ json: String) -> QueryUnderstanding {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(UnderstandingJSON.self, from: data) else {
            return QueryUnderstanding(themes: [], genres: [], mood: "", isGenre: false, suggestions: [])
        }
        
        return QueryUnderstanding(
            themes: ThemeExtractor.shared.normalizeThemes(parsed.themes),
            genres: parsed.genres,
            mood: parsed.mood,
            isGenre: parsed.isGenre,
            suggestions: parsed.suggestions
        )
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
    let followUpQuestions: [FollowUpQuestion]
    let connections: [Connection]
    
    var hasResults: Bool {
        !inLibraryMovies.isEmpty || !inLibraryTVShows.isEmpty || !recommendations.isEmpty
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

struct OllamaResponse: Codable {
    let response: String
}
