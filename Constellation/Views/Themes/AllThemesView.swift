//
//  AllThemesView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import SwiftUI
import SwiftData

struct AllThemesView: View {
    @Query private var movies: [Movie]
    @Query private var tvShows: [TVShow]
    
    var allThemes: [(theme: String, count: Int)] {
        let movieThemes = movies.flatMap(\.themes)
        let showThemes = tvShows.flatMap(\.themes)
        let combined = movieThemes + showThemes
        let grouped = Dictionary(grouping: combined) { $0 }
        
        return grouped
            .map { (theme: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    var body: some View {
        List {
            ForEach(allThemes, id: \.theme) { item in
                NavigationLink(destination: ThemeDetailView(themeName: item.theme)) {
                    HStack {
                        Text(item.theme.capitalized)
                        
                        Spacer()
                        
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("All Themes")
    }
}
