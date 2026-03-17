import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Movie.dateAdded, order: .reverse) private var movies: [Movie]
    @Query(sort: \TVShow.dateAdded, order: .reverse) private var tvShows: [TVShow]
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @Query(sort: \PodcastEpisode.dateAdded, order: .reverse) private var podcastEpisodes: [PodcastEpisode]

    @State private var filterState = LibraryFilterState()
    @State private var searchText = ""
    @State private var activeSheet: AddMediaSheet?
    @State private var showingFilterSheet = false

    private var podcastShowGroups: [PodcastLibraryShowGroup] {
        Dictionary(grouping: podcastEpisodes, by: { $0.showName.trimmingCharacters(in: .whitespacesAndNewlines) })
            .map { name, episodes in
                let sorted = episodes.sorted { ($0.releaseDate ?? $0.dateAdded) > ($1.releaseDate ?? $1.dateAdded) }
                return PodcastLibraryShowGroup(
                    name: name,
                    episodes: sorted,
                    feedID: sorted.compactMap(\.podcastIndexFeedID).first,
                    feedURL: sorted.compactMap(\.feedURL).first,
                    artworkURL: sorted.compactMap(\.thumbnailURL).first
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var baseEntries: [LibraryEntry] {
        var entries: [LibraryEntry] = []
        entries.append(contentsOf: movies.map(LibraryEntry.movie))
        entries.append(contentsOf: tvShows.map(LibraryEntry.tvShow))
        entries.append(contentsOf: books.map(LibraryEntry.book))
        entries.append(contentsOf: podcastShowGroups.map(LibraryEntry.podcastShow))
        return entries
    }

    private var filteredEntries: [LibraryEntry] {
        var entries = baseEntries

        if filterState.type != .all {
            entries = entries.filter { $0.filterType == filterState.type }
        }

        if filterState.status != .all {
            entries = entries.filter { entry in
                switch filterState.status {
                case .all:
                    return true
                case .inProgress:
                    return entry.statusCategory == .inProgress
                case .planned:
                    return entry.statusCategory == .planned
                case .completed:
                    return entry.statusCategory == .completed
                }
            }
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            entries = entries.filter { entry in
                entry.searchIndex.contains { $0.contains(query) }
            }
        }

        switch filterState.sort {
        case .statusPriority:
            entries.sort { lhs, rhs in
                if lhs.statusCategory != rhs.statusCategory {
                    return lhs.statusCategory.sortRank < rhs.statusCategory.sortRank
                }
                return lhs.activityDate > rhs.activityDate
            }
        case .recentlyAdded:
            entries.sort { $0.dateAdded > $1.dateAdded }
        case .recentActivity:
            entries.sort { $0.activityDate > $1.activityDate }
        case .titleAZ:
            entries.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .highestRated:
            entries.sort { ($0.publicRating ?? -1) > ($1.publicRating ?? -1) }
        }

        return entries
    }

    private var groupedEntries: [(String, [LibraryEntry])] {
        guard filterState.groupByType else {
            let byStatus = Dictionary(grouping: filteredEntries, by: { $0.statusCategory })
            let order: [LibraryEntryStatus] = [.inProgress, .planned, .completed]
            return order.compactMap { status in
                guard let values = byStatus[status], !values.isEmpty else { return nil }
                return (status.label, values)
            }
        }

        let groups = Dictionary(grouping: filteredEntries, by: { $0.groupLabel })
        let ordered = ["Movies", "TV Shows", "Books", "Podcasts"]
        return ordered.compactMap { key in
            guard let values = groups[key], !values.isEmpty else { return nil }
            return (key, values)
        }
    }

    private var suggestions: [LibrarySearchSuggestion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        var items: [LibrarySearchSuggestion] = []

        for show in podcastShowGroups {
            let label = show.name
            if label.lowercased().contains(query) {
                items.append(.show(name: label))
            }
        }

        for episode in podcastEpisodes {
            if episode.title.lowercased().contains(query) {
                items.append(.episode(title: episode.title, showName: episode.showName))
            }
        }

        for title in movies.map(\.title) where title.lowercased().contains(query) {
            items.append(.item(title: title, type: .movies))
        }
        for title in tvShows.map(\.title) where title.lowercased().contains(query) {
            items.append(.item(title: title, type: .tv))
        }
        for title in books.map(\.title) where title.lowercased().contains(query) {
            items.append(.item(title: title, type: .books))
        }

        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }.prefix(10).map { $0 }
    }

    private var matchedPodcastEpisodes: [PodcastEpisode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return podcastEpisodes
            .filter { episode in
                episode.title.lowercased().contains(query)
                    || episode.showName.lowercased().contains(query)
            }
            .sorted { ($0.releaseDate ?? $0.dateAdded) > ($1.releaseDate ?? $1.dateAdded) }
            .prefix(8)
            .map { $0 }
    }

    private var personalRankingInsight: String? {
        var picks: [(String, Double)] = []
        picks.append(contentsOf: movies.compactMap { movie in
            guard let rating = movie.rating else { return nil }
            return (movie.title, rating)
        })
        picks.append(contentsOf: tvShows.compactMap { show in
            guard let rating = show.rating else { return nil }
            return (show.title, rating)
        })
        let ranked = picks.sorted { $0.1 > $1.1 }
        guard let top = ranked.first else { return nil }
        return "Your top pick: \(top.0) ★\(String(format: "%.1f", top.1))"
    }

    private var personalRankByItemKey: [String: Int] {
        var scored: [(String, Double)] = []
        scored.append(contentsOf: movies.compactMap { movie in
            guard let rating = movie.rating else { return nil }
            return ("movie:\(movie.id.uuidString)", rating)
        })
        scored.append(contentsOf: tvShows.compactMap { show in
            guard let rating = show.rating else { return nil }
            return ("tv:\(show.id.uuidString)", rating)
        })

        let ranked = scored.sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0 < rhs.0 }
            return lhs.1 > rhs.1
        }

        var result: [String: Int] = [:]
        for (index, item) in ranked.enumerated() {
            result[item.0] = index + 1
        }
        return result
    }

    private func personalRank(for entry: LibraryEntry) -> Int? {
        switch entry {
        case .movie(let movie):
            return personalRankByItemKey["movie:\(movie.id.uuidString)"]
        case .tvShow(let show):
            return personalRankByItemKey["tv:\(show.id.uuidString)"]
        case .book, .podcastShow:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerControls

                    if filteredEntries.isEmpty {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "sparkles",
                            description: Text("Try adjusting filters or search.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        ForEach(groupedEntries, id: \.0) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                if filterState.groupByType || groupedEntries.count > 1 {
                                    Text(section.0)
                                        .font(ConstellationTypeScale.sectionTitle)
                                        .padding(.horizontal, 4)
                                }

                                ForEach(section.1) { entry in
                                    entryCard(entry)
                                }
                            }
                        }

                        if !matchedPodcastEpisodes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Matching Episodes")
                                    .font(ConstellationTypeScale.sectionTitle)
                                    .padding(.horizontal, 4)

                                ForEach(matchedPodcastEpisodes) { episode in
                                    NavigationLink(destination: PodcastEpisodeDetailView(episode: episode)) {
                                        MediaLibraryCard(
                                            title: episode.title,
                                            subtitle: episode.showName,
                                            posterURL: episode.thumbnailURL,
                                            typeLabel: "Episode",
                                            typeColor: .purple,
                                            progressLabel: episode.completedAt == nil ? "In Progress" : "Completed",
                                            ratingLine: nil,
                                            themesHint: episode.themes.isEmpty ? "No themes yet" : episode.themes.prefix(3).map(displayTheme).joined(separator: " · "),
                                            rankingLabel: nil
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(libraryBackground)
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search your library") {
                ForEach(suggestions) { suggestion in
                    Button {
                        searchText = suggestion.queryText
                    } label: {
                        HStack {
                            Image(systemName: suggestion.icon)
                            Text(suggestion.displayText)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeSheet = .movie
                        } label: {
                            Label("Add Movie", systemImage: "film.fill")
                        }

                        Button {
                            activeSheet = .tvShow
                        } label: {
                            Label("Add TV Show", systemImage: "tv.fill")
                        }

                        Button {
                            activeSheet = .book
                        } label: {
                            Label("Add Book", systemImage: "book.closed.fill")
                        }

                        Button {
                            activeSheet = .podcast
                        } label: {
                            Label("Add Podcast", systemImage: "mic.fill")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .movie:
                    MovieSearchView()
                case .tvShow:
                    TVShowSearchView()
                case .book:
                    BookSearchView()
                case .podcast:
                    PodcastSearchView()
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                LibraryFilterSheet(state: $filterState)
            }
    }
    }
    
    private var libraryBackground: Color {
        Color(.systemBackground)
    }

    private var controlSurface: Color {
        Color(.secondarySystemBackground)
    }

    private var controlSurfaceSubtle: Color {
        Color(.tertiarySystemBackground)
    }

    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    showingFilterSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Advanced")
                            .font(ConstellationTypeScale.supporting.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(controlSurface)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(filterSummary)
                        .font(ConstellationTypeScale.caption)
                        .foregroundStyle(.secondary)
                    if let insight = personalRankingInsight {
                        Text(insight)
                            .font(.caption2)
                            .foregroundStyle(ConstellationPalette.accent)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickPill("Now", selected: filterState.status == .inProgress) { filterState.status = .inProgress }
                    quickPill("On Shelf", selected: filterState.status == .planned) { filterState.status = .planned }
                    quickPill("Done", selected: filterState.status == .completed) { filterState.status = .completed }
                    quickPill("All Status", selected: filterState.status == .all) { filterState.status = .all }

                    quickPill("All Media", selected: filterState.type == .all) { filterState.type = .all }
                    quickPill("Movies", selected: filterState.type == .movies) { filterState.type = .movies }
                    quickPill("TV", selected: filterState.type == .tv) { filterState.type = .tv }
                    quickPill("Books", selected: filterState.type == .books) { filterState.type = .books }
                    quickPill("Podcasts", selected: filterState.type == .podcasts) { filterState.type = .podcasts }
                }
            }
        }
    }

    private func quickPill(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(ConstellationTypeScale.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(selected ? ConstellationPalette.accent.opacity(0.16) : controlSurfaceSubtle)
                .foregroundStyle(selected ? ConstellationPalette.accent : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var filterSummary: String {
        let status = filterState.status.label
        let sort = filterState.sort.label
        let group = filterState.groupByType ? "Grouped" : "Flat"
        return "\(status) · \(sort) · \(group)"
    }

    @ViewBuilder
    private func entryCard(_ entry: LibraryEntry) -> some View {
        switch entry {
        case .movie(let movie):
            NavigationLink(destination: MovieDetailView(movie: movie)) {
                MediaLibraryCard(
                    title: movie.title,
                    subtitle: movie.year.map(String.init) ?? "Movie",
                    posterURL: movie.posterURL,
                    typeLabel: "Movie",
                    typeColor: .blue,
                    progressLabel: movie.watchedDate == nil ? "Planned" : "Completed",
                    ratingLine: mediaRatingLine(publicRating: movie.publicRating, publicCount: movie.publicRatingCount, personalRating: movie.rating),
                    themesHint: movie.themes.isEmpty ? nil : movie.themes.prefix(3).map(displayTheme).joined(separator: " · "),
                    rankingLabel: personalRank(for: entry).map { "#\($0)" }
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                completionAction(for: entry)
                deleteAction(for: entry)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                completionSwipe(for: entry)
                deleteSwipe(for: entry)
            }

        case .tvShow(let show):
            NavigationLink(destination: TVShowDetailView(show: show)) {
                MediaLibraryCard(
                    title: show.title,
                    subtitle: show.year.map(String.init) ?? "TV Show",
                    posterURL: show.posterURL,
                    typeLabel: "TV",
                    typeColor: .green,
                    progressLabel: show.watchedDate == nil ? "Planned" : "Completed",
                    ratingLine: mediaRatingLine(publicRating: show.publicRating, publicCount: show.publicRatingCount, personalRating: show.rating),
                    themesHint: show.themes.isEmpty ? nil : show.themes.prefix(3).map(displayTheme).joined(separator: " · "),
                    rankingLabel: personalRank(for: entry).map { "#\($0)" }
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                completionAction(for: entry)
                deleteAction(for: entry)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                completionSwipe(for: entry)
                deleteSwipe(for: entry)
            }

        case .book(let book):
            NavigationLink(destination: BookDetailView(book: book)) {
                MediaLibraryCard(
                    title: book.title,
                    subtitle: book.author ?? "Book",
                    posterURL: book.coverURL,
                    typeLabel: "Book",
                    typeColor: .orange,
                    progressLabel: book.watchedDate == nil ? "Planned" : "Completed",
                    ratingLine: mediaRatingLine(publicRating: book.rating, publicCount: book.ratingCount, personalRating: nil),
                    themesHint: book.themes.isEmpty ? nil : book.themes.prefix(3).map(displayTheme).joined(separator: " · "),
                    rankingLabel: nil
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                completionAction(for: entry)
                deleteAction(for: entry)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                completionSwipe(for: entry)
                deleteSwipe(for: entry)
            }

        case .podcastShow(let show):
            NavigationLink(destination: PodcastLibraryShowDetailView(group: show)) {
                MediaLibraryCard(
                    title: show.name,
                    subtitle: "\(show.episodes.count) added episode\(show.episodes.count == 1 ? "" : "s")",
                    posterURL: show.artworkURL,
                    typeLabel: "Podcast",
                    typeColor: .purple,
                    progressLabel: podcastProgressLabel(for: show),
                    ratingLine: nil,
                    themesHint: podcastThemeHint(for: show),
                    rankingLabel: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func mediaRatingLine(publicRating: Double?, publicCount: Int?, personalRating: Double?) -> String? {
        let publicPart = publicRating.map { rating in
            if let publicCount, publicCount > 0 {
                return "Public ★\(String(format: "%.1f", rating)) (\(formatCount(publicCount)))"
            }
            return "Public ★\(String(format: "%.1f", rating))"
        }
        let personalPart = personalRating.map { "Yours ★\(String(format: "%.1f", $0))" }
        return [publicPart, personalPart].compactMap { $0 }.joined(separator: " · ")
    }

    private func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    private func podcastProgressLabel(for show: PodcastLibraryShowGroup) -> String {
        let completed = show.episodes.filter { $0.completedAt != nil }.count
        if completed == show.episodes.count, completed > 0 { return "Completed" }
        let inProgress = show.episodes.filter { $0.currentPositionSeconds > 0 && $0.completedAt == nil }.count
        if inProgress > 0 { return "In Progress" }
        return "Planned"
    }

    private func podcastThemeHint(for show: PodcastLibraryShowGroup) -> String {
        let themes = show.episodes.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        if themes.isEmpty {
            return "No themes yet — generate themes from episode notes"
        }
        let unique = Array(Set(themes)).sorted()
        return unique.prefix(3).map(displayTheme).joined(separator: " · ")
    }

    private func displayTheme(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }

    @ViewBuilder
    private func completionAction(for entry: LibraryEntry) -> some View {
        switch entry {
        case .movie(let movie):
            Button(movie.watchedDate == nil ? "Mark Complete" : "Mark Incomplete") {
                movie.watchedDate = movie.watchedDate == nil ? Date() : nil
                try? modelContext.save()
            }
        case .tvShow(let show):
            Button(show.watchedDate == nil ? "Mark Complete" : "Mark Incomplete") {
                show.watchedDate = show.watchedDate == nil ? Date() : nil
                try? modelContext.save()
            }
        case .book(let book):
            Button(book.watchedDate == nil ? "Mark Read" : "Mark Unread") {
                book.watchedDate = book.watchedDate == nil ? Date() : nil
                try? modelContext.save()
            }
        case .podcastShow:
            EmptyView()
        }
    }

    @ViewBuilder
    private func completionSwipe(for entry: LibraryEntry) -> some View {
        switch entry {
        case .movie(let movie):
            Button(movie.watchedDate == nil ? "Complete" : "Undo") {
                movie.watchedDate = movie.watchedDate == nil ? Date() : nil
                try? modelContext.save()
            }
            .tint(movie.watchedDate == nil ? .green : .orange)
        case .tvShow(let show):
            Button(show.watchedDate == nil ? "Complete" : "Undo") {
                show.watchedDate = show.watchedDate == nil ? Date() : nil
                try? modelContext.save()
            }
            .tint(show.watchedDate == nil ? .green : .orange)
        case .book(let book):
            Button(book.watchedDate == nil ? "Read" : "Unread") {
                book.watchedDate = book.watchedDate == nil ? Date() : nil
                try? modelContext.save()
            }
            .tint(book.watchedDate == nil ? .green : .orange)
        case .podcastShow:
            EmptyView()
        }
    }

    private func deleteAction(for entry: LibraryEntry) -> some View {
        Button(role: .destructive) {
            delete(entry)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteSwipe(for entry: LibraryEntry) -> some View {
        Button(role: .destructive) {
            delete(entry)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func delete(_ entry: LibraryEntry) {
        switch entry {
        case .movie(let movie):
            modelContext.delete(movie)
        case .tvShow(let show):
            modelContext.delete(show)
        case .book(let book):
            modelContext.delete(book)
        case .podcastShow(let group):
            for episode in group.episodes {
                modelContext.delete(episode)
            }
        }
        try? modelContext.save()
    }
}

private struct MediaLibraryCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let posterURL: String?
    let typeLabel: String
    let typeColor: Color
    let progressLabel: String
    let ratingLine: String?
    let themesHint: String?
    let rankingLabel: String?

    var body: some View {
        HStack(spacing: 12) {
            ConstellationPosterView(
                imageURL: posterURL,
                symbol: "photo",
                width: 62,
                height: 92,
                cornerRadius: 10,
                contentMode: .fill
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(ConstellationTypeScale.supporting.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        if let rankingLabel, !rankingLabel.isEmpty {
                            Text(rankingLabel)
                                .font(ConstellationTypeScale.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.yellow.opacity(0.2))
                                .foregroundStyle(.yellow)
                                .clipShape(Capsule())
                        }

                        Text(typeLabel)
                            .font(ConstellationTypeScale.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(typeColor.opacity(0.16))
                            .foregroundStyle(typeColor)
                            .clipShape(Capsule())
                    }
                }

                Text(subtitle)
                    .font(ConstellationTypeScale.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(progressLabel)
                        .font(ConstellationTypeScale.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(progressColor.opacity(0.14))
                        .foregroundStyle(progressColor)
                        .clipShape(Capsule())

                    if let ratingLine, !ratingLine.isEmpty {
                        Text(ratingLine)
                            .font(ConstellationTypeScale.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let themesHint, !themesHint.isEmpty {
                    Text(themesHint)
                        .font(ConstellationTypeScale.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorder, lineWidth: 0.7)
        }
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.94)
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    private var progressColor: Color {
        switch progressLabel.lowercased() {
        case "completed":
            return .green
        case "in progress":
            return .blue
        default:
            return .orange
        }
    }
}

private struct LibraryFilterSheet: View {
    @Binding var state: LibraryFilterState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $state.type) {
                        ForEach(LibraryFilterType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                }

                Section("Status") {
                    Picker("Status", selection: $state.status) {
                        ForEach(LibraryStatusFilter.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                }

                Section("Sort") {
                    Picker("Sort", selection: $state.sort) {
                        ForEach(LibrarySortOption.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                }

                Section("Layout") {
                    Toggle("Group by Type", isOn: $state.groupByType)
                }
            }
            .navigationTitle("Advanced Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private enum LibrarySearchSuggestion: Identifiable {
    case show(name: String)
    case episode(title: String, showName: String)
    case item(title: String, type: LibraryFilterType)

    var id: String {
        switch self {
        case .show(let name): return "show-\(name.lowercased())"
        case .episode(let title, let show): return "ep-\(show.lowercased())-\(title.lowercased())"
        case .item(let title, let type): return "item-\(type.rawValue)-\(title.lowercased())"
        }
    }

    var queryText: String {
        switch self {
        case .show(let name): return name
        case .episode(let title, _): return title
        case .item(let title, _): return title
        }
    }

    var displayText: String {
        switch self {
        case .show(let name): return "\(name) (Show)"
        case .episode(let title, let showName): return "\(title) · \(showName)"
        case .item(let title, let type): return "\(title) (\(type.label))"
        }
    }

    var icon: String {
        switch self {
        case .show: return "mic.fill"
        case .episode: return "waveform"
        case .item(_, let type):
            switch type {
            case .movies: return "film"
            case .tv: return "tv"
            case .books: return "book"
            case .podcasts: return "mic"
            case .all: return "sparkles"
            }
        }
    }
}

private struct LibraryFilterState {
    var type: LibraryFilterType = .all
    var status: LibraryStatusFilter = .all
    var sort: LibrarySortOption = .statusPriority
    var groupByType = true
}

private enum LibraryFilterType: String, CaseIterable, Identifiable {
    case all
    case movies
    case tv
    case books
    case podcasts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .tv: return "TV"
        case .books: return "Books"
        case .podcasts: return "Podcasts"
        }
    }
}

private enum LibraryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case inProgress
    case planned
    case completed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .inProgress: return "In Progress"
        case .planned: return "On Shelf"
        case .completed: return "Completed"
        }
    }
}

private enum LibrarySortOption: String, CaseIterable, Identifiable {
    case statusPriority
    case recentlyAdded
    case recentActivity
    case titleAZ
    case highestRated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .statusPriority: return "Priority (Now -> Shelf -> Done)"
        case .recentlyAdded: return "Recently Added"
        case .recentActivity: return "Recent Activity"
        case .titleAZ: return "Title A–Z"
        case .highestRated: return "Highest Rated"
        }
    }
}

private enum LibraryEntry: Identifiable {
    case movie(Movie)
    case tvShow(TVShow)
    case book(Book)
    case podcastShow(PodcastLibraryShowGroup)

    var id: String {
        switch self {
        case .movie(let movie): return "movie-\(movie.id.uuidString)"
        case .tvShow(let show): return "tv-\(show.id.uuidString)"
        case .book(let book): return "book-\(book.id.uuidString)"
        case .podcastShow(let show): return "podcast-show-\(show.name.lowercased())"
        }
    }

    var title: String {
        switch self {
        case .movie(let movie): return movie.title
        case .tvShow(let show): return show.title
        case .book(let book): return book.title
        case .podcastShow(let show): return show.name
        }
    }

    var filterType: LibraryFilterType {
        switch self {
        case .movie: return .movies
        case .tvShow: return .tv
        case .book: return .books
        case .podcastShow: return .podcasts
        }
    }

    var groupLabel: String {
        switch self {
        case .movie: return "Movies"
        case .tvShow: return "TV Shows"
        case .book: return "Books"
        case .podcastShow: return "Podcasts"
        }
    }

    var dateAdded: Date {
        switch self {
        case .movie(let movie): return movie.dateAdded
        case .tvShow(let show): return show.dateAdded
        case .book(let book): return book.dateAdded
        case .podcastShow(let show): return show.episodes.map(\.dateAdded).max() ?? .distantPast
        }
    }

    var activityDate: Date {
        switch self {
        case .movie(let movie): return movie.watchedDate ?? movie.dateAdded
        case .tvShow(let show): return show.watchedDate ?? show.dateAdded
        case .book(let book): return book.watchedDate ?? book.dateAdded
        case .podcastShow(let show):
            let episodeDates = show.episodes.map { $0.completedAt ?? $0.dateAdded }
            return episodeDates.max() ?? .distantPast
        }
    }

    var publicRating: Double? {
        switch self {
        case .movie(let movie): return movie.publicRating
        case .tvShow(let show): return show.publicRating
        case .book(let book): return book.rating
        case .podcastShow: return nil
        }
    }

    var isCompleted: Bool {
        switch self {
        case .movie(let movie): return movie.watchedDate != nil
        case .tvShow(let show): return show.watchedDate != nil
        case .book(let book): return book.watchedDate != nil
        case .podcastShow(let show):
            return !show.episodes.isEmpty && show.episodes.allSatisfy { $0.completedAt != nil }
        }
    }

    var isInProgress: Bool {
        statusCategory == .inProgress
    }

    var statusCategory: LibraryEntryStatus {
        switch self {
        case .movie(let movie):
            return movie.watchedDate != nil ? .completed : .planned
        case .tvShow(let show):
            return show.watchedDate != nil ? .completed : .planned
        case .book(let book):
            return book.watchedDate != nil ? .completed : .planned
        case .podcastShow(let show):
            let hasStarted = show.episodes.contains { $0.currentPositionSeconds > 0 && $0.completedAt == nil }
            if hasStarted { return .inProgress }
            let isDone = !show.episodes.isEmpty && show.episodes.allSatisfy { $0.completedAt != nil }
            return isDone ? .completed : .planned
        }
    }

    var searchIndex: [String] {
        switch self {
        case .movie(let movie):
            return [movie.title, movie.director ?? "", movie.year.map(String.init) ?? ""].map { $0.lowercased() }
        case .tvShow(let show):
            return [show.title, show.creator ?? "", show.year.map(String.init) ?? ""].map { $0.lowercased() }
        case .book(let book):
            return [book.title, book.author ?? "", book.year.map(String.init) ?? ""].map { $0.lowercased() }
        case .podcastShow(let show):
            let titles = show.episodes.map(\.title)
            return ([show.name] + titles).map { $0.lowercased() }
        }
    }
}


private enum LibraryEntryStatus: String, CaseIterable {
    case inProgress
    case planned
    case completed

    var label: String {
        switch self {
        case .inProgress: return "In Progress"
        case .planned: return "On Shelf"
        case .completed: return "Completed"
        }
    }

    var sortRank: Int {
        switch self {
        case .inProgress: return 0
        case .planned: return 1
        case .completed: return 2
        }
    }
}

private enum AddMediaSheet: String, Identifiable {
    case movie
    case tvShow
    case book
    case podcast

    var id: String { rawValue }
}
