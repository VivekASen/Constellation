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
            
            DiscoveryView()
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
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

    
    @State private var activeSheet: AddMediaSheet?
    
    var allThemes: [String] {
        let movieThemes = movies.flatMap(\.themes)
        let tvThemes = tvShows.flatMap(\.themes)
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
        }
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

#Preview {
    ContentView()
        .modelContainer(for: [Movie.self, TVShow.self, Theme.self, ItemCollection.self], inMemory: true)
}
