//
//  SynthesisEngine.swift
//  Constellation
//
//  Created by Codex on 2/27/26.
//

import Foundation

enum SynthesisError: Error {
    case apiError
}

final class SynthesisEngine {
    static let shared = SynthesisEngine()
    
    private let ollamaURL = "http://localhost:11434"
    private let model = "llama3.2"
    
    private init() {}
    
    func generateCollectionInsight(
        collectionName: String,
        movies: [Movie],
        tvShows: [TVShow]
    ) async -> String {
        let mediaSummary = buildMediaSummary(movies: movies, tvShows: tvShows)
        
        guard !mediaSummary.isEmpty else {
            return "Add a few movies or TV shows to this collection, then generate an insight."
        }
        
        let prompt = """
        You are analyzing a user's media collection.
        Write a short insight (2-4 sentences, max 90 words) that explains:
        1) The strongest shared themes.
        2) A notable cross-media connection if present.
        3) One suggested direction for what to add next.
        
        Keep it specific and concrete. No bullet points.
        
        Collection: \(collectionName)
        
        Items:
        \(mediaSummary)
        """
        
        do {
            let response = try await callOllama(prompt: prompt)
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return localFallbackInsight(collectionName: collectionName, movies: movies, tvShows: tvShows)
        }
    }
    
    private func callOllama(prompt: String) async throws -> String {
        let url = URL(string: "\(ollamaURL)/api/generate")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.3,
                "num_predict": 180
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SynthesisError.apiError
        }
        
        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.response
    }
    
    private func buildMediaSummary(movies: [Movie], tvShows: [TVShow]) -> String {
        let movieLines = movies.map {
            "Movie: \($0.title) | genres: \($0.genres.joined(separator: ", ")) | themes: \($0.themes.joined(separator: ", "))"
        }
        
        let showLines = tvShows.map {
            "TV: \($0.title) | genres: \($0.genres.joined(separator: ", ")) | themes: \($0.themes.joined(separator: ", "))"
        }
        
        return (movieLines + showLines).joined(separator: "\n")
    }
    
    private func localFallbackInsight(collectionName: String, movies: [Movie], tvShows: [TVShow]) -> String {
        let allThemes = movies.flatMap(\.themes) + tvShows.flatMap(\.themes)
        let grouped = Dictionary(grouping: allThemes, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
        
        let topThemes = grouped.prefix(3).map { $0.0 }
        let themeText = topThemes.isEmpty ? "mixed topics" : topThemes.joined(separator: ", ")
        
        return "\(collectionName) currently clusters around \(themeText). It combines \(movies.count) movie(s) and \(tvShows.count) TV show(s), which gives you room for cross-media comparison. Add one title that deepens the strongest theme while shifting format if possible."
    }
}
