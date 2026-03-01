import SwiftUI
import SwiftData

struct DiscoveryView: View {
    @Query private var movies: [Movie]
    @Query private var tvShows: [TVShow]

    @State private var draftQuery = ""
    @State private var isSearching = false
    @State private var turns: [DiscoveryChatTurn] = []
    @State private var conversationState = DiscoveryConversationState()
    @State private var showingAddMovie: TMDBMovie?
    @State private var showingAddTVShow: TMDBTVShow?
    @State private var pendingMovieForAddFeedback: TMDBMovie?
    @State private var pendingTVForAddFeedback: TMDBTVShow?
    @State private var addedMovieIDs: Set<Int> = []
    @State private var addedTVIDs: Set<Int> = []
    @State private var toastMessage: String?

    private let starterPrompts = [
        "space exploration",
        "murder mystery",
        "historical non-fiction",
        "thoughtful sci fi"
    ]

    private let appBlue = Color(red: 0.10, green: 0.43, blue: 0.95)
    private let surface = Color(uiColor: .secondarySystemBackground)
    private let pageBackground = Color(uiColor: .systemGroupedBackground)

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            assistantBubble("Tell me a topic and I’ll keep refining with you. I’ll return one strong movie pick and one strong TV pick each turn.")

                            if turns.isEmpty {
                                starterPromptSection
                            }

                            ForEach(turns) { turn in
                                let display = turn.displayPreference
                                userBubble(turn.userText)

                                if let summary = turn.assistantSummary {
                                    assistantBubble(summary)
                                }

                                if let result = turn.result, display.movieLimit > 0 {
                                    ForEach(Array(result.recommendations.prefix(display.movieLimit))) { movie in
                                        let isAdded = isMovieInLibrary(movie.id)
                                        mediaBubble(
                                            title: movie.title,
                                            subtitle: mediaSubtitle(year: movie.year, rating: movie.voteAverage),
                                            reason: result.movieRecommendationReasons[movie.id] ?? "Strong fit for your request",
                                            posterURL: movie.posterURL,
                                            emoji: "🎬",
                                            actionTitle: isAdded ? "Added" : "Add Movie",
                                            isAdded: isAdded,
                                            action: {
                                                pendingMovieForAddFeedback = movie
                                                showingAddMovie = movie
                                            },
                                            onTap: {
                                                pendingMovieForAddFeedback = movie
                                                showingAddMovie = movie
                                            }
                                        )
                                    }
                                }

                                if let result = turn.result, display.tvLimit > 0 {
                                    ForEach(Array(result.tvRecommendations.prefix(display.tvLimit))) { show in
                                        let isAdded = isTVInLibrary(show.id)
                                        mediaBubble(
                                            title: show.title,
                                            subtitle: mediaSubtitle(year: show.year, rating: show.voteAverage),
                                            reason: result.tvRecommendationReasons[show.id] ?? "Strong fit for your request",
                                            posterURL: show.posterURL,
                                            emoji: "📺",
                                            actionTitle: isAdded ? "Added" : "Add TV Show",
                                            isAdded: isAdded,
                                            action: {
                                                pendingTVForAddFeedback = show
                                                showingAddTVShow = show
                                            },
                                            onTap: {
                                                pendingTVForAddFeedback = show
                                                showingAddTVShow = show
                                            }
                                        )
                                    }
                                }

                                if let result = turn.result,
                                   result.recommendations.isEmpty,
                                   result.tvRecommendations.isEmpty {
                                    assistantBubble("I could not find confident picks yet. Add one concrete cue like topic, format, or fiction/non-fiction.")
                                }
                            }

