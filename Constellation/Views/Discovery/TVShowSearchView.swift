//
//  TVShowSearchView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI
import SwiftData

struct TVShowSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [TMDBTVShow] = []
    @State private var isSearching = false
    @State private var selectedShow: TMDBTVShow?
    
    var body: some View {
        NavigationStack {
            VStack {
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "tv",
                        description: Text("Try a different search term")
                    )
                } else if searchResults.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text("Search for TV Shows")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Find and add shows to your constellation")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { show in
                                TVShowSearchCard(show: show)
                                    .onTapGesture {
                                        selectedShow = show
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Add TV Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "Search TMDB TV")
            .onChange(of: searchText) { _, newValue in
                Task {
                    await performSearch(query: newValue)
                }
            }
            .sheet(item: $selectedShow) { show in
                TVShowDetailSheet(show: show)
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
            try await Task.sleep(nanoseconds: 500_000_000)
            guard query == searchText else { return }
            
            let results = try await TMDBService.shared.searchTVShows(query: query)
            searchResults = results
        } catch {
            print("TV search error: \(error)")
        }
        
        isSearching = false
    }
}

struct TVShowSearchCard: View {
    let show: TMDBTVShow
    
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: show.posterURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay {
                        Image(systemName: "tv")
                            .foregroundStyle(.secondary)
                    }
            }
            .frame(width: 60, height: 90)
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(show.name)
                    .font(.headline)
                    .lineLimit(2)
                
                if let year = show.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let rating = show.voteAverage {
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

struct TVShowDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let show: TMDBTVShow
    let recommendationContext: TVRecommendationContext?
    
    @State private var showDetail: TMDBTVShowDetail?
    @State private var isLoading = true
    @State private var addStatus: AddStatus = .watchlist
    @State private var watchedDate = Date()
    @State private var notes = ""
    @State private var rating: Double = 0

    enum AddStatus: String, CaseIterable, Identifiable {
        case watchlist
        case watched
        var id: String { rawValue }
    }

    init(show: TMDBTVShow, recommendationContext: TVRecommendationContext? = nil) {
        self.show = show
        self.recommendationContext = recommendationContext
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let detail = showDetail {
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
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(detail.title)
                                .font(.title)
                                .fontWeight(.bold)
                            
                            HStack {
                                if let year = detail.year {
                                    Text(String(year))
                                        .foregroundStyle(.secondary)
                                }
                                
                                if let creator = detail.creator {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text(creator)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                            
                            HStack(spacing: 10) {
                                if let seasons = detail.numberOfSeasons {
                                    Text("\(seasons) season\(seasons == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let episodes = detail.numberOfEpisodes {
                                    Text("\(episodes) episodes")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            if let rating = detail.voteAverage {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                    Text(String(format: "%.1f", rating))
                                }
                                .foregroundStyle(.yellow)
                            }
                        }
                        
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
                        
                        if let overview = detail.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.headline)
                                
                                Text(overview)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let context = recommendationContext {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Why This Was Recommended")
                                    .font(.headline)
                                Text(context.reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    scorePill("Semantic", value: context.semanticScore)
                                    scorePill("Coherence", value: context.coherenceScore)
                                    scorePill("Overall", value: context.blendedScore)
                                }
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Add to Your Library")
                                .font(.headline)
                            Picker("Status", selection: $addStatus) {
                                Text("Watchlist").tag(AddStatus.watchlist)
                                Text("Watched").tag(AddStatus.watched)
                            }
                            .pickerStyle(.segmented)

                            if addStatus == .watched {
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
            .navigationTitle("TV Show Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addStatus == .watchlist ? "Add to Watchlist" : "Add as Watched") {
                        addTVShow()
                    }
                    .disabled(showDetail == nil)
                }
            }
            .task {
                await loadTVShowDetails()
            }
        }
    }
    
    private func loadTVShowDetails() async {
        do {
            let detail = try await TMDBService.shared.getTVShowDetails(id: show.id)
            showDetail = detail
            isLoading = false
        } catch {
            print("Failed to load TV show details: \(error)")
            isLoading = false
        }
    }
    
    private func addTVShow() {
        guard let detail = showDetail else { return }
        
        let isWatched = addStatus == .watched
        let newShow = TVShow(
            title: detail.title,
            year: detail.year,
            creator: detail.creator,
            posterURL: detail.posterURL?.absoluteString,
            overview: detail.overview,
            genres: detail.genres.map { $0.name },
            seasonCount: detail.numberOfSeasons,
            episodeCount: detail.numberOfEpisodes,
            rating: isWatched && rating > 0 ? rating : nil,
            watchedDate: isWatched ? watchedDate : nil,
            notes: notes.isEmpty ? nil : notes,
            tmdbID: detail.id
        )
        
        modelContext.insert(newShow)
        
        Task {
            let themes = await ThemeExtractor.shared.extractThemes(from: newShow)
            newShow.themes = themes
            try? modelContext.save()
        }
        
        dismiss()
    }

    @ViewBuilder
    private func scorePill(_ title: String, value: Double) -> some View {
        Text("\(title) \(String(format: "%.2f", value))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

struct TVRecommendationContext {
    let reason: String
    let semanticScore: Double
    let coherenceScore: Double
    let blendedScore: Double
}

#Preview {
    TVShowSearchView()
        .modelContainer(for: TVShow.self, inMemory: true)
}
