import Foundation
import SwiftData

@Model
final class PodcastHighlight {
    var id: UUID
    var episodeID: String
    var timestampSeconds: Double
    var highlight: String
    var themes: [String]
    var createdAt: Date

    init(
        episodeID: String,
        timestampSeconds: Double,
        highlight: String,
        themes: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.episodeID = episodeID
        self.timestampSeconds = max(0, timestampSeconds)
        self.highlight = highlight
        self.themes = themes
        self.createdAt = createdAt
    }
}

extension PodcastHighlight {
    var timestampFormatted: String {
        let total = max(0, Int(timestampSeconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
