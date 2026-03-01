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

    private let starterPrompts = [
        "space exploration",
        "murder mystery",
        "historical non-fiction",
        "thoughtful sci fi"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.22, blue: 0.52),
                        Color(red: 0.06, green: 0.18, blue: 0.43),
                        Color(red: 0.03, green: 0.11, blue: 0.29)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            assistantBubble("Tell me a topic and I will keep refining with you. I will return one strong movie pick and one strong TV pick each turn.")

                            if turns.isEmpty {
                                starterPromptSection
                            }

                            ForEach(turns) { turn in
                                userBubble(turn.userText)

                                if let summary = turn.assistantSummary {
                                    assistantBubble(summary)
                                }

                                if let movie = turn.result?.recommendations.first {
                                    mediaBubble(
                                        title: movie.title,
                                        subtitle: mediaSubtitle(year: movie.year, rating: movie.voteAverage),
                                        reason: turn.result?.movieRecommendationReasons[movie.id] ?? "Strong fit for your request",
                                        posterURL: movie.posterURL,
                                        emoji: "🎬",
                                        actionTitle: "Add Movie",
                                        action: { showingAddMovie = movie }
                                    )
                                }

                                if let show = turn.result?.tvRecommendations.first {
                                    mediaBubble(
                                        title: show.title,
                                        subtitle: mediaSubtitle(year: show.year, rating: show.voteAverage),
                                        reason: turn.result?.tvRecommendationReasons[show.id] ?? "Strong fit for your request",
                                        posterURL: show.posterURL,
                                        emoji: "📺",
                                        actionTitle: nil,
                                        action: nil
                                    )
                                }

                                if let result = turn.result,
                                   result.recommendations.isEmpty,
                                   result.tvRecommendations.isEmpty {
                                    assistantBubble("I could not find confident picks for that yet. Add one more concrete cue (topic, format, or fiction/non-fiction).")
                                }
                            }

                            if isSearching {
                                assistantBubble("Updating recommendations with your latest message...")
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
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $showingAddMovie) { movie in
                MovieDetailSheet(movie: movie)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Type your next message...", text: $draftQuery)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onSubmit {
                    Task { await submitMessage(draftQuery) }
                }

            Button {
                Task { await submitMessage(draftQuery) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(draftQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray.opacity(0.5) : .white)
            }
            .disabled(draftQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var starterPromptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Starter prompts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starterPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            Task { await submitMessage(prompt) }
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.16))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.10))
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

        turn.assistantSummary = conversationState.summaryLine
        turn.result = discovery

        if let lastIndex = turns.indices.last {
            turns[lastIndex] = turn
        }

        isSearching = false
    }

    private func updateConversationState(with message: String) {
        let normalized = normalizedIntentText(message)

        if containsAny(normalized, terms: ["reset", "start over", "new topic"]) {
            conversationState = DiscoveryConversationState(topic: nil)
            return
        }

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
        } else if containsAny(normalized, terms: ["tv only", "show only", "shows only", "series only", "tv shows only"]) {
            conversationState.mediaMode = .tvOnly
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
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Spacer(minLength: 24)
        }
    }

    @ViewBuilder
    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color(red: 0.03, green: 0.20, blue: 0.46))
                .padding(12)
                .background(Color.white.opacity(0.95))
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
        action: (() -> Void)?
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
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))

                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)

                if let actionTitle, let action {
                    Button(actionTitle) {
                        action()
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DiscoveryChatTurn: Identifiable {
    let id = UUID()
    let userText: String
    var assistantSummary: String?
    var result: DiscoveryResult?
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
