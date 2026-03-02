import SwiftUI
import SwiftData

struct DiscoveryView: View {
    @Query private var movies: [Movie]
    @Query private var tvShows: [TVShow]
    @AppStorage("recommend.coherenceThreshold") private var coherenceThreshold = 0.22

    @State private var draftQuery = ""
    @State private var isSearching = false
    @State private var turns: [DiscoveryChatTurn] = []
    @State private var conversationState = ChatConversationState()
    @State private var showingAddMovie: DiscoveryMovieSelection?
    @State private var showingAddTVShow: DiscoveryTVSelection?
    @State private var pendingMovieForAddFeedback: TMDBMovie?
    @State private var pendingTVForAddFeedback: TMDBTVShow?
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

    private let intentService = ChatIntentService.shared
    private let memoryStore = RecommendationMemoryStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                pageBackground.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            assistantBubble("Tell me what you want to watch and I’ll refine with you. I can compare against your library and keep improving suggestions each turn.")

                            if turns.isEmpty {
                                starterPromptSection
                            }

                            ForEach(turns) { turn in
                                userBubble(turn.userText)

                                if let summary = turn.assistantSummary {
                                    assistantBubble(summary)
                                }

                                if let result = turn.result, turn.displayPreference.movieLimit > 0 {
                                    ForEach(Array(displayedMovies(from: result).prefix(turn.displayPreference.movieLimit))) { movie in
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
                                                showingAddMovie = movieSelection(for: movie, in: result)
                                            },
                                            secondaryActionTitle: isAdded ? nil : "Not this",
                                            secondaryAction: {
                                                memoryStore.markRejectedMovie(movie.id)
                                                showToast("Noted. I’ll avoid \(movie.title)")
                                            },
                                            onTap: {
                                                pendingMovieForAddFeedback = movie
                                                showingAddMovie = movieSelection(for: movie, in: result)
                                            }
                                        )
                                    }
                                }

                                if let result = turn.result, turn.displayPreference.tvLimit > 0 {
                                    ForEach(Array(displayedTV(from: result).prefix(turn.displayPreference.tvLimit))) { show in
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
                                                showingAddTVShow = tvSelection(for: show, in: result)
                                            },
                                            secondaryActionTitle: isAdded ? nil : "Not this",
                                            secondaryAction: {
                                                memoryStore.markRejectedTV(show.id)
                                                showToast("Noted. I’ll avoid \(show.title)")
                                            },
                                            onTap: {
                                                pendingTVForAddFeedback = show
                                                showingAddTVShow = tvSelection(for: show, in: result)
                                            }
                                        )
                                    }
                                }

                                if let result = turn.result,
                                   let highlight = watchlistHighlight(from: result, display: turn.displayPreference) {
                                    watchlistHighlightCard(highlight)
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
                MovieDetailSheet(movie: movie.movie, recommendationContext: movie.context)
            }
            .sheet(item: $showingAddTVShow, onDismiss: handleTVSheetDismiss) { show in
                TVShowDetailSheet(show: show.show, recommendationContext: show.context)
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
        isSearching = true

        turns.append(
            DiscoveryChatTurn(
                userText: message,
                assistantSummary: nil,
                result: nil,
                displayPreference: ChatDisplayPreference(movieLimit: 1, tvLimit: 1)
            )
        )
        guard let turnIndex = turns.indices.last else {
            isSearching = false
            return
        }

        let plan = await intentService.planTurn(message: message, state: conversationState)
        conversationState = intentService.apply(plan: plan, to: conversationState)
        var turn = turns[turnIndex]
        turn.displayPreference = plan.displayPreference

        let discovery = await DiscoveryEngine.shared.discover(
            interest: intentService.effectiveQuery(for: conversationState),
            userMovies: movies,
            userTVShows: tvShows
        )

        turn.result = discovery
        let hasCards = hasRenderableResults(in: discovery, display: plan.displayPreference)
        let baseSummary = hasCards
            ? (plan.assistantLine?.isEmpty == false
                ? plan.assistantLine
                : intentService.fallbackAssistantSummary(plan: plan, state: conversationState))
            : "I couldn't find good matches for that topic yet. Try adding one more anchor like era, format, or region."
        turn.assistantSummary = [baseSummary, watchlistContextNote(from: discovery)]
            .compactMap { $0 }
            .joined(separator: " ")

        turns[turnIndex] = turn

        isSearching = false
    }

    private func hasRenderableResults(in result: DiscoveryResult, display: ChatDisplayPreference) -> Bool {
        let hasMovieCards = display.movieLimit > 0 && !Array(displayedMovies(from: result).prefix(display.movieLimit)).isEmpty
        let hasTVCards = display.tvLimit > 0 && !Array(displayedTV(from: result).prefix(display.tvLimit)).isEmpty
        return hasMovieCards || hasTVCards
    }

    private func filteredMovies(from result: DiscoveryResult) -> [TMDBMovie] {
        let rejected = memoryStore.rejectedMovieIDs
        return result.recommendations.filter { movie in
            guard !isMovieInLibrary(movie.id) else { return false }
            guard !rejected.contains(movie.id) else { return false }
            let coherence = result.movieRecommendationCoherence[movie.id] ?? 0
            let semantic = result.movieRecommendationSemantic[movie.id] ?? 0
            let score = result.movieRecommendationScore[movie.id] ?? 0
            return coherence >= coherenceThreshold
                || semantic >= 0.12
                || score >= 0.28
        }
    }

    private func filteredTV(from result: DiscoveryResult) -> [TMDBTVShow] {
        let rejected = memoryStore.rejectedTVIDs
        return result.tvRecommendations.filter { show in
            guard !isTVInLibrary(show.id) else { return false }
            guard !rejected.contains(show.id) else { return false }
            let coherence = result.tvRecommendationCoherence[show.id] ?? 0
            let semantic = result.tvRecommendationSemantic[show.id] ?? 0
            let score = result.tvRecommendationScore[show.id] ?? 0
            return coherence >= coherenceThreshold
                || semantic >= 0.12
                || score >= 0.28
        }
    }

    private func displayedMovies(from result: DiscoveryResult) -> [TMDBMovie] {
        let filtered = filteredMovies(from: result)
        if !filtered.isEmpty { return filtered }
        let rejected = memoryStore.rejectedMovieIDs
        return result.recommendations.filter { !rejected.contains($0.id) && !isMovieInLibrary($0.id) }
    }

    private func displayedTV(from result: DiscoveryResult) -> [TMDBTVShow] {
        let filtered = filteredTV(from: result)
        if !filtered.isEmpty { return filtered }
        let rejected = memoryStore.rejectedTVIDs
        return result.tvRecommendations.filter { !rejected.contains($0.id) && !isTVInLibrary($0.id) }
    }

    private func watchlistContextNote(from result: DiscoveryResult) -> String? {
        let watchlistMovieTitles = result.inLibraryMovies
            .filter { $0.watchedDate == nil }
            .map(\.title)
        let watchlistTVTitles = result.inLibraryTVShows
            .filter { $0.watchedDate == nil }
            .map(\.title)
        let titles = Array(NSOrderedSet(array: watchlistMovieTitles + watchlistTVTitles)) as? [String] ?? []
        guard !titles.isEmpty else { return nil }
        let preview = titles.prefix(2).joined(separator: ", ")
        return "Related in your watchlist: \(preview)."
    }

    private func watchlistHighlight(from result: DiscoveryResult, display: ChatDisplayPreference) -> WatchlistHighlight? {
        let movieCandidates = result.inLibraryMovies.filter { $0.watchedDate == nil }
        let tvCandidates = result.inLibraryTVShows.filter { $0.watchedDate == nil }

        if display.movieLimit == 0 {
            if let show = tvCandidates.first { return .tv(show) }
            if let movie = movieCandidates.first { return .movie(movie) }
            return nil
        }

        if display.tvLimit == 0 {
            if let movie = movieCandidates.first { return .movie(movie) }
            if let show = tvCandidates.first { return .tv(show) }
            return nil
        }

        if let movie = movieCandidates.first { return .movie(movie) }
        if let show = tvCandidates.first { return .tv(show) }
        return nil
    }

    @ViewBuilder
    private func watchlistHighlightCard(_ highlight: WatchlistHighlight) -> some View {
        switch highlight {
        case .movie(let movie):
            mediaBubble(
                title: movie.title,
                subtitle: mediaSubtitle(year: movie.year, rating: movie.rating),
                reason: "Already on your watchlist and related to this topic",
                posterURL: URL(string: movie.posterURL ?? ""),
                emoji: "🎬",
                actionTitle: "On your list",
                isAdded: true,
                action: nil,
                secondaryActionTitle: nil,
                secondaryAction: nil,
                onTap: nil
            )
        case .tv(let show):
            mediaBubble(
                title: show.title,
                subtitle: mediaSubtitle(year: show.year, rating: show.rating),
                reason: "Already on your watchlist and related to this topic",
                posterURL: URL(string: show.posterURL ?? ""),
                emoji: "📺",
                actionTitle: "On your list",
                isAdded: true,
                action: nil,
                secondaryActionTitle: nil,
                secondaryAction: nil,
                onTap: nil
            )
        }
    }

    private func movieSelection(for movie: TMDBMovie, in result: DiscoveryResult) -> DiscoveryMovieSelection {
        DiscoveryMovieSelection(
            movie: movie,
            context: MovieRecommendationContext(
                reason: result.movieRecommendationReasons[movie.id] ?? "Strong fit for your request",
                semanticScore: result.movieRecommendationSemantic[movie.id] ?? 0,
                coherenceScore: result.movieRecommendationCoherence[movie.id] ?? 0,
                blendedScore: result.movieRecommendationScore[movie.id] ?? 0
            )
        )
    }

    private func tvSelection(for show: TMDBTVShow, in result: DiscoveryResult) -> DiscoveryTVSelection {
        DiscoveryTVSelection(
            show: show,
            context: TVRecommendationContext(
                reason: result.tvRecommendationReasons[show.id] ?? "Strong fit for your request",
                semanticScore: result.tvRecommendationSemantic[show.id] ?? 0,
                coherenceScore: result.tvRecommendationCoherence[show.id] ?? 0,
                blendedScore: result.tvRecommendationScore[show.id] ?? 0
            )
        )
    }

    private func isMovieInLibrary(_ tmdbID: Int) -> Bool {
        memoryStore.acceptedMovieIDs.contains(tmdbID) || movies.contains(where: { $0.tmdbID == tmdbID })
    }

    private func isTVInLibrary(_ tmdbID: Int) -> Bool {
        memoryStore.acceptedTVIDs.contains(tmdbID) || tvShows.contains(where: { $0.tmdbID == tmdbID })
    }

    private func handleMovieSheetDismiss() {
        guard let candidate = pendingMovieForAddFeedback else { return }
        defer { pendingMovieForAddFeedback = nil }

        guard movies.contains(where: { $0.tmdbID == candidate.id }) else { return }
        memoryStore.markAcceptedMovie(candidate.id)
        showToast("Added \(candidate.title)")
    }

    private func handleTVSheetDismiss() {
        guard let candidate = pendingTVForAddFeedback else { return }
        defer { pendingTVForAddFeedback = nil }

        guard tvShows.contains(where: { $0.tmdbID == candidate.id }) else { return }
        memoryStore.markAcceptedTV(candidate.id)
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
        conversationState = ChatConversationState()
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
        secondaryActionTitle: String?,
        secondaryAction: (() -> Void)?,
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

                HStack(spacing: 8) {
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
                    }

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle) {
                            secondaryAction()
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
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
    var displayPreference: ChatDisplayPreference = ChatDisplayPreference(movieLimit: 1, tvLimit: 1)
}

private struct DiscoveryMovieSelection: Identifiable {
    let movie: TMDBMovie
    let context: MovieRecommendationContext
    var id: Int { movie.id }
}

private struct DiscoveryTVSelection: Identifiable {
    let show: TMDBTVShow
    let context: TVRecommendationContext
    var id: Int { show.id }
}

private enum WatchlistHighlight {
    case movie(Movie)
    case tv(TVShow)
}

#Preview {
    DiscoveryView()
}
