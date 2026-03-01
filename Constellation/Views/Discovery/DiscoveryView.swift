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
    @State private var progressiveContext = ProgressiveDiscoveryContext()
    
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
                                progressiveContext = ProgressiveDiscoveryContext()
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
                    
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ProgressiveDiscoveryChatView(
                            context: $progressiveContext,
                            onAnswer: {
                                Task { await performDiscovery() }
                            }
                        )
                        .padding(.horizontal)
                    }
                    
                    if searchText.isEmpty && discoveryResult == nil {
                        QuickSuggestionsView(onSelect: { suggestion in
                            searchText = suggestion
                            progressiveContext = ProgressiveDiscoveryContext()
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
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSearching = true
        discoveryResult = nil
        
        let result = await DiscoveryEngine.shared.discover(
            interest: effectiveSearchQuery,
            userMovies: movies,
            userTVShows: tvShows
        )
        
        discoveryResult = result
        isSearching = false
    }
    
    private var effectiveSearchQuery: String {
        var parts: [String] = [searchText]
        
        if let fiction = progressiveContext.fictionPreference {
            parts.append("Content preference: \(fiction).")
            switch fiction {
            case "Fiction":
                parts.append("narrative, fictional stories")
            case "Non-Fiction":
                parts.append("documentary, true story, real events")
            default:
                break
            }
        }
        
        if let format = progressiveContext.formatPreference {
            parts.append("Preferred format: \(format).")
        }
        
        if let pacing = progressiveContext.pacingPreference {
            parts.append("Preferred pacing: \(pacing).")
        }
        
        return parts.joined(separator: " ")
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

struct ProgressiveDiscoveryContext {
    var fictionPreference: String?
    var formatPreference: String?
    var pacingPreference: String?
}

private struct ProgressiveDiscoveryChatView: View {
    @Binding var context: ProgressiveDiscoveryContext
    let onAnswer: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guided Discover")
                .font(.subheadline.weight(.semibold))
            
            assistantBubble("Quickly refine your search so recommendations are more precise.")
            
            QnABlock(
                prompt: "Are you looking for fiction or non-fiction?",
                answer: context.fictionPreference,
                options: ["Fiction", "Non-Fiction", "Mixed"]
            ) { selection in
                context.fictionPreference = selection
                onAnswer()
            }
            
            if context.fictionPreference != nil {
                QnABlock(
                    prompt: "What format do you want right now?",
                    answer: context.formatPreference,
                    options: ["Movies", "TV Shows", "Either"]
                ) { selection in
                    context.formatPreference = selection
                    onAnswer()
                }
            }
            
            if context.formatPreference != nil {
                QnABlock(
                    prompt: "What pacing are you in the mood for?",
                    answer: context.pacingPreference,
                    options: ["Fast-paced", "Thoughtful", "Balanced"]
                ) { selection in
                    context.pacingPreference = selection
                    onAnswer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func assistantBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct QnABlock: View {
    let prompt: String
    let answer: String?
    let options: [String]
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text(prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let answer {
                HStack {
                    Spacer()
                    Text(answer)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.16))
                        .foregroundStyle(.blue)
                        .cornerRadius(12)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            Button(option) {
                                onSelect(option)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(14)
                        }
                    }
                }
            }
        }
    }
}

struct SmartDiscoveryResultsView: View {
    let result: DiscoveryResult
    let onAddMovie: (TMDBMovie) -> Void
    
    @State private var selectedAnswers: [String: String] = [:]
    
    private var selectedFormat: String {
        selectedAnswers["What format are you in the mood for?"] ?? "Any"
    }
    
    private var selectedVibe: String? {
        selectedAnswers["What vibe are you looking for?"]
    }
    
    private var filteredMovies: [Movie] {
        var items = result.inLibraryMovies
        
        if selectedFormat == "TV Shows" {
            items = []
        }
        
        if let vibe = selectedVibe {
            items = items.filter { matchesVibe(movie: $0, vibe: vibe) }
        }
        
        return items
    }
    
    private var filteredTVShows: [TVShow] {
        var items = result.inLibraryTVShows
        
        if selectedFormat == "Movies" {
            items = []
        }
        
        if let vibe = selectedVibe {
            items = items.filter { matchesVibe(show: $0, vibe: vibe) }
        }
        
        return items
    }
    
    private var filteredRecommendations: [TMDBMovie] {
        var items = result.recommendations
        
        if selectedFormat == "TV Shows" {
            items = []
        }
        
        if let vibe = selectedVibe {
            items = items.filter { matchesVibe(recommendation: $0, vibe: vibe) }
        }
        
        return items
    }
    
    private var filteredTVRecommendations: [TMDBTVShow] {
        var items = result.tvRecommendations
        
        if selectedFormat == "Movies" {
            items = []
        }
        
        if let vibe = selectedVibe {
            items = items.filter { matchesVibe(recommendation: $0, vibe: vibe) }
        }
        
        return items
    }
    
    private var filteredConnections: [Connection] {
        let validTitles = Set(filteredMovies.map(\.title) + filteredTVShows.map(\.title))
        return result.connections.filter { validTitles.contains($0.from) && validTitles.contains($0.to) }
    }
    
    var totalLibraryMatches: Int {
        filteredMovies.count + filteredTVShows.count
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
                                        let isSelected = selectedAnswers[question.text] == option
                                        
                                        Button(action: {
                                            selectedAnswers[question.text] = option
                                        }) {
                                            Text(option)
                                                .font(.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(isSelected ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                                                .foregroundStyle(isSelected ? .blue : .blue)
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
                    
                    if !filteredConnections.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("💡 Connections I found:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal)
                            
                            ForEach(filteredConnections.prefix(3), id: \.reason) { connection in
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
                    
                    if !filteredMovies.isEmpty {
                        Text("Movies")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(filteredMovies) { movie in
                            NavigationLink(destination: MovieDetailView(movie: movie)) {
                                LibraryMovieCard(movie: movie)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if !filteredTVShows.isEmpty {
                        Text("TV Shows")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(filteredTVShows) { show in
                            NavigationLink(destination: TVShowDetailView(show: show)) {
                                LibraryTVShowCard(show: show)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            if !filteredRecommendations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You Might Like (Movies)")
                            .font(.title3)
                            .fontWeight(.semibold)
                            
                            Text("Popular movies in this theme")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(filteredRecommendations.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ForEach(filteredRecommendations) { movie in
                        RecommendationMovieCard(
                            movie: movie,
                            reason: result.movieRecommendationReasons[movie.id]
                        )
                            .onTapGesture {
                                onAddMovie(movie)
                            }
                    }
                }
            }
            
            if !filteredTVRecommendations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You Might Like (TV)")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Text("Popular TV shows in this theme")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(filteredTVRecommendations.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    ForEach(filteredTVRecommendations) { show in
                        RecommendationTVShowCard(
                            show: show,
                            reason: result.tvRecommendationReasons[show.id]
                        )
                    }
                }
            }
            
            if !hasFilteredResults {
                ContentUnavailableView(
                    "No Matches Yet",
                    systemImage: "magnifyingglass",
                    description: Text("Try another answer above or adjust your search.")
                )
                .padding(.top, 60)
            }
        }
    }
    
    private var hasFilteredResults: Bool {
        !filteredMovies.isEmpty || !filteredTVShows.isEmpty || !filteredRecommendations.isEmpty || !filteredTVRecommendations.isEmpty
    }
    
    private func matchesVibe(movie: Movie, vibe: String) -> Bool {
        let haystack = (movie.genres + movie.themes + [movie.title, movie.overview ?? ""]).joined(separator: " ").lowercased()
        return matchesVibe(haystack: haystack, vibe: vibe)
    }
    
    private func matchesVibe(show: TVShow, vibe: String) -> Bool {
        let haystack = (show.genres + show.themes + [show.title, show.overview ?? ""]).joined(separator: " ").lowercased()
        return matchesVibe(haystack: haystack, vibe: vibe)
    }
    
    private func matchesVibe(recommendation: TMDBMovie, vibe: String) -> Bool {
        let haystack = [recommendation.title, recommendation.overview ?? ""].joined(separator: " ").lowercased()
        return matchesVibe(haystack: haystack, vibe: vibe)
    }
    
    private func matchesVibe(recommendation: TMDBTVShow, vibe: String) -> Bool {
        let haystack = [recommendation.title, recommendation.overview ?? ""].joined(separator: " ").lowercased()
        return matchesVibe(haystack: haystack, vibe: vibe)
    }
    
    private func matchesVibe(haystack: String, vibe: String) -> Bool {
        let keywords: [String]
        
        switch vibe {
        case "Action-packed":
            keywords = ["action", "thriller", "war", "adventure", "crime", "survival"]
        case "Thoughtful":
            keywords = ["drama", "philosophy", "social", "identity", "political", "moral"]
        case "Fun & light":
            keywords = ["comedy", "feel-good", "adventure", "friendship", "family"]
        case "Dark & serious":
            keywords = ["dark", "crime", "psychological", "war", "revenge", "dystopia"]
        default:
            return true
        }
        
        return keywords.contains { haystack.contains($0) }
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
    let reason: String?
    
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
                
                if let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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

struct RecommendationTVShowCard: View {
    let show: TMDBTVShow
    let reason: String?
    
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
            
            VStack(alignment: .leading, spacing: 6) {
                Text(show.title)
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
                
                if let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Image(systemName: "tv")
                .font(.title3)
                .foregroundStyle(.indigo)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
