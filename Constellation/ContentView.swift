//
//  ContentView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/25/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
            
            CollectionsView()
                .tabItem {
                    Label("Collections", systemImage: "square.stack.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(ConstellationPalette.accent)
    }
}

private enum AddMediaSheet: String, Identifiable {
    case movie
    case tvShow
    
    var id: String { rawValue }
}

struct HomeView: View {
    @Query(sort: \Movie.dateAdded, order: .reverse) private var movies: [Movie]
    @Query(sort: \TVShow.dateAdded, order: .reverse) private var tvShows: [TVShow]
    @Query private var collections: [ItemCollection]

    
    @AppStorage("recommend.enableTasteDiveBlend") private var enableTasteDiveBlend = false
    @AppStorage("tastedive.apiKey") private var tasteDiveAPIKey = ""
    @State private var activeSheet: AddMediaSheet?
    @State private var homeSuggestions: [HomeSuggestion] = []
    @State private var isLoadingSuggestions = false
    
    var allThemes: [String] {
        let movieThemes = movies.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        let tvThemes = tvShows.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        return Array(Set(movieThemes + tvThemes)).sorted()
    }
    
    var totalItems: Int {
        movies.count + tvShows.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Constellation")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Your knowledge graph")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    HStack(spacing: 16) {
                        StatCard(title: "Items", count: totalItems, icon: "✨")
                        
                        NavigationLink(destination: AllThemesView()) {
                            StatCard(title: "Themes", count: allThemes.count, icon: "⭐")
                        }
                        .buttonStyle(.plain)
                        
                        StatCard(title: "Collections", count: collections.count, icon: "📚")
                        
                    }
                    .padding(.horizontal)

