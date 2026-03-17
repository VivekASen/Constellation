import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Bindable var book: Book
    @Environment(\.modelContext) private var modelContext

    @Query private var allMovies: [Movie]
    @Query private var allTVShows: [TVShow]
    @Query private var allBooks: [Book]
    @Query private var allPodcasts: [PodcastEpisode]

    @State private var showConnectionsSheet = false

    private var normalizedThemes: [String] {
        ThemeExtractor.shared.normalizeThemes(book.themes)
    }

    private var connectionItems: [MediaConnectionItem] {
        guard !normalizedThemes.isEmpty else { return [] }

        var items: [MediaConnectionItem] = []

        for movie in allMovies {
            let shared = sharedThemes(with: movie.themes)
            guard !shared.isEmpty else { continue }
            items.append(
                MediaConnectionItem(
                    id: "movie-\(movie.id.uuidString)",
                    title: movie.title,
                    subtitle: movie.year.map(String.init) ?? "",
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

        for other in allBooks where other.id != book.id {
            let shared = sharedThemes(with: other.themes)
            guard !shared.isEmpty else { continue }
            items.append(
                MediaConnectionItem(
                    id: "book-\(other.id.uuidString)",
                    title: other.title,
                    subtitle: other.author ?? "",
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
        let ratingValue = book.rating.map { String(format: "%.1f", $0) } ?? "-"
        let pagesValue = book.pageCount.map(String.init) ?? "-"
        return [
            ConstellationHeroMetric(value: ratingValue, label: "Rating", icon: "star.fill"),
            ConstellationHeroMetric(value: pagesValue, label: "Pages", icon: "book.pages"),
            ConstellationHeroMetric(value: "\(connectionItems.count)", label: "Connections", icon: "sparkles", key: "connections")
        ]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ConstellationStarHeroHeader(
                    posterURL: book.coverURL,
                    symbol: "book.closed",
                    title: book.title,
                    subtitle: book.author,
                    metrics: headerMetrics,
                    onMetricTap: { metric in
                        guard metric.key == "connections", !connectionItems.isEmpty else { return }
                        showConnectionsSheet = true
                    }
                )

                VStack(alignment: .leading, spacing: 20) {
                    if let overview = book.overview, !overview.isEmpty {
                        ConstellationDetailSection("Description") {
                            Text(overview)
                                .font(ConstellationTypeScale.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !book.genres.isEmpty {
                        ConstellationDetailSection("Genre") {
                            Text(book.genres.first ?? "")
                                .font(ConstellationTypeScale.supporting)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !book.themes.isEmpty {
                        ConstellationDetailSection("Themes") {
                            FlowLayout(spacing: 8) {
                                ForEach(book.themes, id: \.self) { theme in
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
        .task(id: book.id) {
            await ensureThemesIfMissing()
        }
    }

    private func sharedThemes(with themes: [String]) -> [String] {
        let normalizedOther = Set(ThemeExtractor.shared.normalizeThemes(themes))
        return normalizedThemes.filter { normalizedOther.contains($0) }
    }

    private func ensureThemesIfMissing() async {
        guard book.themes.isEmpty else { return }
        let generatedThemes = await ThemeExtractor.shared.extractThemes(from: book)
        guard !generatedThemes.isEmpty else { return }
        book.themes = generatedThemes
        try? modelContext.save()
    }
}
