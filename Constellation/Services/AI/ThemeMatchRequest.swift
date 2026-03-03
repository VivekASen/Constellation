import Foundation

struct ThemeMatchRequest {
    let mediaType: String
    let title: String
    let year: Int?
    let overview: String?
    let genres: [String]
    let notes: String?
}
