//
//  Movie.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//

import Foundation
import SwiftData

@Model
final class Movie {
    var id: UUID
    var title: String
    var year: Int?
    var director: String?
    var posterURL: String?
    var overview: String?
    var genres: [String]
    var rating: Double?
    var watchedDate: Date?
    var dateAdded: Date
    var notes: String?
    var themes: [String]
    var tmdbID: Int?
    
    init(
        title: String,
        year: Int? = nil,
        director: String? = nil,
        posterURL: String? = nil,
        overview: String? = nil,
        genres: [String] = [],
        rating: Double? = nil,
        watchedDate: Date? = nil,
        notes: String? = nil,
        tmdbID: Int? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.year = year
        self.director = director
        self.posterURL = posterURL
        self.overview = overview
        self.genres = genres
        self.rating = rating
        self.watchedDate = watchedDate
        self.dateAdded = Date()
        self.notes = notes
        self.themes = []
        self.tmdbID = tmdbID
    }
}

// Conform to MediaItem
extension Movie: MediaItem {
    var mediaType: MediaType { .movie }
}
