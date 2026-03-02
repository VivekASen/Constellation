import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Movie.dateAdded, order: .reverse) private var movies: [Movie]
    @Query(sort: \TVShow.dateAdded, order: .reverse) private var tvShows: [TVShow]

    @State private var mode: LibraryMode = .watchlist
    @State private var filter: LibraryMediaFilter = .all
    @State private var activeSheet: AddMediaSheet?
    @State private var markWatchedTarget: LibraryItem?
    @State private var watchedDate = Date()
    @State private var watchedRating = 0.0

    var body: some View {
        NavigationStack {
            List {
                modePickerSection
                mediaFilterSection

                if mode == .watched, !favoriteItems.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteItems) { item in
                            itemRow(item)
                        }
                    }
                }

                Section(mode == .watchlist ? "Watchlist" : "Watched") {
                    if visibleItems.isEmpty {
                        ContentUnavailableView(
                            mode == .watchlist ? "No Watchlist Items" : "No Watched Items",
                            systemImage: mode == .watchlist ? "bookmark" : "checkmark.circle",
                            description: Text(mode == .watchlist
                                ? "Add movies or TV shows to your watchlist from Discover."
                                : "Mark items as watched to build your ranked favorites."
                            )
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
        }
    }

    private var modePickerSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
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
            }
            .pickerStyle(.segmented)
        }
    }

    private var watchlistItems: [LibraryItem] {
        let movieItems = movies.filter { $0.watchedDate == nil }.map(LibraryItem.movie)
        let showItems = tvShows.filter { $0.watchedDate == nil }.map(LibraryItem.tvShow)
        return applyFilter(movieItems + showItems)
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    private var watchedItems: [LibraryItem] {
        let movieItems = movies.filter { $0.watchedDate != nil }.map(LibraryItem.movie)
        let showItems = tvShows.filter { $0.watchedDate != nil }.map(LibraryItem.tvShow)
        return applyFilter(movieItems + showItems)
            .sorted(by: rankSort)
    }

    private var favoriteItems: [LibraryItem] {
        Array(
            watchedItems
                .filter { ($0.rating ?? 0) >= 4.0 }
                .prefix(10)
        )
    }

    private var visibleItems: [LibraryItem] {
        mode == .watchlist ? watchlistItems : watchedItems
    }

    private func applyFilter(_ items: [LibraryItem]) -> [LibraryItem] {
        switch filter {
        case .all:
            return items
        case .movies:
            return items.filter(\.isMovie)
        case .tv:
            return items.filter { !$0.isMovie }
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
            }
        }()

        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.isMovie ? "Movie" : "TV")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.isMovie ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                        .foregroundStyle(item.isMovie ? .blue : .green)
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
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if mode == .watchlist {
                Button("Watched") {
                    watchedDate = Date()
                    watchedRating = 0
                    markWatchedTarget = item
                }
                .tint(.green)
            } else {
                Button("Move to Watchlist") {
                    markAsWatchlist(item: item)
                }
                .tint(.orange)
            }
        }
    }

    private func applyWatched(target: LibraryItem) {
        switch target {
        case .movie(let movie):
            movie.watchedDate = watchedDate
            movie.rating = watchedRating > 0 ? watchedRating : nil
        case .tvShow(let show):
            show.watchedDate = watchedDate
            show.rating = watchedRating > 0 ? watchedRating : nil
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
        }
        try? modelContext.save()
    }
}

private enum LibraryMode: String, CaseIterable, Identifiable {
    case watchlist
    case watched
    var id: String { rawValue }
}

private enum LibraryMediaFilter: String, CaseIterable, Identifiable {
    case all
    case movies
    case tv
    var id: String { rawValue }
}

private enum LibraryItem: Identifiable {
    case movie(Movie)
    case tvShow(TVShow)

    var id: UUID {
        switch self {
        case .movie(let movie): return movie.id
        case .tvShow(let show): return show.id
        }
    }

    var title: String {
        switch self {
        case .movie(let movie): return movie.title
        case .tvShow(let show): return show.title
        }
    }

    var isMovie: Bool {
        if case .movie = self { return true }
        return false
    }

    var year: Int? {
        switch self {
        case .movie(let movie): return movie.year
        case .tvShow(let show): return show.year
        }
    }

    var rating: Double? {
        switch self {
        case .movie(let movie): return movie.rating
        case .tvShow(let show): return show.rating
        }
    }

    var watchedDate: Date? {
        switch self {
        case .movie(let movie): return movie.watchedDate
        case .tvShow(let show): return show.watchedDate
        }
    }

    var dateAdded: Date {
        switch self {
        case .movie(let movie): return movie.dateAdded
        case .tvShow(let show): return show.dateAdded
        }
    }
}

private enum AddMediaSheet: String, Identifiable {
    case movie
    case tvShow

    var id: String { rawValue }
}
