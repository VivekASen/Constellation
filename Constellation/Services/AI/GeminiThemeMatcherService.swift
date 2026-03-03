import Foundation

final class GeminiThemeMatcherService {
    static let shared = GeminiThemeMatcherService()

    private let model = "gemini-2.5-flash"

    private init() {}

    func matchThemes(from request: ThemeMatchRequest, candidateThemes: [String], maxThemes: Int = 7) async -> [String] {
        guard !candidateThemes.isEmpty else { return [] }
        let key = apiKey
        guard !key.isEmpty else { return [] }

        let prompt = buildPrompt(from: request, candidateThemes: candidateThemes, maxThemes: maxThemes)
        debugLog("theme.match.start media=\(request.mediaType) title=\"\(request.title)\" year=\(request.year.map(String.init) ?? "unknown") genres=\(request.genres)")
        debugLog("theme.match.candidates.count \(candidateThemes.count)")
        debugLog("theme.match.prompt.preview \(String(prompt.prefix(1200)))")

        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var requestURL = URLRequest(url: endpoint)
        requestURL.httpMethod = "POST"
        requestURL.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requestURL.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let body = GeminiGenerateRequest(
            contents: [
                GeminiContent(parts: [GeminiPart(text: prompt)])
            ],
            generationConfig: GeminiGenerationConfig(
                temperature: 0,
                responseMimeType: "application/json"
            )
        )

        guard let data = try? JSONEncoder().encode(body) else { return [] }
        requestURL.httpBody = data

        do {
            let (responseData, response) = try await URLSession.shared.data(for: requestURL)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                if let http = response as? HTTPURLResponse {
                    let bodyText = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
                    debugLog("theme.match.http.error status=\(http.statusCode) body=\(String(bodyText.prefix(1200)))")
                } else {
                    debugLog("theme.match.http.error non-http response")
                }
                return []
            }

            let decoded = try JSONDecoder().decode(GeminiGenerateResponse.self, from: responseData)
            let textParts = decoded.candidates
                .compactMap { $0.content }
                .flatMap { $0.parts }
                .compactMap { $0.text }

            let rawContent = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawContent.isEmpty else {
                debugLog("theme.match.empty.content")
                return []
            }
            debugLog("theme.match.raw.content \(String(rawContent.prefix(2000)))")

            let parsedThemes = parseThemes(from: rawContent)
            guard !parsedThemes.isEmpty else {
                debugLog("theme.match.parse.empty")
                return []
            }
            debugLog("theme.match.parsed \(parsedThemes)")

            var result: [String] = []
            for theme in parsedThemes {
                if let canonical = TopThemeCatalog.shared.canonicalTheme(for: theme) {
                    result.append(canonical)
                }
            }

            let unique = Array(NSOrderedSet(array: result)) as? [String] ?? []
            debugLog("theme.match.canonical \(unique)")
            return Array(unique.prefix(maxThemes))
        } catch {
            debugLog("theme.match.exception \(error.localizedDescription)")
            return []
        }
    }

    private func buildPrompt(from request: ThemeMatchRequest, candidateThemes: [String], maxThemes: Int) -> String {
        let yearText = request.year.map(String.init) ?? "unknown"
        let genreText = request.genres.isEmpty ? "none" : request.genres.joined(separator: ", ")
        let notesText = (request.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let overviewText = (request.overview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let candidateBlock = candidateThemes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        return """
Classify themes for this media item by selecting from the candidate list only.

Media type: \(request.mediaType)
Title: \(request.title)
Year: \(yearText)
Genres: \(genreText)
Overview: \(overviewText.isEmpty ? "none" : overviewText)
Notes: \(notesText.isEmpty ? "none" : notesText)

Rules:
- Choose at most \(maxThemes) themes.
- Output ONLY valid candidate themes.
- Use exact spelling from the candidate list.
- If uncertain, return fewer themes.
- Return strict JSON only: {"themes":["theme-a","theme-b"]}

Candidate Themes:\n\(candidateBlock)
"""
    }

    private var apiKey: String {
        let apiKeys = Bundle.main.object(forInfoDictionaryKey: "APIKeys") as? [String: String]
        return apiKeys?["Gemini"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func parseThemes(from rawContent: String) -> [String] {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced = stripCodeFenceIfPresent(trimmed)

        if let parsed = parseThemesFromJSONObject(unfenced), !parsed.isEmpty {
            return parsed
        }
        if let arrayParsed = parseThemesFromJSONArray(unfenced), !arrayParsed.isEmpty {
            return arrayParsed
        }
        return []
    }

    private func stripCodeFenceIfPresent(_ content: String) -> String {
        guard content.hasPrefix("```") else { return content }
        let lines = content.components(separatedBy: .newlines)
        let filtered = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        return filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseThemesFromJSONObject(_ content: String) -> [String]? {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        for key in ["themes", "matched_themes", "labels", "tags"] {
            if let array = object[key] as? [String] {
                return array
            }
        }
        return nil
    }

    private func parseThemesFromJSONArray(_ content: String) -> [String]? {
        guard let start = content.firstIndex(of: "["),
              let end = content.lastIndex(of: "]"),
              start <= end else {
            return nil
        }

        let slice = String(content[start...end])
        guard let data = slice.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return nil
        }
        return array
    }

    private func debugLog(_ message: String) {
#if DEBUG
        if UserDefaults.standard.object(forKey: "theme.geminiDebug.enabled") == nil {
            UserDefaults.standard.set(true, forKey: "theme.geminiDebug.enabled")
        }
        guard UserDefaults.standard.bool(forKey: "theme.geminiDebug.enabled") else { return }
        print("[GeminiThemeMatcher] \(message)")
#endif
    }
}

private struct GeminiGenerateRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig

    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig = "generationConfig"
    }
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double
    let responseMimeType: String
}

private struct GeminiGenerateResponse: Decodable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Decodable {
    let content: GeminiCandidateContent?
}

private struct GeminiCandidateContent: Decodable {
    let parts: [GeminiCandidatePart]
}

private struct GeminiCandidatePart: Decodable {
    let text: String?
}
