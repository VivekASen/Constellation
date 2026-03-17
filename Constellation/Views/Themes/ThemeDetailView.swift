//
//  ThemeDetailView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI
import SwiftData

struct ThemeDetailView: View {
    @Query private var allMovies: [Movie]
    @Query private var allTVShows: [TVShow]
    @Query private var allBooks: [Book]
    @Query private var allPodcasts: [PodcastEpisode]
    @Query private var allCollections: [ItemCollection]

    @State private var themeExplanation: ThemeExplanation?
    @State private var isLoadingExplanation = false
    @State private var isDeepDiveExpanded = false

    let themeName: String

    private var normalizedThemeName: String {
        ThemeExtractor.shared.normalizeThemes([themeName]).first ?? themeName
    }

    private var displayThemeName: String {
        normalizedThemeName
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private var contextTitles: [String] {
        let movieTitles = moviesWithTheme.map(\.title)
        let showTitles = showsWithTheme.map(\.title)
        let bookTitles = booksWithTheme.map(\.title)
        let podcastTitles = podcastsWithTheme.map(\.title)
        return Array((movieTitles + showTitles + bookTitles + podcastTitles).prefix(8))
    }
    
    var moviesWithTheme: [Movie] {
        allMovies.filter { movie in
            ThemeExtractor.shared.normalizeThemes(movie.themes).contains(normalizedThemeName)
        }
    }
    
    var showsWithTheme: [TVShow] {
        allTVShows.filter { show in
            ThemeExtractor.shared.normalizeThemes(show.themes).contains(normalizedThemeName)
        }
    }
    
    var totalCount: Int {
        moviesWithTheme.count + showsWithTheme.count + booksWithTheme.count + podcastsWithTheme.count
    }

    var booksWithTheme: [Book] {
        allBooks.filter { book in
            ThemeExtractor.shared.normalizeThemes(book.themes).contains(normalizedThemeName)
        }
    }

    var podcastsWithTheme: [PodcastEpisode] {
        allPodcasts.filter { episode in
            ThemeExtractor.shared.normalizeThemes(episode.themes).contains(normalizedThemeName)
        }
    }

    var collectionsWithTheme: [ItemCollection] {
        let movieIDs = Set(moviesWithTheme.map { $0.id.uuidString })
        let showIDs = Set(showsWithTheme.map { $0.id.uuidString })
        let bookIDs = Set(booksWithTheme.map { $0.id.uuidString })
        let podcastIDs = Set(podcastsWithTheme.map { $0.id.uuidString })
        return allCollections.filter { collection in
            !Set(collection.movieIDs).isDisjoint(with: movieIDs)
            || !Set(collection.showIDs).isDisjoint(with: showIDs)
            || !Set(collection.bookIDs).isDisjoint(with: bookIDs)
            || !Set(collection.podcastIDs).isDisjoint(with: podcastIDs)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayThemeName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("\(totalCount) items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    DisclosureGroup(isExpanded: $isDeepDiveExpanded) {
                        if isLoadingExplanation && themeExplanation == nil {
                            ProgressView("Building insight...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if let explanation = themeExplanation {
                            Text(composeDeepSummary(from: explanation))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        } else {
                            Text(ThemeDefinitionService.shared.definition(for: normalizedThemeName))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text("Theme Deep Dive")
                            .font(.headline)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                
                if totalCount == 0 {
                    ContentUnavailableView(
                        "No Items Yet",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text("Add media with this theme to see it here")
                    )
                } else {
                    if !moviesWithTheme.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Movies")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(moviesWithTheme) { movie in
                                NavigationLink(destination: MovieDetailView(movie: movie)) {
                                    ThemeMovieCard(movie: movie)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    if !showsWithTheme.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TV Shows")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(showsWithTheme) { show in
                                NavigationLink(destination: TVShowDetailView(show: show)) {
                                    ThemeTVShowCard(show: show)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !booksWithTheme.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Books")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(booksWithTheme) { book in
                                NavigationLink(destination: BookDetailView(book: book)) {
                                    ThemeBookCard(book: book)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !podcastsWithTheme.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Podcasts")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(podcastsWithTheme) { episode in
                                NavigationLink(destination: PodcastEpisodeDetailView(episode: episode)) {
                                    HStack(spacing: 12) {
                                        if let artwork = episode.thumbnailURL, let url = URL(string: artwork) {
                                            AsyncImage(url: url) { image in
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle().fill(Color.gray.opacity(0.3))
                                            }
                                            .frame(width: 64, height: 64)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(episode.title)
                                                .font(.headline)
                                                .lineLimit(2)
                                            Text(episode.showName)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !collectionsWithTheme.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Collections")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(collectionsWithTheme) { collection in
                                NavigationLink(destination: CollectionDetailView(collection: collection)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(collection.name)
                                                .font(.headline)
                                            Text("\(collection.movieIDs.count + collection.showIDs.count + collection.bookIDs.count) items")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: normalizedThemeName) {
            await loadThemeExplanation()
        }
    }

    private func composeDeepSummary(from explanation: ThemeExplanation) -> String {
        let variant = abs(normalizedThemeName.hashValue) % 3
        switch variant {
        case 0:
            return "\(explanation.summary) \(explanation.deepDive) \(explanation.connectionHint) \(explanation.watchFor)"
        case 1:
            return "\(explanation.deepDive) \(explanation.summary) \(explanation.watchFor) \(explanation.connectionHint)"
        default:
            return "\(explanation.summary) \(explanation.connectionHint) \(explanation.deepDive) \(explanation.watchFor)"
        }
    }

    private func loadThemeExplanation() async {
        isLoadingExplanation = true
        let explanation = await ThemeDefinitionService.shared.explanation(
            for: normalizedThemeName,
            contextTitles: contextTitles
        )
        themeExplanation = explanation
        isLoadingExplanation = false
    }
}

struct ThemeMovieCard: View {
    let movie: Movie
    
    var body: some View {
        HStack(spacing: 12) {
            if let posterURL = movie.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 80, height: 120)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 120)
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
                
                if let year = movie.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let director = movie.director {
                    Text(director)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if let rating = movie.publicRating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                        Text(String(format: "%.1f", rating))
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct ThemeTVShowCard: View {
    let show: TVShow
    
    var body: some View {
        HStack(spacing: 12) {
            if let posterURL = show.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 80, height: 120)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 120)
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
                
                if let year = show.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let creator = show.creator {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if let rating = show.publicRating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                        Text(String(format: "%.1f", rating))
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct ThemeBookCard: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            if let coverURL = book.coverURL, let url = URL(string: coverURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 80, height: 120)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 120)
                    .cornerRadius(8)
                    .overlay {
                        Text("📚")
                            .font(.largeTitle)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)

                if let year = book.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let rating = book.rating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                        Text(String(format: "%.1f", rating))
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
