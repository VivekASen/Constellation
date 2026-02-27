//
//  MovieSearchView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//


import SwiftUI
import SwiftData

struct MovieSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [TMDBMovie] = []
    @State private var isSearching = false
    @State private var selectedMovie: TMDBMovie?
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search results
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "film",
                        description: Text("Try a different search term")
                    )
                } else if searchResults.isEmpty {
                    // Initial state
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text("Search for Movies")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Find and add movies to your constellation")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Results list
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { movie in
                                MovieSearchCard(movie: movie)
                                    .onTapGesture {
                                        selectedMovie = movie
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Add Movie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search TMDB")
            .onChange(of: searchText) { oldValue, newValue in
                Task {
                    await performSearch(query: newValue)
                }
            }
            .sheet(item: $selectedMovie) { movie in
                MovieDetailSheet(movie: movie)
            }
        }
    }
    
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        do {
            // Debounce search
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            guard query == searchText else { return } // User kept typing
            
            let results = try await TMDBService.shared.searchMovies(query: query)
            searchResults = results
        } catch {
            print("Search error: \(error)")
        }
        
        isSearching = false
    }
}

struct MovieSearchCard: View {
    let movie: TMDBMovie
    
    var body: some View {
        HStack(spacing: 12) {
            // Poster
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
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let year = movie.year {
                    Text(String("\(year)"))
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
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MovieDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let movie: TMDBMovie
    
    @State private var movieDetail: TMDBMovieDetail?
    @State private var isLoading = true
    @State private var watchedDate = Date()
    @State private var notes = ""
    @State private var rating: Double = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let detail = movieDetail {
                        // Poster
                        AsyncImage(url: detail.posterURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .aspectRatio(2/3, contentMode: .fit)
                        }
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(12)
                        
                        // Title & Year
                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.title)
                                .font(.title)
                                .fontWeight(.bold)
                            
                            HStack {
                                if let year = detail.year {
                                    Text(String("\(year)"))
                                        .foregroundStyle(.secondary)
                                }
                                
                                if let director = detail.director {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(director)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                            
                            if let rating = detail.voteAverage {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                    Text(String(format: "%.1f", rating))
                                }
                                .foregroundStyle(.yellow)
                            }
                        }
                        
                        // Genres
                        if !detail.genres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(detail.genres, id: \.id) { genre in
                                        Text(genre.name)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.blue.opacity(0.2))
                                            .foregroundStyle(.blue)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }
                        
                        // Overview
                        if let overview = detail.overview {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.headline)
                                
                                Text(overview)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Add to library form
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Add to Your Library")
                                .font(.headline)
                            
                            DatePicker("Watched Date", selection: $watchedDate, displayedComponents: .date)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your Rating")
                                    .font(.subheadline)
                                
                                HStack(spacing: 8) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                                            .foregroundStyle(.yellow)
                                            .onTapGesture {
                                                rating = Double(star)
                                            }
                                    }
                                }
                                .font(.title2)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes")
                                    .font(.subheadline)
                                
                                TextEditor(text: $notes)
                                    .frame(height: 100)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Add Movie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addMovie()
                    }
                    .disabled(movieDetail == nil)
                }
            }
            .task {
                await loadMovieDetails()
            }
        }
    }
    
    private func loadMovieDetails() async {
        do {
            let detail = try await TMDBService.shared.getMovieDetails(id: movie.id)
            movieDetail = detail
            isLoading = false
        } catch {
            print("Failed to load movie details: \(error)")
            isLoading = false
        }
    }
    
    private func addMovie() {
        guard let detail = movieDetail else { return }
        
        let newMovie = Movie(
            title: detail.title,
            year: detail.year,
            director: detail.director,
            posterURL: detail.posterURL?.absoluteString,
            overview: detail.overview,
            genres: detail.genres.map { $0.name },
            rating: rating > 0 ? rating : nil,
            watchedDate: watchedDate,
            notes: notes.isEmpty ? nil : notes,
            tmdbID: detail.id
        )
        
        modelContext.insert(newMovie)
        
        // Extract themes in background
        Task {
            let themes = await ThemeExtractor.shared.extractThemes(from: newMovie)
            newMovie.themes = themes
            try? modelContext.save()
        }
        
        dismiss()
    }
}

#Preview {
    MovieSearchView()
        .modelContainer(for: Movie.self, inMemory: true)
}
