import Foundation

enum ChatMediaMode: String, Codable {
    case any
    case movieOnly
    case tvOnly
}

struct ChatConversationState: Codable {
    var topic: String? = nil
    var refinements: [String] = []
    var documentaryOnly = false
    var fictionPreference: String? = nil
    var mediaMode: ChatMediaMode = .any
}

struct ChatDisplayPreference {
    let movieLimit: Int
    let tvLimit: Int
}

struct ChatTurnPlan {
    enum TopicAction {
        case startNew
        case refine
        case keep
    }

    let resetRequested: Bool
    let topicAction: TopicAction
    let topicText: String?
    let refinementText: String?
    let mediaModeOverride: ChatMediaMode?
    let documentaryOnlyOverride: Bool?
    let fictionPreferenceOverride: String?
    let wantsMore: Bool
    let displayPreference: ChatDisplayPreference
    let assistantLine: String?
}

final class ChatIntentService {
    static let shared = ChatIntentService()
    private init() {}

    func planTurn(message: String, state: ChatConversationState) async -> ChatTurnPlan {
        // Deterministic planning is more stable for app-side chat flow
        // and avoids topic drift from model variability.
        let heuristic = planTurnHeuristic(message: message, state: state)
        return sanitize(plan: heuristic, message: message, state: state)
    }

    func apply(plan: ChatTurnPlan, to state: ChatConversationState) -> ChatConversationState {
        var next = state
        if plan.resetRequested {
            return ChatConversationState()
        }
        if let mode = plan.mediaModeOverride { next.mediaMode = mode }
        if let doc = plan.documentaryOnlyOverride { next.documentaryOnly = doc }
        if let fiction = plan.fictionPreferenceOverride { next.fictionPreference = fiction }

        switch plan.topicAction {
        case .startNew:
            next.topic = plan.topicText
            next.refinements.removeAll()
        case .refine:
            if let ref = plan.refinementText, !ref.isEmpty {
                next.refinements.append(ref)
                if next.refinements.count > 4 {
                    next.refinements = Array(next.refinements.suffix(4))
                }
            }
        case .keep:
            break
        }
        return next
    }

    func effectiveQuery(for state: ChatConversationState) -> String {
        var parts: [String] = []
        if let topic = state.topic, !topic.isEmpty {
            parts.append(topic)
        }
        if !state.refinements.isEmpty {
            parts.append(contentsOf: state.refinements.map { "refine: \($0)" })
        }
        if state.documentaryOnly {
            parts.append("documentary only")
        }
        if let fiction = state.fictionPreference {
            parts.append("preference: \(fiction)")
        }
        switch state.mediaMode {
        case .movieOnly:
            parts.append("movies only")
        case .tvOnly:
            parts.append("tv shows only")
        case .any:
            break
        }
        return parts.joined(separator: " | ")
    }

    func fallbackAssistantSummary(plan: ChatTurnPlan, state: ChatConversationState) -> String {
        if plan.resetRequested {
            return "Reset complete. Tell me what you want next."
        }
        if plan.wantsMore {
            switch state.mediaMode {
            case .movieOnly: return "Great, here are more movie picks."
            case .tvOnly: return "Great, here are more TV picks."
            case .any: return "Great, here are a few more strong picks."
            }
        }
        if state.documentaryOnly {
            return "Got it. I’ll keep this strictly documentary."
        }
        switch plan.topicAction {
        case .startNew:
            if let topic = state.topic, !topic.isEmpty {
                return "Got it. I’m now focusing on \(topic)."
            }
            return "Got it. I’m ready for your topic."
        case .refine:
            if let ref = plan.refinementText, !ref.isEmpty {
                return "Perfect. I refined the picks based on “\(ref)”."
            }
            return "Perfect. I refined the picks."
        case .keep:
            switch state.mediaMode {
            case .movieOnly: return "Got it, I’ll focus on movies."
            case .tvOnly: return "Got it, I’ll focus on TV."
            case .any: return "Got it. Here are the best matches."
            }
        }
    }

