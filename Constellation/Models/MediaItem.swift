//
//  MediaItem.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//


import Foundation
import SwiftData

protocol MediaItem {
    var id: UUID { get }
    var title: String { get }
    var mediaType: MediaType { get }
    var dateAdded: Date { get }
    var notes: String? { get set }
    var themes: [String] { get set }
}

enum MediaType: String, Codable, Sendable {  // ← Add Sendable
    case movie
    case tvShow
    case article
    case podcast
    case book
    
    var icon: String {
        switch self {
        case .movie: return "🎬"
        case .tvShow: return "📺"
        case .article: return "📰"
        case .podcast: return "🎙️"
        case .book: return "📚"
        }
    }
    
    var displayName: String {
        switch self {
        case .movie: return "Movie"
        case .tvShow: return "TV Show"
        case .article: return "Article"
        case .podcast: return "Podcast"
        case .book: return "Book"
        }
    }
}
