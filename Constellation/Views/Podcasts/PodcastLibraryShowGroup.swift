import Foundation

struct PodcastLibraryShowGroup {
    let name: String
    let episodes: [PodcastEpisode]
    let feedID: Int?
    let feedURL: String?
    let artworkURL: String?
}