    func shouldSuggestTopicReset(message: String, state: ChatConversationState) -> Bool {
        guard let currentTopic = state.topic, !currentTopic.isEmpty else { return false }
        let normalizedMessage = normalize(message)
        if normalizedMessage.isEmpty { return false }

        // Explicit controls should never be treated as drift.
        if containsAny(normalizedMessage, terms: ["reset", "start over", "new chat", "clear chat", "switch topic", "switch to"]) {
            return false
        }
        if containsAny(normalizedMessage, terms: ["more", "another", "similar", "keep going", "next", "same"]) {
            return false
        }
        if isLikelyPropertyRefinement(normalizedMessage) {
            return false
        }
        if isMetaOnlyMessage(normalizedMessage) {
            return false
        }
        if !isLikelyStandaloneTopic(normalizedMessage) {
            return false
        }

        let newTokens = tokenizeForTopic(normalizedMessage)
        let currentTokens = tokenizeForTopic(normalize(currentTopic))
        guard !newTokens.isEmpty, !currentTokens.isEmpty else { return false }

        let overlap = jaccard(newTokens, currentTokens)
        return overlap < 0.15
    }

    private func planTurnHeuristic(message: String, state: ChatConversationState) -> ChatTurnPlan {
        let normalized = normalize(message)
        let wantsMore = containsAny(normalized, terms: ["more", "another", "anything else", "similar", "keep going", "next", "additional"])
        let resetRequested = containsAny(normalized, terms: ["reset", "start over", "new chat", "clear chat"])
        let wantsTV = containsAny(normalized, terms: ["tv", "show", "shows", "series"])
        let wantsMovies = containsAny(normalized, terms: ["movie", "movies", "film", "films"])

        let mediaOverride: ChatMediaMode?
        if wantsTV && !wantsMovies {
            mediaOverride = .tvOnly
        } else if wantsMovies && !wantsTV {
            mediaOverride = .movieOnly
        } else if containsAny(normalized, terms: ["both", "either", "any format", "anything"]) {
            mediaOverride = .any
        } else {
            mediaOverride = nil
        }

        let documentaryOnly: Bool?
        let fictionPreference: String?
        if containsAny(normalized, terms: ["documentary", "documentaries", "docuseries", "non fiction", "non-fiction", "nonfiction"]) {
            documentaryOnly = true
            fictionPreference = "Non-Fiction"
        } else if normalized.contains("fiction") {
            documentaryOnly = false
            fictionPreference = "Fiction"
        } else {
            documentaryOnly = nil
            fictionPreference = nil
        }

        let metaOnly = isMetaOnlyMessage(normalized)
        let explicitNewTopic = containsAny(normalized, terms: ["switch to", "new topic", "let s talk about", "lets talk about", "what about", "how about"])
        let standaloneTopic = isLikelyStandaloneTopic(normalized)

        let topicAction: ChatTurnPlan.TopicAction
        let topicText: String?
        let refinementText: String?
        if resetRequested {
            topicAction = .keep
            topicText = nil
            refinementText = nil
        } else if state.topic != nil && isLikelyPropertyRefinement(normalized) {
            topicAction = .refine
            topicText = nil
            refinementText = message.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if state.topic == nil || explicitNewTopic || (standaloneTopic && !wantsMore) {
            topicAction = .startNew
            topicText = message.trimmingCharacters(in: .whitespacesAndNewlines)
            refinementText = nil
        } else if metaOnly {
            topicAction = .keep
            topicText = nil
            refinementText = nil
        } else {
            topicAction = .refine
            topicText = nil
            refinementText = message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let effectiveMode = mediaOverride ?? state.mediaMode
        let display: ChatDisplayPreference
        switch effectiveMode {
        case .movieOnly:
            display = ChatDisplayPreference(movieLimit: wantsMore ? 4 : 2, tvLimit: 0)
        case .tvOnly:
            display = ChatDisplayPreference(movieLimit: 0, tvLimit: wantsMore ? 4 : 2)
        case .any:
            display = wantsMore ? ChatDisplayPreference(movieLimit: 2, tvLimit: 2) : ChatDisplayPreference(movieLimit: 1, tvLimit: 1)
        }

        return ChatTurnPlan(
            resetRequested: resetRequested,
            topicAction: topicAction,
            topicText: topicText,
            refinementText: refinementText,
            mediaModeOverride: mediaOverride,
            documentaryOnlyOverride: documentaryOnly,
            fictionPreferenceOverride: fictionPreference,
            wantsMore: wantsMore,
            displayPreference: display,
            assistantLine: nil
        )
    }

    private func planTurnWithLLM(message: String, state: ChatConversationState) async -> ChatTurnPlan? {
        let prompt = """
        You are a planner for a media discovery chat assistant.
        Convert the user's latest message into STRICT JSON for app logic.

        Current conversation state:
        - topic: "\(state.topic ?? "")"
        - refinements: "\(state.refinements.joined(separator: " | "))"
        - media_mode: "\(state.mediaMode.rawValue)"
        - documentary_only: \(state.documentaryOnly ? "true" : "false")
        - fiction_preference: "\(state.fictionPreference ?? "any")"

        Latest user message:
        "\(message)"

        Rules:
        1) If user asks for "more tv suggestions" (or similar), this is a REFINE, not a new topic.
        2) "more", "another", "anything else" should usually keep topic and increase counts.
        3) For format requests, set media_mode_override to movieOnly or tvOnly.
        4) For documentary/non-fiction requests, set documentary_only_override=true.
        5) assistant_line must sound natural and concise.
        6) Output JSON only, no prose.

        Output schema:
        {
          "reset_requested": bool,
          "topic_action": "startNew" | "refine" | "keep",
          "topic_text": string | null,
          "refinement_text": string | null,
          "media_mode_override": "any" | "movieOnly" | "tvOnly" | null,
          "documentary_only_override": bool | null,
          "fiction_preference_override": "Fiction" | "Non-Fiction" | null,
          "wants_more": bool,
          "movie_count": int,
          "tv_count": int,
          "assistant_line": string
        }
        """

        guard let json = await callOllama(prompt: prompt),
              let parsed = parseTurnPlanJSON(json) else {
            return nil
        }

        var movieLimit = min(max(parsed.movieCount, 0), 6)
        var tvLimit = min(max(parsed.tvCount, 0), 6)
        if movieLimit == 0 && tvLimit == 0 {
            switch parsed.mediaModeOverride ?? state.mediaMode {
            case .movieOnly:
                movieLimit = parsed.wantsMore ? 4 : 2
            case .tvOnly:
                tvLimit = parsed.wantsMore ? 4 : 2
            case .any:
                movieLimit = parsed.wantsMore ? 2 : 1
                tvLimit = parsed.wantsMore ? 2 : 1
            }
        }

        return ChatTurnPlan(
            resetRequested: parsed.resetRequested,
            topicAction: parsed.topicAction,
            topicText: parsed.topicText,
            refinementText: parsed.refinementText,
            mediaModeOverride: parsed.mediaModeOverride,
            documentaryOnlyOverride: parsed.documentaryOnlyOverride,
            fictionPreferenceOverride: parsed.fictionPreferenceOverride,
            wantsMore: parsed.wantsMore,
            displayPreference: ChatDisplayPreference(movieLimit: movieLimit, tvLimit: tvLimit),
            assistantLine: parsed.assistantLine
        )
    }

    private func callOllama(prompt: String) async -> String? {
        guard let url = URL(string: "http://localhost:11434/api/generate") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "llama3.2",
            "prompt": prompt,
            "stream": false,
            "format": "json",
            "options": ["temperature": 0.1]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, _) = try await URLSession.shared.data(for: request)
            let envelope = try JSONDecoder().decode(OllamaEnvelope.self, from: data)
            return envelope.response
        } catch {
            return nil
        }
    }

