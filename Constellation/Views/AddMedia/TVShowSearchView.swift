//
//  TVShowSearchView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI
import SwiftData
import UIKit

struct TVShowSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [TMDBTVShow] = []
    @State private var isSearching = false
    @State private var selectedShow: TMDBTVShow?
    @State private var searchTask: Task<Void, Never>?
    
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search TMDB TV")
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    await performSearch(query: newValue)
                }
            }
            .onDisappear {
                searchTask?.cancel()
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
            try await Task.sleep(nanoseconds: 350_000_000)
            guard query == searchText else { return }
            
            let results = try await TMDBService.shared.searchTVShows(query: query)
            searchResults = results
        } catch is CancellationError {
            return
        } catch {
            print("TV search error: \(error)")
        }
        
        isSearching = false
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
    @Query private var existingTVShows: [TVShow]
    
    let show: TMDBTVShow
         
    @State private var showDetail: TMDBTVShowDetail?
    @State private var isLoading = true
    @State private var trailer: TMDBVideo?
    @State private var watchProviders: [TMDBWatchProvider] = []
    @State private var similarShows: [TMDBTVShow] = []
    @State private var addStatus: AddStatus = .watchlist
    @State private var watchedDate = Date()
    @State private var notes = ""
    @State private var rating: Double = 0
    @State private var showDuplicateAlert = false
    @State private var duplicateMessage = "This TV show is already in your library."

    enum AddStatus: String, CaseIterable, Identifiable {
        case watchlist
        case watched
        var id: String { rawValue }
    }

    init(show: TMDBTVShow) {
        self.show = show
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
                        if let trailer, let url = trailer.youtubeURL {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Trailer")
                                    .font(.headline)
                                Link(destination: url) {
                                    Label(trailer.name, systemImage: "play.rectangle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.red.opacity(0.14))
                                        .foregroundStyle(.red)
                                        .clipShape(Capsule())
                                }
                            }
                        }

                        if !watchProviders.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Where to Watch (US)")
                                    .font(.headline)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(watchProviders.prefix(10)) { provider in
                                            HStack(spacing: 6) {
                                                if let logo = provider.logoURL {
                                                    AsyncImage(url: logo) { image in
                                                        image.resizable().scaledToFit()
                                                    } placeholder: {
                                                        Color.gray.opacity(0.2)
                                                    }
                                                    .frame(width: 16, height: 16)
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                }
                                                Text(provider.providerName)
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.green.opacity(0.14))
                                            .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        if !similarShows.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Similar Picks")
                                    .font(.headline)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(similarShows.prefix(8)) { similar in
                                            VStack(alignment: .leading, spacing: 4) {
                                                AsyncImage(url: similar.posterURL) { image in
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } placeholder: {
                                                    Rectangle().fill(Color.gray.opacity(0.25))
                                                }
                                                .frame(width: 95, height: 140)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                Text(similar.name)
                                                    .font(.caption.weight(.semibold))
                                                    .lineLimit(2)
                                                    .frame(width: 95, alignment: .leading)
                                            }
                                        }
                                    }
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
            .alert("Already Added", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(duplicateMessage)
            }
        }
    }
    
    private func loadTVShowDetails() async {
        do {
            let detail = try await TMDBService.shared.getTVShowDetails(id: show.id)
            showDetail = detail
            async let videosTask = TMDBService.shared.getTVVideos(tvID: show.id)
            async let providersTask = TMDBService.shared.getTVWatchProviders(tvID: show.id)
            async let similarTask = TMDBService.shared.getTVRecommendations(tvID: show.id)

            if let videos = try? await videosTask {
                trailer = videos.first(where: { video in
                    video.site.lowercased() == "youtube" && (video.type == "Trailer" || video.official == true)
                }) ?? videos.first(where: { $0.site.lowercased() == "youtube" })
            }
            watchProviders = (try? await providersTask) ?? []
            similarShows = (try? await similarTask)?
                .filter { $0.voteCount ?? 0 >= 80 }
                .sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) } ?? []
            isLoading = false
        } catch {
            print("Failed to load TV show details: \(error)")
            isLoading = false
        }
    }
    
    private func addTVShow() {
        guard let detail = showDetail else { return }
        let normalizedTitle = detail.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let duplicateExists = existingTVShows.contains { existing in
            if existing.tmdbID == detail.id { return true }
            let existingTitle = existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let yearMatches = (existing.year == nil || detail.year == nil || existing.year == detail.year)
            return existingTitle == normalizedTitle && yearMatches
        }
        if duplicateExists {
            duplicateMessage = "\"\(detail.title)\" is already in your library."
            showDuplicateAlert = true
            return
        }
        
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
            publicRating: detail.voteAverage ?? show.voteAverage,
            publicRatingCount: detail.voteCount ?? show.voteCount,
            rating: isWatched && rating > 0 ? rating : nil,
            watchedDate: isWatched ? watchedDate : nil,
            notes: notes.isEmpty ? nil : notes,
            tmdbID: detail.id
        )
        
        modelContext.insert(newShow)
        try? modelContext.save()
        
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

#Preview {
    TVShowSearchView()
        .modelContainer(for: TVShow.self, inMemory: true)
}
