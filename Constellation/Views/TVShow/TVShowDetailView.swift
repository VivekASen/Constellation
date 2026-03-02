//
//  TVShowDetailView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI

struct TVShowDetailView: View {
    let show: TVShow
    @Environment(\.openURL) private var openURL

    @State private var trailer: TMDBVideo?
    @State private var watchProviders: [TMDBWatchProvider] = []
    @State private var similarShows: [TMDBTVShow] = []
    @State private var isLoadingExtras = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let posterURL = show.posterURL, let url = URL(string: posterURL) {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(show.title)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        HStack {
                            if let year = show.year {
                                Text(String(year))
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let creator = show.creator {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(creator)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        
                        HStack(spacing: 10) {
                            if let seasons = show.seasonCount {
                                Text("\(seasons) season\(seasons == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let episodes = show.episodeCount {
                                Text("\(episodes) episodes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if let rating = show.rating {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= Int(rating) ? "star.fill" : "star")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .font(.title3)
                    }
                    
                    if !show.genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(show.genres, id: \.self) { genre in
                                    Text(genre)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .cornerRadius(20)
                                }
                            }
                        }
                    }
                    
                    if let overview = show.overview {
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
                                        .background(Color.green.opacity(0.14))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    if !similarShows.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
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
                                            .frame(width: 110, height: 165)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            Text(similar.name)
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
                    
                    if !show.themes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Themes")
                                .font(.headline)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(show.themes, id: \.self) { theme in
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
                    
                    if let notes = show.notes {
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
        .task(id: show.id) {
            await loadEnhancements()
        }
    }

    private func loadEnhancements() async {
        guard let tmdbID = show.tmdbID else { return }
        isLoadingExtras = true
        defer { isLoadingExtras = false }

        async let videosTask = TMDBService.shared.getTVVideos(tvID: tmdbID)
        async let providersTask = TMDBService.shared.getTVWatchProviders(tvID: tmdbID)
        async let similarTask = TMDBService.shared.getSimilarTVShows(tvID: tmdbID)

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
            similarShows = try await similarTask
                .filter { $0.voteCount ?? 0 >= 100 }
                .sorted { lhs, rhs in
                    let l = (lhs.voteAverage ?? 0) * log10(Double(max(lhs.voteCount ?? 1, 1)))
                    let r = (rhs.voteAverage ?? 0) * log10(Double(max(rhs.voteCount ?? 1, 1)))
                    return l > r
                }
        } catch {
            similarShows = []
        }
    }
}
