//
//  ThemeExtractor.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import Foundation
import SwiftData
import NaturalLanguage

class ThemeExtractor {
    static let shared = ThemeExtractor()
    
    private let ollamaURL = "http://localhost:11434"
    private let model = "llama3.2"
    private let thresholdDefaultsKey = "theme.semanticMatchThreshold"
    
    // Canonical vocabulary: data you can expand over time.
    // New themes are still allowed; these are just preferred anchors.
    private let canonicalThemes: Set<String> = [
        "space-exploration", "sci-fi", "survival", "dystopia", "time-travel",
        "coming-of-age", "family-drama", "political-intrigue", "crime-investigation",
        "mystery", "war", "romance", "revenge", "friendship", "identity",
        "artificial-intelligence", "power-struggles", "psychological-thriller",
        "adventure", "heroism", "isolation", "corruption", "redemption",
        "moral-ambiguity", "social-commentary", "technology", "human-nature",
        "leadership", "sacrifice", "justice"
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
        let prompt = """
        Analyze this movie and extract 3-7 key themes or topics.
        
        Rules:
        1) Return ONLY a comma-separated list.
        2) Use lowercase, dash-separated tags.
        3) Prefer canonical tags when they fit naturally.
        4) If none fit, create concise new tags.
        
        Canonical tags:
        \(canonicalThemes.sorted().joined(separator: ", "))
        
        Title: \(movie.title)
        Year: \(movie.year ?? 0)
        Director: \(movie.director ?? "Unknown")
        Genres: \(movie.genres.joined(separator: ", "))
        Overview: \(movie.overview ?? "")
        My Notes: \(movie.notes ?? "")
        
        Themes (comma-separated):
        """
        
        do {
            let raw = try await callOllama(prompt: prompt)
            return normalizeThemes(raw)
        } catch {
            print("Theme extraction error: \(error)")
            return []
        }
    }
    
    func extractThemes(from show: TVShow) async -> [String] {
        let prompt = """
        Analyze this TV show and extract 3-7 key themes or topics.
        
        Rules:
        1) Return ONLY a comma-separated list.
        2) Use lowercase, dash-separated tags.
        3) Prefer canonical tags when they fit naturally.
        4) If none fit, create concise new tags.
        
        Canonical tags:
        \(canonicalThemes.sorted().joined(separator: ", "))
        
        Title: \(show.title)
        Year: \(show.year ?? 0)
        Creator: \(show.creator ?? "Unknown")
        Genres: \(show.genres.joined(separator: ", "))
        Seasons: \(show.seasonCount ?? 0)
        Episodes: \(show.episodeCount ?? 0)
        Overview: \(show.overview ?? "")
        My Notes: \(show.notes ?? "")
        
        Themes (comma-separated):
        """
        
        do {
            let raw = try await callOllama(prompt: prompt)
            return normalizeThemes(raw)
        } catch {
            print("Theme extraction error: \(error)")
            return []
        }
    }
    
    func extractThemesFromText(_ text: String, context: String = "") async -> [String] {
        let prompt = """
        Analyze this content and extract 3-7 key themes or topics.
        
        Rules:
        1) Return ONLY a comma-separated list.
        2) Use lowercase, dash-separated tags.
        3) Prefer canonical tags when they fit naturally.
        4) If none fit, create concise new tags.
        
        Canonical tags:
        \(canonicalThemes.sorted().joined(separator: ", "))
        
        \(context.isEmpty ? "" : "Context: \(context)\n")
        Content: \(text)
        
        Themes (comma-separated):
        """
        
        do {
            let raw = try await callOllama(prompt: prompt)
            return normalizeThemes(raw)
        } catch {
            print("Theme extraction error: \(error)")
            return []
        }
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
    
    private func callOllama(prompt: String) async throws -> [String] {
        let url = URL(string: "\(ollamaURL)/api/generate")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.2,
                "num_predict": 120
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ThemeError.apiError
        }
        
        let result = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return splitThemeResponse(result.response)
    }
    
    private func splitThemeResponse(_ response: String) -> [String] {
        response
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

enum ThemeError: Error {
    case apiError
    case networkError
}
