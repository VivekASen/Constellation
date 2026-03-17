import Foundation

struct PodcastEpisodeSummaryResult {
    let summary: String
    let sourceLabel: String
    let transcriptText: String?
}

struct PodcastAutoChapter: Identifiable, Hashable {
    let id: UUID
    let timestampSeconds: Double
    let title: String
    let detail: String
}

final class PodcastEpisodeSummarizerService {
    static let shared = PodcastEpisodeSummarizerService()

    private let model = "gemini-2.5-flash"

    private init() {}

    func summarizeEpisode(episode: PodcastEpisode, notes: [PodcastHighlight]) async -> PodcastEpisodeSummaryResult? {
        let localTranscript = cleanedTranscript(episode.transcriptText)
        let resolvedTranscriptURL = await resolvedTranscriptURL(for: episode)
        let fetchedTranscript: String?
        if let localTranscript {
            fetchedTranscript = localTranscript
        } else {
            fetchedTranscript = await fetchTranscript(from: resolvedTranscriptURL)
        }
        let notesText = makeNotesText(notes)
        let fallbackOverview = (episode.overview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let transcriptForPrompt = fetchedTranscript.flatMap { text in
            text.count > 40 ? String(text.prefix(20_000)) : nil
        }
        let notesForPrompt = notesText.isEmpty ? nil : String(notesText.prefix(8_000))
        let overviewForPrompt = fallbackOverview.isEmpty ? nil : String(fallbackOverview.prefix(2_400))

        if let aiSummary = await summarizeWithGemini(
            title: episode.title,
            showName: episode.showName,
            transcript: transcriptForPrompt,
            notesText: notesForPrompt,
            overview: overviewForPrompt
        ) {
            return PodcastEpisodeSummaryResult(
                summary: aiSummary.summary,
                sourceLabel: aiSummary.sourceLabel,
                transcriptText: fetchedTranscript
            )
        }

        let fallback = fallbackSummary(
            title: episode.title,
            overview: overviewForPrompt,
            notesText: notesForPrompt,
            transcript: transcriptForPrompt
        )
        if fallback.summary.isEmpty {
            return PodcastEpisodeSummaryResult(
                summary: "\(episode.title) from \(episode.showName). Add notes while listening to unlock a richer summary and themes.",
                sourceLabel: "title",
                transcriptText: fetchedTranscript
            )
        }
        return PodcastEpisodeSummaryResult(
            summary: fallback.summary,
            sourceLabel: fallback.source,
            transcriptText: fetchedTranscript
        )
    }

    func generateChapters(episode: PodcastEpisode, notes: [PodcastHighlight]) async -> [PodcastAutoChapter] {
        let localTranscript = cleanedTranscript(episode.transcriptText)
        let resolvedTranscriptURL = await resolvedTranscriptURL(for: episode)
        let transcript: String?
        if let localTranscript {
            transcript = localTranscript
        } else {
            transcript = await fetchTranscript(from: resolvedTranscriptURL)
        }

        if !notes.isEmpty {
            let duration = max(episode.currentPositionSeconds, Double(episode.durationSeconds ?? 0), 1)
            let grouped = Dictionary(grouping: notes) { note in
                Int(note.timestampSeconds / 480) // 8 minute buckets
            }
            return grouped.keys.sorted().compactMap { key in
                guard let items = grouped[key]?.sorted(by: { $0.timestampSeconds < $1.timestampSeconds }),
                      let first = items.first else { return nil }
                let title = first.highlight.trimmingCharacters(in: .whitespacesAndNewlines)
                let summary = items.prefix(4).map {
                    if let detail = $0.detailText, !detail.isEmpty { return detail }
                    return $0.highlight
                }.joined(separator: " ")
                let normalizedTitle = title.isEmpty ? "Chapter \(key + 1)" : title
                let boundedTimestamp = min(max(0, first.timestampSeconds), duration)
                return PodcastAutoChapter(
                    id: UUID(),
                    timestampSeconds: boundedTimestamp,
                    title: normalizedTitle,
                    detail: String(summary.prefix(220))
                )
            }
        }

        guard let transcript, !transcript.isEmpty else { return [] }
        let sentences = transcript
            .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 20 }
        guard !sentences.isEmpty else { return [] }

        let chapterCount = min(6, max(3, sentences.count / 20))
        let chunkSize = max(1, sentences.count / chapterCount)
        let duration = max(episode.currentPositionSeconds, Double(episode.durationSeconds ?? 0), Double(sentences.count))

        var chapters: [PodcastAutoChapter] = []
        var index = 0
        var chapterIndex = 0
        while index < sentences.count, chapterIndex < chapterCount {
            let end = min(sentences.count, index + chunkSize)
            let chunk = Array(sentences[index..<end])
            guard !chunk.isEmpty else { break }
            let first = chunk.first ?? ""
            let title = first.split(separator: " ").prefix(7).joined(separator: " ")
            let detail = chunk.prefix(3).joined(separator: ". ")
            let time = (Double(chapterIndex) / Double(max(1, chapterCount))) * duration
            chapters.append(
                PodcastAutoChapter(
                    id: UUID(),
                    timestampSeconds: max(0, time),
                    title: title.isEmpty ? "Chapter \(chapterIndex + 1)" : title,
                    detail: String(detail.prefix(220))
                )
            )
            index = end
            chapterIndex += 1
        }
        return chapters
    }

