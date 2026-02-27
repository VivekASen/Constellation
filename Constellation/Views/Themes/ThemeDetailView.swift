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
    
    let themeName: String
    
    var moviesWithTheme: [Movie] {
        allMovies.filter { $0.themes.contains(themeName) }
    }
    
    var showsWithTheme: [TVShow] {
        allTVShows.filter { $0.themes.contains(themeName) }
    }
    
    var totalCount: Int {
        moviesWithTheme.count + showsWithTheme.count
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(themeName.capitalized)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("\(totalCount) items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
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