    private func parseTurnPlanJSON(_ text: String) -> ParsedTurnPlan? {
        let body = extractJSONObject(from: text)
        guard let data = body.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ParsedTurnPlanJSON.self, from: data) else {
            return nil
        }
        return parsed.toParsedPlan()
    }

    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains { term in
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
            return text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func tokenizeForTopic(_ text: String) -> Set<String> {
        let stopwords: Set<String> = [
            "movie", "movies", "film", "films", "tv", "show", "shows", "series",
            "more", "another", "suggestion", "suggestions", "recommend", "recommendations",
            "best", "good", "great", "about", "with", "for", "and", "the", "a", "an"
        ]
        return Set(
            text.split(separator: " ").map(String.init).filter {
                $0.count >= 3 && !$0.allSatisfy(\.isNumber) && !stopwords.contains($0)
            }
        )
    }

    private func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let unionCount = a.union(b).count
        guard unionCount > 0 else { return 0 }
        let intersectionCount = a.intersection(b).count
        return Double(intersectionCount) / Double(unionCount)
    }

    private func isMetaOnlyMessage(_ normalized: String) -> Bool {
        let metaTokens: Set<String> = [
            "more", "another", "anything", "else", "similar", "keep", "going",
            "suggestion", "suggestions", "tv", "show", "shows", "series",
            "movie", "movies", "film", "films", "please", "some", "give", "me", "can", "you"
        ]
        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { metaTokens.contains($0) }
    }

    private func isLikelyStandaloneTopic(_ normalized: String) -> Bool {
        if isLikelyPropertyRefinement(normalized) {
            return false
        }
        if containsAny(normalized, terms: ["more", "another", "similar", "like this", "keep going"]) {
            return false
        }
        let tokens = normalized.split(separator: " ")
        return !tokens.isEmpty && tokens.count <= 6
    }

    private func isLikelyPropertyRefinement(_ normalized: String) -> Bool {
        if containsAny(normalized, terms: [
            "with a female lead", "female lead", "female protagonist", "woman lead",
            "male lead", "ensemble cast", "starring", "directed by", "written by",
            "set in", "set during", "based on", "true story", "real story",
            "award winning", "oscar", "emmy", "golden globe", "bafta",
            "from the 80s", "from the 90s", "from the 2000s", "from the 2010s",
            "from the 2020s", "in japanese", "in english", "in korean",
            "animated", "live action", "documentary style", "family friendly",
            "not too dark", "less violent", "more serious", "more grounded"
        ]) {
            return true
        }

        // Natural follow-up style: "with ...", "that has ...", "where ..."
        if normalized.hasPrefix("with ") || normalized.hasPrefix("that ") || normalized.hasPrefix("where ") {
            return true
        }
        if normalized.hasPrefix("without ") || normalized.hasPrefix("only ") || normalized.hasPrefix("but ") {
            return true
        }
        return false
    }

    private func sanitize(plan: ChatTurnPlan, message: String, state: ChatConversationState) -> ChatTurnPlan {
        let normalized = normalize(message)
        let wantsMore = containsAny(normalized, terms: [
            "more", "another", "anything else", "similar", "keep going", "next", "additional"
        ])
        let wantsTV = containsAny(normalized, terms: ["tv", "show", "shows", "series"])
        let wantsMovies = containsAny(normalized, terms: ["movie", "movies", "film", "films"])
        let metaOnly = isMetaOnlyMessage(normalized)
        let standaloneTopic = isLikelyStandaloneTopic(normalized)

        var topicAction = plan.topicAction
        var topicText = plan.topicText
        var refinementText = plan.refinementText
        var mediaOverride = plan.mediaModeOverride
        var movieLimit = plan.displayPreference.movieLimit
        var tvLimit = plan.displayPreference.tvLimit

        // Follow-up requests should not reset the main topic.
        if state.topic != nil && (wantsMore || metaOnly) && topicAction == .startNew {
            topicAction = .keep
            topicText = nil
        }

        // Enforce explicit media mode from user phrasing.
        if wantsTV && !wantsMovies {
            mediaOverride = .tvOnly
        } else if wantsMovies && !wantsTV {
            mediaOverride = .movieOnly
        }

        let effectiveMode = mediaOverride ?? state.mediaMode
        switch effectiveMode {
        case .tvOnly:
            movieLimit = 0
            tvLimit = max(tvLimit, wantsMore ? 4 : 2)
        case .movieOnly:
            tvLimit = 0
            movieLimit = max(movieLimit, wantsMore ? 4 : 2)
        case .any:
            if movieLimit == 0 && tvLimit == 0 {
                movieLimit = wantsMore ? 2 : 1
                tvLimit = wantsMore ? 2 : 1
            }
        }

        if wantsMore && refinementText == nil && state.topic != nil {
            refinementText = "more options in the same style"
        }

        let resolvedWantsMore = standaloneTopic ? false : (plan.wantsMore || wantsMore)

        return ChatTurnPlan(
            resetRequested: plan.resetRequested,
            topicAction: topicAction,
            topicText: topicText,
            refinementText: refinementText,
            mediaModeOverride: mediaOverride,
            documentaryOnlyOverride: plan.documentaryOnlyOverride,
            fictionPreferenceOverride: plan.fictionPreferenceOverride,
            wantsMore: resolvedWantsMore,
            displayPreference: ChatDisplayPreference(movieLimit: movieLimit, tvLimit: tvLimit),
            assistantLine: plan.assistantLine
        )
    }
}

