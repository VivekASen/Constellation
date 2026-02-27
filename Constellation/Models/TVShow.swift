//
//  TVShow.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//


import Foundation
import SwiftData

@Model
final class TVShow {
    var id: UUID
    var title: String
    var year: Int?
    var creator: String?
    var posterURL: String?
    var overview: String?
    var genres: [String]
    var seasonCount: Int?
    var episodeCount: Int?
    var rating: Double?
    var watchedDate: Date?
    var dateAdded: Date
    var notes: String?
    var themes: [String]
    var tmdbID: Int?
    
    init(
        title: String,
        year: Int? = nil,
        creator: String? = nil,
        posterURL: String? = nil,
        overview: String? = nil,
        genres: [String] = [],
        seasonCount: Int? = nil,
        episodeCount: Int? = nil,
        rating: Double? = nil,
        watchedDate: Date? = nil,
        notes: String? = nil,
        tmdbID: Int? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.year = year
        self.creator = creator
        self.posterURL = posterURL
        self.overview = overview
        self.genres = genres
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
        self.rating = rating
        self.watchedDate = watchedDate
        self.dateAdded = Date()
        self.notes = notes
        self.themes = []
        self.tmdbID = tmdbID
    }
}

extension TVShow: MediaItem {
    var mediaType: MediaType { .tvShow }
}
