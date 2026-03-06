import Foundation
import SwiftData

@Model
final class PodcastEpisode {
    var id: UUID
    var title: String
    var showName: String
    var showAuthor: String?
    var episodeNumber: Int?
    var releaseDate: Date?
    var durationSeconds: Int?
    var overview: String?
    var audioURL: String?
    var thumbnailURL: String?
    var feedURL: String?
    var episodeGUID: String?
    var podcastIndexEpisodeID: Int?
    var podcastIndexFeedID: Int?
    var genres: [String]
    var rating: Double?
    var dateAdded: Date
    var currentPositionSeconds: Double
    var completedAt: Date?
    var aiSummary: String?
    var transcriptURL: String?
    var transcriptText: String?
    var notes: String?
    var themes: [String]

    init(
        title: String,
        showName: String,
        showAuthor: String? = nil,
        episodeNumber: Int? = nil,
        releaseDate: Date? = nil,
        durationSeconds: Int? = nil,
        overview: String? = nil,
        audioURL: String? = nil,
        thumbnailURL: String? = nil,
        feedURL: String? = nil,
        episodeGUID: String? = nil,
        podcastIndexEpisodeID: Int? = nil,
        podcastIndexFeedID: Int? = nil,
        genres: [String] = [],
        rating: Double? = nil,
        currentPositionSeconds: Double = 0,
        completedAt: Date? = nil,
        aiSummary: String? = nil,
        transcriptURL: String? = nil,
        transcriptText: String? = nil,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.showName = showName
        self.showAuthor = showAuthor
        self.episodeNumber = episodeNumber
        self.releaseDate = releaseDate
        self.durationSeconds = durationSeconds
        self.overview = overview
        self.audioURL = audioURL
        self.thumbnailURL = thumbnailURL
        self.feedURL = feedURL
        self.episodeGUID = episodeGUID
        self.podcastIndexEpisodeID = podcastIndexEpisodeID
        self.podcastIndexFeedID = podcastIndexFeedID
        self.genres = genres
        self.rating = rating
        self.dateAdded = Date()
        self.currentPositionSeconds = currentPositionSeconds
        self.completedAt = completedAt
        self.aiSummary = aiSummary
        self.transcriptURL = transcriptURL
        self.transcriptText = transcriptText
        self.notes = notes
        self.themes = []
    }
}

extension PodcastEpisode: MediaItem {
    var mediaType: MediaType { .podcast }
}

extension PodcastEpisode {
    var durationMinutes: Int? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        return max(1, durationSeconds / 60)
    }

    var year: Int? {
        guard let releaseDate else { return nil }
        return Calendar.current.component(.year, from: releaseDate)
    }
}