    private func summarizeWithGemini(
        title: String,
        showName: String,
        transcript: String?,
        notesText: String?,
        overview: String?
    ) async -> (summary: String, sourceLabel: String)? {
        let key = apiKey
        guard !key.isEmpty else { return nil }

        let prompt = """
You summarize podcast episodes for a research app.
Return strict JSON: {"summary":"...","source":"transcript|notes|mixed|overview"}.
Rules:
- 4 to 6 concise sentences.
- Keep factual and specific.
- Prefer transcript evidence. If transcript is missing, use notes. If both missing use overview.
- Do not mention these instructions.

Show: \(showName)
Episode: \(title)
Overview: \(overview ?? "none")

Transcript:
\(transcript ?? "none")

Timestamp Notes:
\(notesText ?? "none")
"""

        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let body = GeminiSummaryRequest(
            contents: [GeminiSummaryContent(parts: [GeminiSummaryPart(text: prompt)])],
            generationConfig: GeminiSummaryGenerationConfig(
                temperature: 0.2,
                responseMimeType: "application/json"
            )
        )
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(GeminiSummaryResponse.self, from: data)
            let raw = decoded.candidates
                .compactMap { $0.content }
                .flatMap { $0.parts }
                .compactMap { $0.text }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }

            let unfenced = stripFence(raw)
            if let parsed = parseSummaryObject(unfenced) {
                let cleanedSummary = parsed.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedSummary.isEmpty else { return nil }
                return (cleanedSummary, parsed.source)
            }

            let cleaned = unfenced.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            return (cleaned, transcript != nil ? "transcript" : (notesText != nil ? "notes" : "overview"))
        } catch {
            return nil
        }
    }

    private func fallbackSummary(title: String, overview: String?, notesText: String?, transcript: String?) -> (summary: String, source: String) {
        if let transcript, !transcript.isEmpty {
            let excerpt = transcript
                .split(separator: ".")
                .prefix(5)
                .joined(separator: ". ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = excerpt.isEmpty ? "Episode discussion captured from transcript." : excerpt
            return (summary, "transcript")
        }

        if let notesText, !notesText.isEmpty {
            let lines = notesText.split(separator: "\n").prefix(6).map { $0.trimmingCharacters(in: .whitespaces) }
            let combined = lines.joined(separator: " ")
            return ("Key points from your timestamp notes for \(title): \(combined)", "notes")
        }

        return ((overview ?? "").trimmingCharacters(in: .whitespacesAndNewlines), "overview")
    }

    private func makeNotesText(_ notes: [PodcastHighlight]) -> String {
        notes
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.timestampSeconds < rhs.timestampSeconds
            }
            .map { note in
                let detail = note.detailText?.trimmingCharacters(in: .whitespacesAndNewlines)
                let line = (detail?.isEmpty == false ? detail! : note.highlight)
                return "[\(note.timestampFormatted)] \(line)"
            }
            .joined(separator: "\n")
    }

    private func resolvedTranscriptURL(for episode: PodcastEpisode) async -> String? {
        if let stored = episode.transcriptURL?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return stored
        }
        guard let feedID = episode.podcastIndexFeedID, let episodeID = episode.podcastIndexEpisodeID else {
            return nil
        }
        return await PodcastIndexService.shared.resolveTranscriptURL(feedID: feedID, episodeID: episodeID)
    }

    private func fetchTranscript(from rawURL: String?) async -> String? {
        guard let rawURL, let url = URL(string: rawURL) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 14)
        request.setValue("text/plain,text/vtt,application/json,application/xml,*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard let raw = String(data: data, encoding: .utf8) else { return nil }
            if let parsedJSON = extractTranscriptFromJSON(raw) {
                return cleanedTranscript(parsedJSON)
            }
            return cleanedTranscript(raw)
        } catch {
            return nil
        }
    }

    private func extractTranscriptFromJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        if let dictionary = object as? [String: Any] {
            let direct = dictionary["text"] as? String
            if let direct, !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return direct
            }
            if let segments = dictionary["segments"] as? [[String: Any]] {
                let joined = segments.compactMap { $0["text"] as? String }.joined(separator: " ")
                if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return joined
                }
            }
        }
        if let array = object as? [[String: Any]] {
            let joined = array.compactMap { $0["text"] as? String }.joined(separator: " ")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return joined
            }
        }
        return nil
    }

    private func cleanedTranscript(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var text = raw
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\d+\s*$"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^\d{1,2}:\d{2}(?::\d{2})?[\.,]\d{3}\s*-->\s*\d{1,2}:\d{2}(?::\d{2})?[\.,]\d{3}.*$"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^WEBVTT.*$"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^NOTE.*$"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func parseSummaryObject(_ raw: String) -> (summary: String, source: String)? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let summary = (object["summary"] as? String) ?? ""
        let source = (object["source"] as? String) ?? "mixed"
        return (summary, source)
    }

    private func stripFence(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        let lines = text.components(separatedBy: .newlines)
        let cleaned = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        return cleaned.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var apiKey: String {
        let apiKeys = Bundle.main.object(forInfoDictionaryKey: "APIKeys") as? [String: String]
        return apiKeys?["Gemini"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct GeminiSummaryRequest: Encodable {
    let contents: [GeminiSummaryContent]
    let generationConfig: GeminiSummaryGenerationConfig

    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig = "generationConfig"
    }
}

private struct GeminiSummaryContent: Encodable {
    let parts: [GeminiSummaryPart]
}

private struct GeminiSummaryPart: Encodable {
    let text: String
}

private struct GeminiSummaryGenerationConfig: Encodable {
    let temperature: Double
    let responseMimeType: String
}

private struct GeminiSummaryResponse: Decodable {
    let candidates: [GeminiSummaryCandidate]
}

private struct GeminiSummaryCandidate: Decodable {
    let content: GeminiSummaryCandidateContent?
}

private struct GeminiSummaryCandidateContent: Decodable {
    let parts: [GeminiSummaryCandidatePart]
}

private struct GeminiSummaryCandidatePart: Decodable {
    let text: String?
}