                            if isSearching {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.secondary)
                                    Text("Updating recommendations...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(surface)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 100)
                    }
                    .onChange(of: turns.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: isSearching) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                }

                VStack {
                    Spacer()
                    composer
                }

                if let toastMessage {
                    VStack {
                        Spacer()
                        toastView(text: toastMessage)
                            .padding(.bottom, 86)
                    }
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetConversation()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(turns.isEmpty && conversationState.topic == nil)
                }
            }
            .sheet(item: $showingAddMovie, onDismiss: handleMovieSheetDismiss) { movie in
                MovieDetailSheet(movie: movie)
            }
            .sheet(item: $showingAddTVShow, onDismiss: handleTVSheetDismiss) { show in
                TVShowDetailSheet(show: show)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Type your next message...", text: $draftQuery)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
                .onSubmit {
                    Task { await submitMessage(draftQuery) }
                }

            Button {
                Task { await submitMessage(draftQuery) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(draftQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.45) : appBlue)
                    .clipShape(Circle())
            }
            .disabled(draftQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemGroupedBackground).opacity(0.96))
    }

    private var starterPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Starter prompts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starterPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            Task { await submitMessage(prompt) }
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func submitMessage(_ rawMessage: String) async {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        draftQuery = ""

        let plan = planTurn(for: message)
        applyPlan(plan)

        var turn = DiscoveryChatTurn(
            userText: message,
            assistantSummary: nil,
            result: nil,
            displayPreference: plan.displayPreference
        )
        turns.append(turn)

        isSearching = true

        let effectiveQuery = conversationState.effectiveQuery
        let discovery = await DiscoveryEngine.shared.discover(
            interest: effectiveQuery,
            userMovies: movies,
            userTVShows: tvShows
        )

        turn.assistantSummary = assistantSummary(for: plan)
        turn.result = discovery

        if let lastIndex = turns.indices.last {
            turns[lastIndex] = turn
        }

        isSearching = false
    }

    private func normalizedIntentText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func planTurn(for message: String) -> DiscoveryTurnPlan {
        let normalized = normalizedIntentText(message)
        let wantsMore = containsAny(normalized, terms: [
            "more", "another", "anything else", "similar", "keep going", "next", "additional"
        ])
        let resetRequested = containsAny(normalized, terms: ["reset", "start over", "new chat", "clear chat"])

        let wantsTV = containsAny(normalized, terms: ["tv", "show", "shows", "series"])
        let wantsMovies = containsAny(normalized, terms: ["movie", "movies", "film", "films"])

        let mediaOverride: DiscoveryConversationState.MediaMode?
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
        let explicitNewTopic = containsAny(normalized, terms: [
            "switch to", "new topic", "let s talk about", "lets talk about", "what about", "how about"
        ])
        let standaloneTopic = isLikelyStandaloneTopic(normalized)

        let topicAction: DiscoveryTurnPlan.TopicAction
        let topicText: String?
        let refinementText: String?
        if resetRequested {
            topicAction = .keep
            topicText = nil
            refinementText = nil
        } else if conversationState.topic == nil || explicitNewTopic || (standaloneTopic && !wantsMore) {
            topicAction = .startNew
            topicText = extractTopicText(from: message)
            refinementText = nil
        } else if metaOnly {
            topicAction = .keep
            topicText = nil
            refinementText = nil
        } else {
            topicAction = .refine
            topicText = nil
            refinementText = extractTopicText(from: message)
        }

        let effectiveMode = mediaOverride ?? conversationState.mediaMode
        let display: TurnDisplayPreference
        switch effectiveMode {
        case .movieOnly:
            display = TurnDisplayPreference(movieLimit: wantsMore ? 4 : 2, tvLimit: 0)
        case .tvOnly:
            display = TurnDisplayPreference(movieLimit: 0, tvLimit: wantsMore ? 4 : 2)
        case .any:
            display = wantsMore
                ? TurnDisplayPreference(movieLimit: 2, tvLimit: 2)
                : TurnDisplayPreference(movieLimit: 1, tvLimit: 1)
        }

        return DiscoveryTurnPlan(
            resetRequested: resetRequested,
            topicAction: topicAction,
            topicText: topicText,
            refinementText: refinementText,
            mediaModeOverride: mediaOverride,
            documentaryOnlyOverride: documentaryOnly,
            fictionPreferenceOverride: fictionPreference,
            wantsMore: wantsMore,
            displayPreference: display
        )
    }

    private func applyPlan(_ plan: DiscoveryTurnPlan) {
        if plan.resetRequested {
            conversationState = DiscoveryConversationState()
            return
        }

        if let mode = plan.mediaModeOverride {
            conversationState.mediaMode = mode
        }
        if let documentaryOnly = plan.documentaryOnlyOverride {
            conversationState.documentaryOnly = documentaryOnly
        }
        if let fictionPref = plan.fictionPreferenceOverride {
            conversationState.fictionPreference = fictionPref
        }

        switch plan.topicAction {
        case .startNew:
            conversationState.topic = plan.topicText
            conversationState.refinements.removeAll()
        case .refine:
            if let refinement = plan.refinementText, !refinement.isEmpty {
                conversationState.refinements.append(refinement)
                if conversationState.refinements.count > 4 {
                    conversationState.refinements = Array(conversationState.refinements.suffix(4))
                }
            }
        case .keep:
            break
        }
    }

    private func assistantSummary(for plan: DiscoveryTurnPlan) -> String {
        if plan.resetRequested {
            return "Reset complete. Tell me what you want next."
        }

        if plan.wantsMore {
            switch conversationState.mediaMode {
            case .movieOnly: return "Great, here are more movie picks."
            case .tvOnly: return "Great, here are more TV picks."
            case .any: return "Great, here are a few more strong picks."
            }
        }

        if conversationState.documentaryOnly {
            return "Got it. I’ll keep this strictly documentary."
        }

        switch plan.topicAction {
        case .startNew:
            if let topic = conversationState.topic, !topic.isEmpty {
                return "Got it. I’m now focusing on \(topic)."
            }
            return "Got it. I’m ready for your topic."
        case .refine:
            if let refinement = plan.refinementText, !refinement.isEmpty {
                return "Perfect. I refined the picks based on “\(refinement)”."
            }
            return "Perfect. I refined the picks."
        case .keep:
            switch conversationState.mediaMode {
            case .movieOnly: return "Got it, I’ll focus on movies."
            case .tvOnly: return "Got it, I’ll focus on TV."
            case .any: return "Got it. Here are the best matches."
            }
        }
    }

    private func extractTopicText(from message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if containsAny(normalized, terms: ["more", "another", "similar", "like this", "keep going"]) {
            return false
        }
        let tokens = normalized.split(separator: " ")
        return !tokens.isEmpty && tokens.count <= 6
    }

    private func isMovieInLibrary(_ tmdbID: Int) -> Bool {
        addedMovieIDs.contains(tmdbID) || movies.contains(where: { $0.tmdbID == tmdbID })
    }

    private func isTVInLibrary(_ tmdbID: Int) -> Bool {
        addedTVIDs.contains(tmdbID) || tvShows.contains(where: { $0.tmdbID == tmdbID })
    }

    private func handleMovieSheetDismiss() {
        guard let candidate = pendingMovieForAddFeedback else { return }
        defer { pendingMovieForAddFeedback = nil }

        guard movies.contains(where: { $0.tmdbID == candidate.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            addedMovieIDs.insert(candidate.id)
        }
        showToast("Added \(candidate.title)")
    }

    private func handleTVSheetDismiss() {
        guard let candidate = pendingTVForAddFeedback else { return }
        defer { pendingTVForAddFeedback = nil }

        guard tvShows.contains(where: { $0.tmdbID == candidate.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            addedTVIDs.insert(candidate.id)
        }
        showToast("Added \(candidate.title)")
    }

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
        }
    }

    private func resetConversation() {
        turns.removeAll()
        conversationState = DiscoveryConversationState()
        draftQuery = ""
        toastMessage = nil
    }

    private func mediaSubtitle(year: Int?, rating: Double?) -> String {
        let yearText = year.map(String.init) ?? "Year unknown"
        let ratingText = rating.map { String(format: "%.1f", $0) } ?? "-"
        return "\(yearText) • Rating \(ratingText)"
    }

    @ViewBuilder
    private func assistantBubble(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                }
            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(appBlue)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func mediaBubble(
        title: String,
        subtitle: String,
        reason: String,
        posterURL: URL?,
        emoji: String,
        actionTitle: String?,
        isAdded: Bool = false,
        action: (() -> Void)?,
        onTap: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: posterURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.18))
                    .overlay {
                        Text(emoji)
                            .font(.title3)
                    }
            }
            .frame(width: 52, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                if let actionTitle, let action {
                    Button(actionTitle) {
                        action()
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isAdded ? Color.green.opacity(0.16) : appBlue.opacity(0.14))
                    .foregroundStyle(isAdded ? Color.green : appBlue)
                    .clipShape(Capsule())
                    .overlay(alignment: .trailing) {
                        if isAdded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .offset(x: 7, y: -10)
                                .symbolEffect(.bounce, value: isAdded)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            onTap?()
        }
    }

    private func toastView(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

private struct DiscoveryChatTurn: Identifiable {
    let id = UUID()
    let userText: String
    var assistantSummary: String?
    var result: DiscoveryResult?
    var displayPreference: TurnDisplayPreference = TurnDisplayPreference(movieLimit: 1, tvLimit: 1)
}

private struct TurnDisplayPreference {
    let movieLimit: Int
    let tvLimit: Int
}

private struct DiscoveryTurnPlan {
    enum TopicAction {
        case startNew
        case refine
        case keep
    }

    let resetRequested: Bool
    let topicAction: TopicAction
    let topicText: String?
    let refinementText: String?
    let mediaModeOverride: DiscoveryConversationState.MediaMode?
    let documentaryOnlyOverride: Bool?
    let fictionPreferenceOverride: String?
    let wantsMore: Bool
    let displayPreference: TurnDisplayPreference
}

private struct DiscoveryConversationState {
    enum MediaMode {
        case any
        case movieOnly
        case tvOnly
    }

    var topic: String? = nil
    var refinements: [String] = []
    var documentaryOnly = false
    var fictionPreference: String? = nil
    var mediaMode: MediaMode = .any

    var effectiveQuery: String {
        var parts: [String] = []
        if let topic, !topic.isEmpty {
            parts.append(topic)
        }

        if !refinements.isEmpty {
            parts.append(contentsOf: refinements.map { "refine: \($0)" })
        }

        if documentaryOnly {
            parts.append("documentary only")
        }

        if let fictionPreference {
            parts.append("preference: \(fictionPreference)")
        }

        switch mediaMode {
        case .movieOnly:
            parts.append("movies only")
        case .tvOnly:
            parts.append("tv shows only")
        case .any:
            break
        }

        return parts.joined(separator: " | ")
    }
}

#Preview {
    DiscoveryView()
}
