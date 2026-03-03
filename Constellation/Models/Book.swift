//
//  Book.swift
//  Constellation
//
//  Created by Codex on 3/3/26.
//

import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var year: Int?
    var author: String?
    var coverURL: String?
    var overview: String?
    var genres: [String]
    var pageCount: Int?
    var rating: Double?
    var watchedDate: Date?
    var dateAdded: Date
    var notes: String?
    var themes: [String]
    var openLibraryWorkKey: String?
    var isbn: String?

    init(
        title: String,
        year: Int? = nil,
        author: String? = nil,
        coverURL: String? = nil,
        overview: String? = nil,
        genres: [String] = [],
        pageCount: Int? = nil,
        rating: Double? = nil,
        watchedDate: Date? = nil,
        notes: String? = nil,
        openLibraryWorkKey: String? = nil,
        isbn: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.year = year
        self.author = author
        self.coverURL = coverURL
        self.overview = overview
        self.genres = genres
        self.pageCount = pageCount
        self.rating = rating
        self.watchedDate = watchedDate
        self.dateAdded = Date()
        self.notes = notes
        self.themes = []
        self.openLibraryWorkKey = openLibraryWorkKey
        self.isbn = isbn
    }
}

extension Book: MediaItem {
    var mediaType: MediaType { .book }
}
