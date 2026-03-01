import SwiftUI
import SwiftData

struct DiscoveryView: View {
    @Query private var movies: [Movie]
    @Query private var tvShows: [TVShow]

    @State private var draftQuery = ""
    @State private var submittedQuery: String?
    @State private var isSearching = false
    @State private var result: DiscoveryResult?
    @State private var showingAddMovie: TMDBMovie?

    private let starterPrompts = [
        "space exploration",
        "thoughtful sci fi",
        "grounded non-fiction history",
        "murder mystery"
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        assistantBubble("Tell me what you want to watch, read, or listen to. I will return one strong movie pick and one strong TV pick.")

                        if submittedQuery == nil {
                            promptSuggestions
                        }

                        if let submittedQuery {
                            userBubble(submittedQuery)
                        }

                        if isSearching {
                            assistantBubble("Searching across your themes and ranking high-confidence picks...")
                        }

                        if let result, !isSearching {
                            discoveryResponse(result)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 100)
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
            TextField("Try: non-fiction space documentaries", text: $draftQuery)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onSubmit {
                    Task { await submitDraft() }
                }

            Button {
                Task { await submitDraft() }
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

    private var promptSuggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Starter prompts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starterPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            draftQuery = prompt
                            Task { await submitDraft() }
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

    @ViewBuilder
    private func discoveryResponse(_ result: DiscoveryResult) -> some View {
        let topicSummary = !result.understanding.mood.isEmpty
            ? result.understanding.mood
            : result.understanding.themes.joined(separator: ", ")

        if !topicSummary.isEmpty {
            assistantBubble("Got it. I optimized for: \(topicSummary).")
        }

        if let movie = result.recommendations.first {
            mediaBubble(
                title: movie.title,
                subtitle: mediaSubtitle(year: movie.year, rating: movie.voteAverage),
                reason: result.movieRecommendationReasons[movie.id] ?? "Strong fit for your query",
                posterURL: movie.posterURL,
                emoji: "🎬",
                actionTitle: "Add Movie",
                action: { showingAddMovie = movie }
            )
        } else {
            assistantBubble("I could not find a confident movie pick yet. Try adding one extra keyword.")
        }

        if let show = result.tvRecommendations.first {
            mediaBubble(
                title: show.title,
                subtitle: mediaSubtitle(year: show.year, rating: show.voteAverage),
                reason: result.tvRecommendationReasons[show.id] ?? "Strong fit for your query",
                posterURL: show.posterURL,
                emoji: "📺",
                actionTitle: nil,
                action: nil
            )
        } else {
            assistantBubble("I could not find a confident TV pick yet. Try clarifying genre or vibe.")
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

    private func submitDraft() async {
        let query = draftQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        submittedQuery = query
        isSearching = true
        result = nil

        let discovery = await DiscoveryEngine.shared.discover(
            interest: query,
            userMovies: movies,
            userTVShows: tvShows
        )

        result = discovery
        isSearching = false
    }
}

#Preview {
    DiscoveryView()
}
