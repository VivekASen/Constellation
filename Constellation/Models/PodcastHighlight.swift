import Foundation
import SwiftData

@Model
final class PodcastHighlight {
    var id: UUID
    var episodeID: String
    var timestampSeconds: Double
    var highlight: String
    var detailText: String?
    var isPinned: Bool
    var themes: [String]
    var createdAt: Date
    var updatedAt: Date?

    init(
        episodeID: String,
        timestampSeconds: Double,
        highlight: String,
        detailText: String? = nil,
        isPinned: Bool = false,
        themes: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = UUID()
        self.episodeID = episodeID
        self.timestampSeconds = max(0, timestampSeconds)
        self.highlight = highlight
        self.detailText = detailText
        self.isPinned = isPinned
        self.themes = themes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