                    if totalItems > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            ConstellationGraphView(
                                movies: movies,
                                tvShows: tvShows,
                                collections: collections
                            )
                        }
                        .padding(.horizontal)
                    }

                    if !homeSuggestions.isEmpty || isLoadingSuggestions {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Because You Watched")
                                    .font(.headline)
                                Spacer()
                                if isLoadingSuggestions {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(homeSuggestions) { suggestion in
                                        HomeSuggestionCard(suggestion: suggestion)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    if !movies.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Movies")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(movies.prefix(5)) { movie in
                                NavigationLink(destination: MovieDetailView(movie: movie)) {
                                    MovieRow(movie: movie)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    if !tvShows.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent TV Shows")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(tvShows.prefix(5)) { show in
                                NavigationLink(destination: TVShowDetailView(show: show)) {
                                    TVShowRow(show: show)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    if movies.isEmpty && tvShows.isEmpty {
                        VStack(spacing: 16) {
                            Text("🌟")
                                .font(.system(size: 60))
                            
                            Text("Start Your Constellation")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Add movies and TV shows to discover connections")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                            
                            HStack(spacing: 12) {
                                Button(action: { activeSheet = .movie }) {
                                    Label("Add Movie", systemImage: "film.fill")
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                                
                                Button(action: { activeSheet = .tvShow }) {
                                    Label("Add TV Show", systemImage: "tv.fill")
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 60)
                    }
                }
                .padding(.vertical)
            }
            .toolbar {
                ToolbarItem {
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
            .task(id: movies.map(\.id).description + tvShows.map(\.id).description) {
                await loadHomeSuggestions()
            }
        }
    }

    private func loadHomeSuggestions() async {
        guard !movies.isEmpty || !tvShows.isEmpty else {
            homeSuggestions = []
            return
        }

        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        let existingMovieIDs = Set(movies.compactMap(\.tmdbID))
        let existingTVIDs = Set(tvShows.compactMap(\.tmdbID))
        let preferenceTerms = buildPreferenceTerms()

        var candidates: [HomeSuggestion] = []

        let movieSeeds = movies
            .filter { $0.watchedDate != nil }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .prefix(2)
            .compactMap(\.tmdbID)

        for seed in movieSeeds {
            let similar = (try? await TMDBService.shared.getMovieRecommendations(movieID: seed, page: 1)) ?? []
            for item in similar where !existingMovieIDs.contains(item.id) {
                candidates.append(
                    HomeSuggestion(
                        id: "movie-\(item.id)",
                        title: item.title,
                        subtitle: item.year.map(String.init) ?? "Movie",
                        posterURL: item.posterURL,
                        reason: "Matched by similar audience taste",
                        mediaType: .movie,
                        score: blendedScore(
                            title: item.title,
                            overview: item.overview,
                            voteAverage: item.voteAverage,
                            voteCount: item.voteCount,
                            sourceBoost: 1.0,
                            preferenceTerms: preferenceTerms
                        )
                    )
                )
            }
        }

        let showSeeds = tvShows
            .filter { $0.watchedDate != nil }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .prefix(2)
            .compactMap(\.tmdbID)

        for seed in showSeeds {
            let similar = (try? await TMDBService.shared.getTVRecommendations(tvID: seed, page: 1)) ?? []
            for item in similar where !existingTVIDs.contains(item.id) {
                candidates.append(
                    HomeSuggestion(
                        id: "tv-\(item.id)",
                        title: item.title,
                        subtitle: item.year.map(String.init) ?? "TV Show",
                        posterURL: item.posterURL,
                        reason: "Matched by similar audience taste",
                        mediaType: .tv,
                        score: blendedScore(
                            title: item.title,
                            overview: item.overview,
                            voteAverage: item.voteAverage,
                            voteCount: item.voteCount,
                            sourceBoost: 1.0,
                            preferenceTerms: preferenceTerms
                        )
                    )
                )
            }
        }

        if enableTasteDiveBlend && !tasteDiveAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let movieSeedTitles = movies
                .filter { $0.watchedDate != nil || ($0.rating ?? 0) >= 4.0 }
                .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
                .prefix(2)
                .map(\.title)
            let tvSeedTitles = tvShows
                .filter { $0.watchedDate != nil || ($0.rating ?? 0) >= 4.0 }
                .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
                .prefix(2)
                .map(\.title)
            let seedTitles = Array(NSOrderedSet(array: movieSeedTitles + tvSeedTitles)) as? [String] ?? []

            for seedTitle in seedTitles {
                let tasteResults = (try? await TasteDiveService.shared.similar(query: seedTitle, limit: 8)) ?? []
                for tasteResult in tasteResults.prefix(6) {
                    let mediaHint = parseTasteDiveMediaType(tasteResult.type)
                    switch mediaHint {
                    case .movie:
                        if let movie = await bestMovieMatch(for: tasteResult.name),
                           !existingMovieIDs.contains(movie.id) {
                            candidates.append(
                                HomeSuggestion(
                                    id: "movie-\(movie.id)",
                                    title: movie.title,
                                    subtitle: movie.year.map(String.init) ?? "Movie",
                                    posterURL: movie.posterURL,
                                    reason: "Taste graph match from \(seedTitle)",
                                    mediaType: .movie,
                                    score: blendedScore(
                                        title: movie.title,
                                        overview: movie.overview,
                                        voteAverage: movie.voteAverage,
                                        voteCount: movie.voteCount,
                                        sourceBoost: 1.3,
                                        preferenceTerms: preferenceTerms
                                    )
                                )
                            )
                        }
                    case .tv:
                        if let show = await bestTVMatch(for: tasteResult.name),
                           !existingTVIDs.contains(show.id) {
                            candidates.append(
                                HomeSuggestion(
                                    id: "tv-\(show.id)",
                                    title: show.title,
                                    subtitle: show.year.map(String.init) ?? "TV Show",
                                    posterURL: show.posterURL,
                                    reason: "Taste graph match from \(seedTitle)",
                                    mediaType: .tv,
                                    score: blendedScore(
                                        title: show.title,
                                        overview: show.overview,
                                        voteAverage: show.voteAverage,
                                        voteCount: show.voteCount,
                                        sourceBoost: 1.3,
                                        preferenceTerms: preferenceTerms
                                    )
                                )
                            )
                        }
                    case .unknown:
                        if let movie = await bestMovieMatch(for: tasteResult.name),
                           !existingMovieIDs.contains(movie.id) {
                            candidates.append(
                                HomeSuggestion(
                                    id: "movie-\(movie.id)",
                                    title: movie.title,
                                    subtitle: movie.year.map(String.init) ?? "Movie",
                                    posterURL: movie.posterURL,
                                    reason: "Taste graph match from \(seedTitle)",
                                    mediaType: .movie,
                                    score: blendedScore(
                                        title: movie.title,
                                        overview: movie.overview,
                                        voteAverage: movie.voteAverage,
                                        voteCount: movie.voteCount,
                                        sourceBoost: 1.25,
                                        preferenceTerms: preferenceTerms
                                    )
                                )
                            )
                        } else if let show = await bestTVMatch(for: tasteResult.name),
                                  !existingTVIDs.contains(show.id) {
                            candidates.append(
                                HomeSuggestion(
                                    id: "tv-\(show.id)",
                                    title: show.title,
                                    subtitle: show.year.map(String.init) ?? "TV Show",
                                    posterURL: show.posterURL,
                                    reason: "Taste graph match from \(seedTitle)",
                                    mediaType: .tv,
                                    score: blendedScore(
                                        title: show.title,
                                        overview: show.overview,
                                        voteAverage: show.voteAverage,
                                        voteCount: show.voteCount,
                                        sourceBoost: 1.25,
                                        preferenceTerms: preferenceTerms
                                    )
                                )
                            )
                        }
                    }
                }
            }
        }

        if candidates.count < 6 {
            let trending = (try? await TMDBService.shared.getTrendingAll(timeWindow: .week, page: 1)) ?? []
            for item in trending.prefix(15) {
                if item.mediaType == "movie", existingMovieIDs.contains(item.id) { continue }
                if item.mediaType == "tv", existingTVIDs.contains(item.id) { continue }
                if item.mediaType != "movie" && item.mediaType != "tv" { continue }

                candidates.append(
                    HomeSuggestion(
                        id: "\(item.mediaType)-\(item.id)",
                        title: item.resolvedTitle,
                        subtitle: item.year.map(String.init) ?? item.mediaType.uppercased(),
                        posterURL: item.posterURL,
                        reason: "Trending this week",
                        mediaType: item.mediaType == "movie" ? .movie : .tv,
                        score: blendedScore(
                            title: item.resolvedTitle,
                            overview: item.overview,
                            voteAverage: item.voteAverage,
                            voteCount: item.voteCount,
                            sourceBoost: 0.8,
                            preferenceTerms: preferenceTerms
                        )
                    )
                )
            }
        }

        var seen = Set<String>()
        homeSuggestions = candidates
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.score > $1.score }
            .prefix(10)
            .map { $0 }
    }

    private func buildPreferenceTerms() -> Set<String> {
        let watchedMovieTerms = movies
            .filter { $0.watchedDate != nil || ($0.rating ?? 0) >= 4.0 }
            .flatMap { $0.themes + $0.genres }
        let watchedTVTerms = tvShows
            .filter { $0.watchedDate != nil || ($0.rating ?? 0) >= 4.0 }
            .flatMap { $0.themes + $0.genres }
        return Set((watchedMovieTerms + watchedTVTerms).flatMap { normalizeTerm($0) })
    }

    private func normalizeTerm(_ raw: String) -> [String] {
        raw.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }
    }

    private func blendedScore(
        title: String,
        overview: String?,
        voteAverage: Double?,
        voteCount: Int?,
        sourceBoost: Double,
        preferenceTerms: Set<String>
    ) -> Double {
        let popularity = (voteAverage ?? 0) * 0.9 + log10(Double(max(voteCount ?? 1, 1)))
        let text = (title + " " + (overview ?? "")).lowercased()
        let matches = preferenceTerms.reduce(into: 0) { acc, term in
            if text.contains(term) { acc += 1 }
        }
        let personal = min(Double(matches) * 0.55, 3.5)
        return popularity + personal + sourceBoost
    }

    private func bestMovieMatch(for query: String) async -> TMDBMovie? {
        let results = (try? await TMDBService.shared.searchMovies(query: query, page: 1)) ?? []
        return results
            .filter { ($0.voteCount ?? 0) >= 80 || ($0.voteAverage ?? 0) >= 7.0 }
            .sorted { lhs, rhs in
                let l = (lhs.voteAverage ?? 0) * log10(Double(max(lhs.voteCount ?? 1, 1)))
                let r = (rhs.voteAverage ?? 0) * log10(Double(max(rhs.voteCount ?? 1, 1)))
                return l > r
            }
            .first
    }

    private func bestTVMatch(for query: String) async -> TMDBTVShow? {
        let results = (try? await TMDBService.shared.searchTVShows(query: query, page: 1)) ?? []
        return results
            .filter { ($0.voteCount ?? 0) >= 80 || ($0.voteAverage ?? 0) >= 7.0 }
            .sorted { lhs, rhs in
                let l = (lhs.voteAverage ?? 0) * log10(Double(max(lhs.voteCount ?? 1, 1)))
                let r = (rhs.voteAverage ?? 0) * log10(Double(max(rhs.voteCount ?? 1, 1)))
                return l > r
            }
            .first
    }

    private func parseTasteDiveMediaType(_ type: String?) -> HomeSuggestionMediaTypeHint {
        guard let type = type?.lowercased() else { return .unknown }
        if type.contains("movie") { return .movie }
        if type.contains("show") || type.contains("tv") { return .tv }
        return .unknown
    }
}

struct StatCard: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.title)
            
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MovieRow: View {
    let movie: Movie
    
    var body: some View {
        HStack(spacing: 12) {
            if let posterURL = movie.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Text("🎬")
                                .font(.largeTitle)
                        }
                }
                .frame(width: 60, height: 90)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
                    .overlay {
                        Text("🎬")
                            .font(.largeTitle)
                    }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let year = movie.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let rating = movie.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                        }
                        .foregroundStyle(.yellow)
                    }
                }
                
                if !movie.themes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(movie.themes.prefix(3), id: \.self) { theme in
                                Text(theme)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(12)
                            }
                            
                            if movie.themes.count > 3 {
                                Text("+\(movie.themes.count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Extracting themes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct TVShowRow: View {
    let show: TVShow
    
    var body: some View {
        HStack(spacing: 12) {
            if let posterURL = show.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Text("📺")
                                .font(.largeTitle)
                        }
                }
                .frame(width: 60, height: 90)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
                    .overlay {
                        Text("📺")
                            .font(.largeTitle)
                    }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(show.title)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let year = show.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let rating = show.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                        }
                        .foregroundStyle(.yellow)
                    }
                }
                
                if !show.themes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(show.themes.prefix(3), id: \.self) { theme in
                                Text(theme)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .cornerRadius(12)
                            }
                            
                            if show.themes.count > 3 {
                                Text("+\(show.themes.count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Extracting themes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

private enum HomeSuggestionMediaType {
    case movie
    case tv
}

private enum HomeSuggestionMediaTypeHint {
    case movie
    case tv
    case unknown
}

private struct HomeSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let posterURL: URL?
    let reason: String
    let mediaType: HomeSuggestionMediaType
    let score: Double
}

private struct HomeSuggestionCard: View {
    let suggestion: HomeSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: suggestion.posterURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(suggestion.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)

            Text(suggestion.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(suggestion.reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(suggestion.mediaType == .movie ? "Movie" : "TV")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((suggestion.mediaType == .movie ? Color.blue : Color.green).opacity(0.16))
                .foregroundStyle(suggestion.mediaType == .movie ? .blue : .green)
                .clipShape(Capsule())
        }
        .frame(width: 120, alignment: .leading)
        .padding(10)
        .background(Color(.systemGray6).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Movie.self, TVShow.self, Theme.self, ItemCollection.self], inMemory: true)
}
