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
                                let display = displayPreference(for: turn.userText)
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

        updateConversationState(with: message)

        var turn = DiscoveryChatTurn(userText: message, assistantSummary: nil, result: nil)
        turns.append(turn)

        isSearching = true

        let effectiveQuery = conversationState.effectiveQuery
        let discovery = await DiscoveryEngine.shared.discover(
            interest: effectiveQuery,
            userMovies: movies,
            userTVShows: tvShows
        )

        turn.assistantSummary = assistantSummary(for: message)
        turn.result = discovery

        if let lastIndex = turns.indices.last {
            turns[lastIndex] = turn
        }

        isSearching = false
    }

    private func updateConversationState(with message: String) {
        let normalized = normalizedIntentText(message)
        let appliedConstraint = applyConstraints(from: normalized)

        if conversationState.topic == nil {
            conversationState.topic = message
            return
        }

        // Keep the original topic when the user sends a short refinement like
        // "actually documentaries" or "movie only".
        if !appliedConstraint || shouldTreatAsNewTopic(normalized) {
            conversationState.topic = message
        }
    }

    @discardableResult
    private func applyConstraints(from normalized: String) -> Bool {
        var applied = false

        if containsAny(normalized, terms: ["documentary", "documentaries", "docuseries"]) {
            conversationState.documentaryOnly = true
            conversationState.fictionPreference = "Non-Fiction"
            applied = true
        }

        if containsAny(normalized, terms: ["non fiction", "non-fiction", "nonfiction"]) {
            conversationState.fictionPreference = "Non-Fiction"
            conversationState.documentaryOnly = true
            applied = true
        }

        if normalized.contains("fiction")
            && !containsAny(normalized, terms: ["non fiction", "non-fiction", "nonfiction"]) {
            conversationState.fictionPreference = "Fiction"
            conversationState.documentaryOnly = false
            applied = true
        }

        if containsAny(normalized, terms: ["movie only", "movies only", "film only", "films only"]) {
            conversationState.mediaMode = .movieOnly
            applied = true
        } else if containsAny(normalized, terms: [
            "tv only",
            "show only",
            "shows only",
            "series only",
            "tv shows only",
            "tv suggestion",
            "tv suggestions",
            "show suggestions",
            "more tv",
            "more shows"
        ]) {
            conversationState.mediaMode = .tvOnly
            applied = true
        } else if containsAny(normalized, terms: [
            "movie suggestion",
            "movie suggestions",
            "film suggestions",
            "more movies",
            "more films"
        ]) {
            conversationState.mediaMode = .movieOnly
            applied = true
        } else if containsAny(normalized, terms: ["both", "either", "any format"]) {
            conversationState.mediaMode = .any
            applied = true
        }

        return applied
    }

    private func shouldTreatAsNewTopic(_ normalized: String) -> Bool {
        if containsAny(normalized, terms: ["actually", "instead", "now", "make it", "i want"]) {
            return false
        }

        let filler = Set([
            "i", "want", "something", "more", "less", "actually", "instead", "now",
            "please", "show", "me", "about", "with", "and", "or", "the", "a", "an",
            "only", "both", "either", "format", "movie", "movies", "tv", "show", "shows",
            "series", "documentary", "documentaries", "docuseries", "fiction", "non", "nonfiction"
        ])

        let topicalTokens = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty && !filler.contains($0) }

        return topicalTokens.count >= 2
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

    private func displayPreference(for message: String) -> TurnDisplayPreference {
        let normalized = normalizedIntentText(message)
        let isMore = containsAny(normalized, terms: [
            "more",
            "another",
            "anything else",
            "similar",
            "keep going",
            "next suggestion",
            "next suggestions"
        ])
        let wantsTV = containsAny(normalized, terms: ["tv", "show", "shows", "series"])
        let wantsMovies = containsAny(normalized, terms: ["movie", "movies", "film", "films"])

        if wantsTV && !wantsMovies {
            return TurnDisplayPreference(movieLimit: 0, tvLimit: isMore ? 3 : 2)
        }
        if wantsMovies && !wantsTV {
            return TurnDisplayPreference(movieLimit: isMore ? 3 : 2, tvLimit: 0)
        }
        if isMore {
            return TurnDisplayPreference(movieLimit: 2, tvLimit: 2)
        }
        return TurnDisplayPreference(movieLimit: 1, tvLimit: 1)
    }

    private func assistantSummary(for message: String) -> String {
        let normalized = normalizedIntentText(message)
        let wantsMore = containsAny(normalized, terms: ["more", "another", "anything else", "similar", "keep going"])

        switch conversationState.mediaMode {
        case .tvOnly:
            return wantsMore
                ? "Great, here are more TV suggestions in the same lane."
                : "Got it, I’ll focus on TV suggestions."
        case .movieOnly:
            return wantsMore
                ? "Great, here are more movie suggestions in the same lane."
                : "Got it, I’ll focus on movie suggestions."
        case .any:
            break
        }

        if conversationState.documentaryOnly {
            return wantsMore
                ? "Great, here are more documentary picks."
                : "Got it, I’ll keep this strictly documentary."
        }

        return wantsMore
            ? "Great, here are a few more strong picks."
            : "Got it. Here are the best matches I found."
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
}

private struct TurnDisplayPreference {
    let movieLimit: Int
    let tvLimit: Int
}

private struct DiscoveryConversationState {
    enum MediaMode {
        case any
        case movieOnly
        case tvOnly
    }

    var topic: String? = nil
    var documentaryOnly = false
    var fictionPreference: String? = nil
    var mediaMode: MediaMode = .any

    var effectiveQuery: String {
        var parts: [String] = []
        if let topic, !topic.isEmpty {
            parts.append(topic)
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

    var summaryLine: String {
        var tags: [String] = []
        if let topic, !topic.isEmpty { tags.append("Topic: \(topic)") }
        if documentaryOnly { tags.append("Documentary mode") }
        if let fictionPreference { tags.append(fictionPreference) }
        switch mediaMode {
        case .movieOnly: tags.append("Movies only")
        case .tvOnly: tags.append("TV only")
        case .any: break
        }

        if tags.isEmpty {
            return "Understood. Here are my top picks."
        }
        return "Understood. Applied: \(tags.joined(separator: ", "))."
    }
}

#Preview {
    DiscoveryView()
}
