//
//  DiscoveryView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI
import SwiftData

struct DiscoveryView: View {
    @Query private var movies: [Movie]
    @Query private var tvShows: [TVShow]
    
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var discoveryResult: DiscoveryResult?
    @State private var showingAddMovie: TMDBMovie?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Discover")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Tell me what you're interested in")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                        
                        TextField("space exploration, murder mysteries, coming of age...", text: $searchText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2)
                            .submitLabel(.search)
                            .onSubmit {
                                Task { await performDiscovery() }
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                discoveryResult = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    if searchText.isEmpty && discoveryResult == nil {
                        QuickSuggestionsView(onSelect: { suggestion in
                            searchText = suggestion
                            Task { await performDiscovery() }
                        })
                    }
                    
                    if isSearching {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Finding connections...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.top, 60)
                    }
                    
                    if let result = discoveryResult {
                        SmartDiscoveryResultsView(
                            result: result,
                            onAddMovie: { movie in
                                showingAddMovie = movie
                            }
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $showingAddMovie) { movie in
                MovieDetailSheet(movie: movie)
            }
        }
    }
    
    private func performDiscovery() async {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        discoveryResult = nil
        
        let result = await DiscoveryEngine.shared.discover(
            interest: searchText,
            userMovies: movies,
            userTVShows: tvShows
        )
        
        discoveryResult = result
        isSearching = false
    }
}

struct QuickSuggestionsView: View {
    let onSelect: (String) -> Void
    
    let categories = [
        ("🚀", "space exploration", Color.blue),
        ("🔍", "murder mysteries", Color.purple),
        ("🧑‍🎓", "coming of age", Color.green),
        ("⏰", "time travel", Color.orange),
        ("🏰", "fantasy adventures", Color.pink),
        ("🤖", "artificial intelligence", Color.cyan),
        ("💔", "romantic dramas", Color.red),
        ("🎭", "psychological thrillers", Color.indigo)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Popular Themes")
                .font(.headline)
                .padding(.horizontal)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(categories, id: \.1) { emoji, text, color in
                    Button(action: { onSelect(text) }) {
                        HStack {
                            Text(emoji)
                                .font(.title2)
                            Text(text)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(color.opacity(0.15))
                        .foregroundStyle(color)
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct SmartDiscoveryResultsView: View {
    let result: DiscoveryResult
    let onAddMovie: (TMDBMovie) -> Void
    
    var totalLibraryMatches: Int {
        result.inLibraryMovies.count + result.inLibraryTVShows.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "brain")
                        .foregroundStyle(.purple)
                    Text("I found content about:")
                        .font(.headline)
                }
                
                Text(result.understanding.mood.isEmpty ?
                     result.understanding.themes.joined(separator: ", ") :
                     result.understanding.mood)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
            .padding(.horizontal)
            
            if !result.followUpQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(result.followUpQuestions, id: \.text) { question in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(question.text)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(question.options, id: \.self) { option in
                                        Button(action: {
                                            print("User selected: \(option) for question: \(question.text)")
                                        }) {
                                            Text(option)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.blue.opacity(0.1))
                                                .foregroundStyle(.blue)
                                                .cornerRadius(16)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            if totalLibraryMatches > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("In Your Library")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("\(totalLibraryMatches)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    if !result.connections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("💡 Connections I found:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal)
                            
                            ForEach(result.connections.prefix(3), id: \.reason) { connection in
                                Text("• \(connection.from) & \(connection.to): \(connection.reason)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    if !result.inLibraryMovies.isEmpty {
                        Text("Movies")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(result.inLibraryMovies) { movie in
                            NavigationLink(destination: MovieDetailView(movie: movie)) {
                                LibraryMovieCard(movie: movie)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if !result.inLibraryTVShows.isEmpty {
                        Text("TV Shows")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(result.inLibraryTVShows) { show in
                            NavigationLink(destination: TVShowDetailView(show: show)) {
                                LibraryTVShowCard(show: show)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            if !result.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You Might Like")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Text("Popular movies in this theme")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(result.recommendations.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ForEach(result.recommendations) { movie in
                        RecommendationMovieCard(movie: movie)
                            .onTapGesture {
                                onAddMovie(movie)
                            }
                    }
                }
            }
            
            if !result.hasResults {
                ContentUnavailableView(
                    "No Matches Yet",
                    systemImage: "magnifyingglass",
                    description: Text("Try searching for something else or add more media to find connections")
                )
                .padding(.top, 60)
            }
        }
    }
}

struct LibraryMovieCard: View {
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
                }
                .frame(width: 60, height: 90)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
                    .overlay { Text("🎬") }
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
                    Text(movie.themes.prefix(2).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct LibraryTVShowCard: View {
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
                }
                .frame(width: 60, height: 90)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
                    .overlay { Text("📺") }
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
                    Text(show.themes.prefix(2).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct RecommendationMovieCard: View {
    let movie: TMDBMovie
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: movie.posterURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 60, height: 90)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let year = movie.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let rating = movie.voteAverage {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                        Text(String(format: "%.1f", rating))
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow)
                }
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                Text("Add")
                    .font(.caption2)
            }
            .foregroundStyle(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