private struct ParsedTurnPlan {
    let resetRequested: Bool
    let topicAction: ChatTurnPlan.TopicAction
    let topicText: String?
    let refinementText: String?
    let mediaModeOverride: ChatMediaMode?
    let documentaryOnlyOverride: Bool?
    let fictionPreferenceOverride: String?
    let wantsMore: Bool
    let movieCount: Int
    let tvCount: Int
    let assistantLine: String?
}

private struct ParsedTurnPlanJSON: Decodable {
    let resetRequested: Bool?
    let topicAction: String?
    let topicText: String?
    let refinementText: String?
    let mediaModeOverride: String?
    let documentaryOnlyOverride: Bool?
    let fictionPreferenceOverride: String?
    let wantsMore: Bool?
    let movieCount: Int?
    let tvCount: Int?
    let assistantLine: String?

    enum CodingKeys: String, CodingKey {
        case resetRequested = "reset_requested"
        case topicAction = "topic_action"
        case topicText = "topic_text"
        case refinementText = "refinement_text"
        case mediaModeOverride = "media_mode_override"
        case documentaryOnlyOverride = "documentary_only_override"
        case fictionPreferenceOverride = "fiction_preference_override"
        case wantsMore = "wants_more"
        case movieCount = "movie_count"
        case tvCount = "tv_count"
        case assistantLine = "assistant_line"
    }

