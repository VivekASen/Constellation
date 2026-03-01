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
    @State private var showingAddMovie: TMDBMovie?
    @State private var showingAddTVShow: TMDBTVShow?
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
                                    ForEach(Array(filteredMovies(from: result).prefix(turn.displayPreference.movieLimit))) { movie in
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
                                            secondaryActionTitle: isAdded ? nil : "Not this",
                                            secondaryAction: {
                                                memoryStore.markRejectedMovie(movie.id)
                                                showToast("Noted. I’ll avoid \(movie.title)")
                                            },
                                            onTap: {
                                                pendingMovieForAddFeedback = movie
                                                showingAddMovie = movie
                                            }
                                        )
                                    }
                                }

                                if let result = turn.result, turn.displayPreference.tvLimit > 0 {
                                    ForEach(Array(filteredTV(from: result).prefix(turn.displayPreference.tvLimit))) { show in
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
                                            secondaryActionTitle: isAdded ? nil : "Not this",
                                            secondaryAction: {
                                                memoryStore.markRejectedTV(show.id)
                                                showToast("Noted. I’ll avoid \(show.title)")
                                            },
                                            onTap: {
                                                pendingTVForAddFeedback = show
                                                showingAddTVShow = show
                                            }
                                        )
                                    }
                                }

                                if let result = turn.result,
                                   filteredMovies(from: result).isEmpty,
                                   filteredTV(from: result).isEmpty {
                                    assistantBubble("I couldn't find good matches with those constraints. Try changing format, vibe, or one core keyword.")
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

        let plan = await intentService.planTurn(message: message, state: conversationState)
        conversationState = intentService.apply(plan: plan, to: conversationState)

        var turn = DiscoveryChatTurn(
            userText: message,
            assistantSummary: nil,
            result: nil,
            displayPreference: plan.displayPreference
        )
        turns.append(turn)

        isSearching = true

        let discovery = await DiscoveryEngine.shared.discover(
            interest: intentService.effectiveQuery(for: conversationState),
            userMovies: movies,
            userTVShows: tvShows
        )

        turn.assistantSummary = plan.assistantLine?.isEmpty == false
            ? plan.assistantLine
            : intentService.fallbackAssistantSummary(plan: plan, state: conversationState)
        turn.result = discovery

        if let lastIndex = turns.indices.last {
            turns[lastIndex] = turn
        }

        isSearching = false
    }

    private func filteredMovies(from result: DiscoveryResult) -> [TMDBMovie] {
        let rejected = memoryStore.rejectedMovieIDs
        return result.recommendations.filter { movie in
            guard !rejected.contains(movie.id) else { return false }
            let coherence = result.movieRecommendationCoherence[movie.id] ?? 0
            return coherence >= coherenceThreshold
        }
    }

    private func filteredTV(from result: DiscoveryResult) -> [TMDBTVShow] {
        let rejected = memoryStore.rejectedTVIDs
        return result.tvRecommendations.filter { show in
            guard !rejected.contains(show.id) else { return false }
            let coherence = result.tvRecommendationCoherence[show.id] ?? 0
            return coherence >= coherenceThreshold
        }
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

#Preview {
    DiscoveryView()
}
