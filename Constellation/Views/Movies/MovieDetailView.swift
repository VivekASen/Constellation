//
//  MovieDetailView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//


import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @Environment(\.openURL) private var openURL

    @State private var trailer: TMDBVideo?
    @State private var watchProviders: [TMDBWatchProvider] = []
    @State private var similarMovies: [TMDBMovie] = []
    @State private var isLoadingExtras = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Poster
                if let posterURL = movie.posterURL, let url = URL(string: posterURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(height: 400)
                    .frame(maxWidth: .infinity)
                    .cornerRadius(12)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Title & Year
                    VStack(alignment: .leading, spacing: 4) {
                        Text(movie.title)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack {
                            if let year = movie.year {
                                Text(String(year))
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let director = movie.director {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(director)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                    
                    // Rating
                    if let rating = movie.rating {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .font(.title3)
                    }
                    
                    // Genres
                    if !movie.genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(movie.genres, id: \.self) { genre in
                                    Text(genre)
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
                    if let overview = movie.overview {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Overview")
                                .font(.headline)
                            
                            Text(overview)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isLoadingExtras {
                        ProgressView("Loading trailers and streaming info…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let trailer, let url = trailer.youtubeURL {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Trailer")
                                .font(.headline)
                            Button {
                                openURL(url)
                            } label: {
                                Label(trailer.name, systemImage: "play.rectangle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.14))
                                    .foregroundStyle(.red)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !watchProviders.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
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
                                                .frame(width: 18, height: 18)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                            }
                                            Text(provider.providerName)
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    if !similarMovies.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Similar Picks")
                                .font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(similarMovies.prefix(8)) { similar in
                                        VStack(alignment: .leading, spacing: 4) {
                                            AsyncImage(url: similar.posterURL) { image in
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Rectangle().fill(Color.gray.opacity(0.25))
                                            }
                                            .frame(width: 110, height: 165)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            Text(similar.title)
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(2)
                                                .frame(width: 110, alignment: .leading)
                                            if let year = similar.year {
                                                Text(String(year))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Themes
                    if !movie.themes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Themes")
                                .font(.headline)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(movie.themes, id: \.self) { theme in
                                    NavigationLink(destination: ThemeDetailView(themeName: theme)) {
                                        Text(theme)
                                            .font(.subheadline)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color.purple.opacity(0.2))
                                            .foregroundStyle(.purple)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Notes
                    if let notes = movie.notes {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("My Notes")
                                .font(.headline)
                            
                            Text(notes)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: movie.id) {
            await loadEnhancements()
        }
    }

    private func loadEnhancements() async {
        guard let tmdbID = movie.tmdbID else { return }
        isLoadingExtras = true
        defer { isLoadingExtras = false }

        async let videosTask = TMDBService.shared.getMovieVideos(movieID: tmdbID)
        async let providersTask = TMDBService.shared.getMovieWatchProviders(movieID: tmdbID)
        async let similarTask = TMDBService.shared.getSimilarMovies(movieID: tmdbID)

        do {
            let videos = try await videosTask
            trailer = videos.first(where: { video in
                video.site.lowercased() == "youtube" && (video.type == "Trailer" || video.official == true)
            }) ?? videos.first(where: { $0.site.lowercased() == "youtube" })
        } catch {
            trailer = nil
        }

        do {
            watchProviders = try await providersTask
        } catch {
            watchProviders = []
        }

        do {
            similarMovies = try await similarTask
                .filter { $0.voteCount ?? 0 >= 120 }
                .sorted { lhs, rhs in
                    let l = (lhs.voteAverage ?? 0) * log10(Double(max(lhs.voteCount ?? 1, 1)))
                    let r = (rhs.voteAverage ?? 0) * log10(Double(max(rhs.voteCount ?? 1, 1)))
                    return l > r
                }
        } catch {
            similarMovies = []
        }
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize
        var positions: [CGPoint]
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var positions: [CGPoint] = []
            var size: CGSize = .zero
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let subviewSize = subview.sizeThatFits(.unspecified)
                
                if currentX + subviewSize.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += subviewSize.width + spacing
                lineHeight = max(lineHeight, subviewSize.height)
                size.width = max(size.width, currentX - spacing)
                size.height = currentY + lineHeight
            }
            
            self.size = size
            self.positions = positions
        }
    }
}
