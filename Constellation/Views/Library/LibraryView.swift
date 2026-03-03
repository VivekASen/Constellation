import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Movie.dateAdded, order: .reverse) private var movies: [Movie]
    @Query(sort: \TVShow.dateAdded, order: .reverse) private var tvShows: [TVShow]
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var mode: LibraryMode = .all
    @State private var filter: LibraryMediaFilter = .all
    @State private var sortOption: LibrarySortOption = .recentlyAdded
    @State private var selectedTheme: String = "all"
    @State private var activeSheet: AddMediaSheet?
    @State private var markWatchedTarget: LibraryItem?
    @State private var watchedDate = Date()
    @State private var watchedRating = 0.0

    var body: some View {
        NavigationStack {
            List {
                modePickerSection
                mediaFilterSection
                sortAndThemeSection
                statsSection

                if mode == .watched, !favoriteItems.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteItems) { item in
                            itemRow(item)
                        }
                    }
                }

                Section(mode.sectionTitle) {
                    if visibleItems.isEmpty {
                        ContentUnavailableView(
                            mode.emptyTitle,
                            systemImage: mode.emptyIcon,
                            description: Text(mode.emptyDescription)
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(visibleItems) { item in
                            itemRow(item)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
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
                }
            }
            .sheet(item: $markWatchedTarget) { target in
                NavigationStack {
                    Form {
                        Section("Mark as Watched") {
                            Text(target.title)
                            DatePicker("Watched Date", selection: $watchedDate, displayedComponents: .date)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your Rating (optional)")
                                HStack(spacing: 8) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: star <= Int(watchedRating) ? "star.fill" : "star")
                                            .foregroundStyle(.yellow)
                                            .onTapGesture {
                                                watchedRating = Double(star)
                                            }
                                    }
                                }
                                .font(.title3)
                            }
                        }
                    }
                    .navigationTitle("Watched")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                markWatchedTarget = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                applyWatched(target: target)
                                markWatchedTarget = nil
                            }
                        }
                    }
                }
            }
            .onChange(of: mode) { _, _ in
                reconcileThemeFilter()
            }
            .onChange(of: filter) { _, _ in
                reconcileThemeFilter()
            }
        }
    }

    private var modePickerSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
                Text("All").tag(LibraryMode.all)
                Text("Watchlist").tag(LibraryMode.watchlist)
                Text("Watched").tag(LibraryMode.watched)
            }
            .pickerStyle(.segmented)
        }
    }

    private var mediaFilterSection: some View {
        Section {
            Picker("Type", selection: $filter) {
                Text("All").tag(LibraryMediaFilter.all)
                Text("Movies").tag(LibraryMediaFilter.movies)
                Text("TV").tag(LibraryMediaFilter.tv)
                Text("Books").tag(LibraryMediaFilter.books)
            }
            .pickerStyle(.segmented)
        }
    }

    private var sortAndThemeSection: some View {
        Section {
            HStack {
                Label("Sort", systemImage: "arrow.up.arrow.down")
                Spacer()
                Picker("Sort", selection: $sortOption) {
                    ForEach(LibrarySortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Label("Theme", systemImage: "sparkles")
                Spacer()
                Picker("Theme", selection: $selectedTheme) {
                    Text("All Themes").tag("all")
                    ForEach(availableThemes, id: \.self) { theme in
                        Text(theme.replacingOccurrences(of: "-", with: " ").capitalized).tag(theme)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var statsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    metricCard(
                        title: "Watchlist",
                        value: "\(watchlistItems.count)",
                        subtitle: "Items to watch",
                        tint: .blue
                    )
                    metricCard(
                        title: "Watched",
                        value: "\(watchedItems.count)",
                        subtitle: "Completed",
                        tint: .green
                    )
                    metricCard(
                        title: "Top Rated",
                        value: topRatedValue,
                        subtitle: topRatedSubtitle,
                        tint: .yellow
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var allItems: [LibraryItem] {
        let movieItems = movies.map(LibraryItem.movie)
        let showItems = tvShows.map(LibraryItem.tvShow)
        let bookItems = books.map(LibraryItem.book)
        return applyFilter(movieItems + showItems + bookItems)
    }

    private var watchlistItems: [LibraryItem] {
        allItems.filter { !$0.isWatched }
    }

    private var watchedItems: [LibraryItem] {
        allItems.filter(\.isWatched)
    }

    private var favoriteItems: [LibraryItem] {
        Array(
            watchedItems
                .filter { ($0.rating ?? 0) >= 4.0 }
                .sorted(by: rankSort)
                .prefix(10)
        )
    }

    private var visibleItems: [LibraryItem] {
        let byMode: [LibraryItem]
        switch mode {
        case .all:
            byMode = allItems
        case .watchlist:
            byMode = watchlistItems
        case .watched:
            byMode = watchedItems
        }

        let themeFiltered = applyThemeFilter(byMode)
        return sortItems(themeFiltered)
    }

    private var availableThemes: [String] {
        let sourceItems: [LibraryItem]
        switch mode {
        case .all:
            sourceItems = allItems
        case .watchlist:
            sourceItems = watchlistItems
        case .watched:
            sourceItems = watchedItems
        }

        let normalized = ThemeExtractor.shared.normalizeThemes(sourceItems.flatMap(\.themes))
        return Array(Set(normalized)).sorted()
    }

    private func applyFilter(_ items: [LibraryItem]) -> [LibraryItem] {
        switch filter {
        case .all:
            return items
        case .movies:
            return items.filter { $0.mediaType == .movie }
        case .tv:
            return items.filter { $0.mediaType == .tvShow }
        case .books:
            return items.filter { $0.mediaType == .book }
        }
    }

    private func applyThemeFilter(_ items: [LibraryItem]) -> [LibraryItem] {
        guard selectedTheme != "all" else { return items }
        return items.filter { item in
            ThemeExtractor.shared.normalizeThemes(item.themes).contains(selectedTheme)
        }
    }

    private func sortItems(_ items: [LibraryItem]) -> [LibraryItem] {
        switch sortOption {
        case .recentlyAdded:
            return items.sorted { $0.dateAdded > $1.dateAdded }
        case .oldestAdded:
            return items.sorted { $0.dateAdded < $1.dateAdded }
        case .highestRated:
            return items.sorted { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case .recentlyWatched:
            return items.sorted {
                ($0.watchedDate ?? .distantPast) > ($1.watchedDate ?? .distantPast)
            }
        case .titleAZ:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func rankSort(_ lhs: LibraryItem, _ rhs: LibraryItem) -> Bool {
        let leftRating = lhs.rating ?? -1
        let rightRating = rhs.rating ?? -1
        if leftRating != rightRating { return leftRating > rightRating }

        let leftWatched = lhs.watchedDate ?? .distantPast
        let rightWatched = rhs.watchedDate ?? .distantPast
        if leftWatched != rightWatched { return leftWatched > rightWatched }

        return lhs.dateAdded > rhs.dateAdded
    }

    @ViewBuilder
    private func itemRow(_ item: LibraryItem) -> some View {
        let destination: AnyView = {
            switch item {
            case .movie(let movie):
                return AnyView(MovieDetailView(movie: movie))
            case .tvShow(let show):
                return AnyView(TVShowDetailView(show: show))
            case .book(let book):
                return AnyView(BookDetailView(book: book))
            }
        }()

        HStack(spacing: 10) {
            NavigationLink(destination: destination) {
                rowContent(item)
            }
            .buttonStyle(.plain)

            if item.isWatched {
                ratingMenu(for: item)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if item.isWatched {
                Menu("Set Rating") {
                    ForEach(1...5, id: \.self) { star in
                        Button("\(star) Star\(star == 1 ? "" : "s")") {
                            setRating(item: item, rating: Double(star))
                        }
                    }
                    Button("Clear Rating") {
                        setRating(item: item, rating: nil)
                    }
                }
                Button {
                    markAsWatchlist(item: item)
                } label: {
                    Label("Move to Watchlist", systemImage: "bookmark")
                }
            } else {
                Button {
                    watchedDate = Date()
                    watchedRating = 0
                    markWatchedTarget = item
                } label: {
                    Label("Mark as Watched", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                deleteItem(item: item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if item.isWatched {
                Button("Watchlist") {
                    markAsWatchlist(item: item)
                }
                .tint(.orange)
            } else {
                Button("Watched") {
                    watchedDate = Date()
                    watchedRating = 0
                    markWatchedTarget = item
                }
                .tint(.green)
            }

            Button("Delete", role: .destructive) {
                deleteItem(item: item)
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.mediaLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(item.mediaColor.opacity(0.12))
                    .foregroundStyle(item.mediaColor)
                    .clipShape(Capsule())

                Text(item.isWatched ? "Watched" : "Watchlist")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(item.isWatched ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                    .foregroundStyle(item.isWatched ? .green : .orange)
                    .clipShape(Capsule())
            }
            HStack(spacing: 10) {
                if let year = item.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let rating = item.rating {
                    Text("★ \(String(format: "%.1f", rating))")
                        .font(.subheadline)
                        .foregroundStyle(.yellow)
                }
                if let watchedDate = item.watchedDate {
                    Text(watchedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !item.themes.isEmpty {
                Text(item.themes.prefix(3).map { $0.replacingOccurrences(of: "-", with: " ") }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func ratingMenu(for item: LibraryItem) -> some View {
        Menu {
            ForEach(1...5, id: \.self) { star in
                Button("\(star) Star\(star == 1 ? "" : "s")") {
                    setRating(item: item, rating: Double(star))
                }
            }
            Button("Clear Rating") {
                setRating(item: item, rating: nil)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "star.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                Text(item.rating.map { String(format: "%.1f", $0) } ?? "Rate")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 42)
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 130, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var topRatedValue: String {
        guard let top = watchedItems.first(where: { $0.rating != nil }),
              let rating = top.rating else { return "—" }
        return String(format: "%.1f ★", rating)
    }

    private var topRatedSubtitle: String {
        guard let top = watchedItems.first(where: { $0.rating != nil }) else { return "No ratings yet" }
        return top.title
    }

    private func applyWatched(target: LibraryItem) {
        switch target {
        case .movie(let movie):
            movie.watchedDate = watchedDate
            movie.rating = watchedRating > 0 ? watchedRating : nil
        case .tvShow(let show):
            show.watchedDate = watchedDate
            show.rating = watchedRating > 0 ? watchedRating : nil
        case .book(let book):
            book.watchedDate = watchedDate
            book.rating = watchedRating > 0 ? watchedRating : nil
        }
        try? modelContext.save()
    }

    private func markAsWatchlist(item: LibraryItem) {
        switch item {
        case .movie(let movie):
            movie.watchedDate = nil
            movie.rating = nil
        case .tvShow(let show):
            show.watchedDate = nil
            show.rating = nil
        case .book(let book):
            book.watchedDate = nil
            book.rating = nil
        }
        try? modelContext.save()
    }

    private func setRating(item: LibraryItem, rating: Double?) {
        switch item {
        case .movie(let movie):
            movie.rating = rating
        case .tvShow(let show):
            show.rating = rating
        case .book(let book):
            book.rating = rating
        }
        try? modelContext.save()
    }

    private func deleteItem(item: LibraryItem) {
        switch item {
        case .movie(let movie):
            modelContext.delete(movie)
        case .tvShow(let show):
            modelContext.delete(show)
        case .book(let book):
            modelContext.delete(book)
        }
        try? modelContext.save()
    }

    private func reconcileThemeFilter() {
        if selectedTheme != "all", !availableThemes.contains(selectedTheme) {
            selectedTheme = "all"
        }
    }
}

private enum LibraryMode: String, CaseIterable, Identifiable {
    case all
    case watchlist
    case watched

    var id: String { rawValue }

    var sectionTitle: String {
        switch self {
        case .all: return "Library"
        case .watchlist: return "Watchlist"
        case .watched: return "Watched"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "No Library Items"
        case .watchlist: return "No Watchlist Items"
        case .watched: return "No Watched Items"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all:
            return "Add movies, TV shows, or books to start building your library."
        case .watchlist:
            return "Add media, then keep upcoming picks here."
        case .watched:
            return "Mark items as watched to build your ranked favorites."
        }
    }

    var emptyIcon: String {
        switch self {
        case .all: return "books.vertical"
        case .watchlist: return "bookmark"
        case .watched: return "checkmark.circle"
        }
    }
}

private enum LibraryMediaFilter: String, CaseIterable, Identifiable {
    case all
    case movies
    case tv
    case books
    var id: String { rawValue }
}

private enum LibrarySortOption: String, CaseIterable, Identifiable {
    case recentlyAdded
    case oldestAdded
    case highestRated
    case recentlyWatched
    case titleAZ

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .oldestAdded: return "Oldest Added"
        case .highestRated: return "Highest Rated"
        case .recentlyWatched: return "Recently Watched"
        case .titleAZ: return "Title A–Z"
        }
    }
}

private enum LibraryItem: Identifiable {
    case movie(Movie)
    case tvShow(TVShow)
    case book(Book)

    var id: UUID {
        switch self {
        case .movie(let movie): return movie.id
        case .tvShow(let show): return show.id
        case .book(let book): return book.id
        }
    }

    var title: String {
        switch self {
        case .movie(let movie): return movie.title
        case .tvShow(let show): return show.title
        case .book(let book): return book.title
        }
    }

    var mediaType: MediaType {
        switch self {
        case .movie: return .movie
        case .tvShow: return .tvShow
        case .book: return .book
        }
    }

    var mediaLabel: String {
        switch self {
        case .movie: return "Movie"
        case .tvShow: return "TV"
        case .book: return "Book"
        }
    }

    var mediaColor: Color {
        switch self {
        case .movie: return .blue
        case .tvShow: return .green
        case .book: return .orange
        }
    }

    var isWatched: Bool {
        watchedDate != nil
    }

    var year: Int? {
        switch self {
        case .movie(let movie): return movie.year
        case .tvShow(let show): return show.year
        case .book(let book): return book.year
        }
    }

    var rating: Double? {
        switch self {
        case .movie(let movie): return movie.rating
        case .tvShow(let show): return show.rating
        case .book(let book): return book.rating
        }
    }

    var watchedDate: Date? {
        switch self {
        case .movie(let movie): return movie.watchedDate
        case .tvShow(let show): return show.watchedDate
        case .book(let book): return book.watchedDate
        }
    }

    var dateAdded: Date {
        switch self {
        case .movie(let movie): return movie.dateAdded
        case .tvShow(let show): return show.dateAdded
        case .book(let book): return book.dateAdded
        }
    }

    var themes: [String] {
        switch self {
        case .movie(let movie): return movie.themes
        case .tvShow(let show): return show.themes
        case .book(let book): return book.themes
        }
    }
}

private enum AddMediaSheet: String, Identifiable {
    case movie
    case tvShow
    case book

    var id: String { rawValue }
}
