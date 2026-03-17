import SwiftUI
import SwiftData

struct MovieDetailView: View {
    let movie: Movie
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Query private var allMovies: [Movie]
    @Query private var allTVShows: [TVShow]
    @Query private var allBooks: [Book]
    @Query private var allPodcasts: [PodcastEpisode]

    @State private var trailer: TMDBVideo?
    @State private var watchProviders: [TMDBWatchProvider] = []
    @State private var similarMovies: [TMDBMovie] = []
    @State private var isLoadingExtras = false
    @State private var showConnectionsSheet = false

    private var normalizedThemes: [String] {
        ThemeExtractor.shared.normalizeThemes(movie.themes)
    }

    private var connectionItems: [MediaConnectionItem] {
        guard !normalizedThemes.isEmpty else { return [] }

        var items: [MediaConnectionItem] = []

        for other in allMovies where other.id != movie.id {
            let shared = sharedThemes(with: other.themes)
            guard !shared.isEmpty else { continue }
            items.append(
                MediaConnectionItem(
                    id: "movie-\(other.id.uuidString)",
                    title: other.title,
                    subtitle: other.year.map(String.init) ?? "",
                    typeLabel: "Movie",
                    sharedThemes: shared
                )
            )
        }

        for show in allTVShows {
            let shared = sharedThemes(with: show.themes)
            guard !shared.isEmpty else { continue }
            items.append(
                MediaConnectionItem(
                    id: "tv-\(show.id.uuidString)",
                    title: show.title,
                    subtitle: show.creator ?? "",
                    typeLabel: "TV",
                    sharedThemes: shared
                )
            )
        }

        for book in allBooks {
            let shared = sharedThemes(with: book.themes)
            guard !shared.isEmpty else { continue }
            items.append(
                MediaConnectionItem(
                    id: "book-\(book.id.uuidString)",
                    title: book.title,
                    subtitle: book.author ?? "",
                    typeLabel: "Book",
                    sharedThemes: shared
                )
            )
        }

        for episode in allPodcasts {
            let shared = sharedThemes(with: episode.themes)
            guard !shared.isEmpty else { continue }
            items.append(
                MediaConnectionItem(
                    id: "podcast-\(episode.id.uuidString)",
                    title: episode.title,
                    subtitle: episode.showName,
                    typeLabel: "Podcast",
                    sharedThemes: shared
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.sharedThemes.count == rhs.sharedThemes.count {
                return lhs.title < rhs.title
            }
            return lhs.sharedThemes.count > rhs.sharedThemes.count
        }
    }

    private var headerMetrics: [ConstellationHeroMetric] {
        let ratingValue = movie.publicRating.map { String(format: "%.1f", $0) } ?? "-"
        let yearValue = movie.year.map(String.init) ?? "-"
        return [
            ConstellationHeroMetric(value: ratingValue, label: "Rating", icon: "star.fill"),
            ConstellationHeroMetric(value: yearValue, label: "Release", icon: "calendar"),
            ConstellationHeroMetric(value: "\(connectionItems.count)", label: "Connections", icon: "sparkles", key: "connections")
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ConstellationStarHeroHeader(
                    posterURL: movie.posterURL,
                    symbol: "film",
                    title: movie.title,
                    subtitle: movie.director,
                    metrics: headerMetrics,
                    onMetricTap: { metric in
                        guard metric.key == "connections", !connectionItems.isEmpty else { return }
                        showConnectionsSheet = true
                    }
                )

                VStack(alignment: .leading, spacing: 20) {
                    if let overview = movie.overview, !overview.isEmpty {
                        ConstellationDetailSection("Description") {
                            Text(overview)
                                .font(ConstellationTypeScale.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isLoadingExtras {
                        ProgressView("Loading trailers and streaming info…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let trailer, let url = trailer.youtubeURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Watch Trailer", systemImage: "play.fill")
                                .font(ConstellationTypeScale.supporting.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(ConstellationPalette.accent)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if !watchProviders.isEmpty {
                        ConstellationDetailSection("Where to Watch") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(watchProviders.prefix(12)) { provider in
                                        HStack(spacing: 6) {
                                            if let logo = provider.logoURL {
                                                AsyncImage(url: logo) { image in
                                                    image.resizable().scaledToFit()
                                                } placeholder: {
                                                    Color.white.opacity(0.35)
                                                }
                                                .frame(width: 16, height: 16)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                            Text(provider.providerName)
                                                .font(ConstellationTypeScale.caption)
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(Color.green.opacity(0.9))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    if !movie.genres.isEmpty {
                        ConstellationDetailSection("Genres") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(movie.genres, id: \.self) { genre in
                                        ConstellationTagPill(text: genre)
                                    }
                                }
                            }
                        }
                    }

                    if !movie.themes.isEmpty {
                        ConstellationDetailSection("Themes") {
                            FlowLayout(spacing: 8) {
                                ForEach(movie.themes, id: \.self) { theme in
                                    NavigationLink(destination: ThemeDetailView(themeName: theme)) {
                                        ConstellationTagPill(
                                            text: theme.replacingOccurrences(of: "-", with: " ").capitalized
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !similarMovies.isEmpty {
                        ConstellationDetailSection("Similar Picks") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(similarMovies.prefix(8)) { similar in
                                        VStack(alignment: .leading, spacing: 6) {
                                            AsyncImage(url: similar.posterURL) { image in
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle().fill(Color.gray.opacity(0.2))
                                            }
                                            .frame(width: 110, height: 165)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                            Text(similar.title)
                                                .font(ConstellationTypeScale.caption.weight(.semibold))
                                                .lineLimit(2)
                                                .frame(width: 110, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showConnectionsSheet) {
            MediaConnectionsView(title: "Connections", items: connectionItems)
        }
        .task(id: movie.id) {
            await loadEnhancements()
            await ensureThemesIfMissing()
        }
    }

    private func sharedThemes(with themes: [String]) -> [String] {
        let normalizedOther = Set(ThemeExtractor.shared.normalizeThemes(themes))
        return normalizedThemes.filter { normalizedOther.contains($0) }
    }

    private func loadEnhancements() async {
        guard let tmdbID = movie.tmdbID else { return }
        isLoadingExtras = true
        defer { isLoadingExtras = false }

        async let videosTask = TMDBService.shared.getMovieVideos(movieID: tmdbID)
        async let providersTask = TMDBService.shared.getMovieWatchProviders(movieID: tmdbID)
        async let similarTask = TMDBService.shared.getSimilarMovies(movieID: tmdbID)
        async let detailTask = TMDBService.shared.getMovieDetails(id: tmdbID)

        do {
            let videos = try await videosTask
            trailer = videos.first(where: { video in
                video.site.lowercased() == "youtube" && (video.type == "Trailer" || video.official == true)
            }) ?? videos.first(where: { $0.site.lowercased() == "youtube" })
        } catch {
            trailer = nil
        }

        do {
            watchProviders = try await providersTask
        } catch {
            watchProviders = []
        }

        do {
            similarMovies = try await similarTask
                .filter { $0.voteCount ?? 0 >= 120 }
                .sorted { lhs, rhs in
                    let l = (lhs.voteAverage ?? 0) * log10(Double(max(lhs.voteCount ?? 1, 1)))
                    let r = (rhs.voteAverage ?? 0) * log10(Double(max(rhs.voteCount ?? 1, 1)))
                    return l > r
                }
        } catch {
            similarMovies = []
        }

        do {
            let details = try await detailTask
            if movie.publicRating == nil || movie.publicRatingCount == nil {
                movie.publicRating = details.voteAverage
                movie.publicRatingCount = details.voteCount
                try? modelContext.save()
            }
        } catch {
            // Ignore rating backfill errors.
        }
    }

    private func ensureThemesIfMissing() async {
        guard movie.themes.isEmpty else { return }
        let generatedThemes = await ThemeExtractor.shared.extractThemes(from: movie)
        guard !generatedThemes.isEmpty else { return }
        movie.themes = generatedThemes
        try? modelContext.save()
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    private struct FlowResult {
        var size: CGSize
        var positions: [CGPoint]

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var positions: [CGPoint] = []
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let viewSize = subview.sizeThatFits(.unspecified)
                if x + viewSize.width > maxWidth, x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                x += viewSize.width + spacing
                rowHeight = max(rowHeight, viewSize.height)
            }

            self.positions = positions
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}
