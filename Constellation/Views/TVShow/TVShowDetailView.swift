//
//  TVShowDetailView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI

struct TVShowDetailView: View {
    let show: TVShow
    
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
    }
}