    func toParsedPlan() -> ParsedTurnPlan {
        let action: ChatTurnPlan.TopicAction
        switch (topicAction ?? "").lowercased() {
        case "startnew", "new", "start_new":
            action = .startNew
        case "refine":
            action = .refine
        default:
            action = .keep
        }

        let mode: ChatMediaMode?
        switch (mediaModeOverride ?? "").lowercased() {
        case "movieonly", "movie_only":
            mode = .movieOnly
        case "tvonly", "tv_only":
            mode = .tvOnly
        case "any":
            mode = .any
        default:
            mode = nil
        }

        let fictionPref: String?
        switch (fictionPreferenceOverride ?? "").lowercased() {
        case "fiction":
            fictionPref = "Fiction"
        case "non-fiction", "non fiction", "nonfiction":
            fictionPref = "Non-Fiction"
        default:
            fictionPref = nil
        }

        return ParsedTurnPlan(
            resetRequested: resetRequested ?? false,
            topicAction: action,
            topicText: topicText?.trimmingCharacters(in: .whitespacesAndNewlines),
            refinementText: refinementText?.trimmingCharacters(in: .whitespacesAndNewlines),
            mediaModeOverride: mode,
            documentaryOnlyOverride: documentaryOnlyOverride,
            fictionPreferenceOverride: fictionPref,
            wantsMore: wantsMore ?? false,
            movieCount: movieCount ?? 1,
            tvCount: tvCount ?? 1,
            assistantLine: assistantLine?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct OllamaEnvelope: Decodable {
    let response: String
}

final class RecommendationMemoryStore {
    static let shared = RecommendationMemoryStore()
    private init() {}

    private let defaults = UserDefaults.standard
    private let acceptedMoviesKey = "discover.acceptedMovies"
    private let acceptedTVKey = "discover.acceptedTV"
    private let rejectedMoviesKey = "discover.rejectedMovies"
    private let rejectedTVKey = "discover.rejectedTV"

    var acceptedMovieIDs: Set<Int> { Set(defaults.array(forKey: acceptedMoviesKey) as? [Int] ?? []) }
    var acceptedTVIDs: Set<Int> { Set(defaults.array(forKey: acceptedTVKey) as? [Int] ?? []) }
    var rejectedMovieIDs: Set<Int> { Set(defaults.array(forKey: rejectedMoviesKey) as? [Int] ?? []) }
    var rejectedTVIDs: Set<Int> { Set(defaults.array(forKey: rejectedTVKey) as? [Int] ?? []) }

    func markAcceptedMovie(_ id: Int) { save(id, to: acceptedMoviesKey, removeFrom: rejectedMoviesKey) }
    func markAcceptedTV(_ id: Int) { save(id, to: acceptedTVKey, removeFrom: rejectedTVKey) }
    func markRejectedMovie(_ id: Int) { save(id, to: rejectedMoviesKey, removeFrom: acceptedMoviesKey) }
    func markRejectedTV(_ id: Int) { save(id, to: rejectedTVKey, removeFrom: acceptedTVKey) }

    private func save(_ id: Int, to includeKey: String, removeFrom excludeKey: String) {
        var include = Set(defaults.array(forKey: includeKey) as? [Int] ?? [])
        include.insert(id)
        defaults.set(Array(include), forKey: includeKey)

        var exclude = Set(defaults.array(forKey: excludeKey) as? [Int] ?? [])
        exclude.remove(id)
        defaults.set(Array(exclude), forKey: excludeKey)
    }
}
