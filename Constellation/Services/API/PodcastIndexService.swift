import Foundation
import CryptoKit

struct PodcastIndexShow: Identifiable, Hashable {
    let id: Int
    let title: String
    let author: String?
    let description: String?
    let imageURL: URL?
    let feedURL: String?
}

struct PodcastIndexEpisode: Identifiable, Hashable {
    let id: Int
    let feedID: Int?
    let title: String
    let feedTitle: String
    let description: String?
    let datePublished: Date?
    let durationMinutes: Int?
    let enclosureURL: URL?
    let imageURL: URL?
    let feedURL: String?
    let guid: String?
}

enum PodcastIndexServiceError: LocalizedError {
    case missingCredentials
    case invalidURL
    case requestFailed(status: Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Podcast Index credentials are missing."
        case .invalidURL:
            return "Invalid Podcast Index request URL."
        case .requestFailed(let status):
            return "Podcast Index request failed (\(status))."
        }
    }
}

final class PodcastIndexService {
    static let shared = PodcastIndexService()

    private let baseURL = "https://api.podcastindex.org/api/1.0"
    private let userAgent = "Constellation/1.0"

    private init() {}

    func searchShows(query: String, limit: Int = 30) async throws -> [PodcastIndexShow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let feeds = try await searchFeeds(query: trimmed, max: max(25, min(limit * 5, 120)))
        let mapped = feeds.map(mapShow(feed:))
        let normalizedQuery = normalizeSearchText(trimmed)
        let queryTokens = tokenize(normalizedQuery)

        // Podcast index often returns near-identical feeds; keep one high-quality
        // result per canonical title bucket.
        var bestByKey: [String: (show: PodcastIndexShow, score: Int)] = [:]
        for show in mapped {
            let key = dedupeKey(for: show)
            let score = showSearchScore(show: show, query: normalizedQuery, tokens: queryTokens)
            if let current = bestByKey[key], current.score >= score {
                continue
            }
            bestByKey[key] = (show, score)
        }

        return bestByKey.values
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.show.title.localizedCaseInsensitiveCompare(rhs.show.title) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map(\.show)
    }

    func fetchEpisodes(for show: PodcastIndexShow, max: Int = 40) async throws -> [PodcastIndexEpisode] {
        try await fetchEpisodes(feedID: show.id, max: max)
    }

    func searchEpisodes(query: String, limit: Int = 25) async throws -> [PodcastIndexEpisode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let feeds = try await searchFeeds(query: trimmed, max: 10)
        guard !feeds.isEmpty else { return [] }

        var gathered: [PodcastIndexEpisode] = []
        await withTaskGroup(of: [PodcastIndexEpisode].self) { group in
            for feed in feeds.prefix(8) {
                group.addTask {
                    (try? await self.fetchEpisodes(feedID: feed.id, max: 20)) ?? []
                }
            }

            for await episodes in group {
                gathered.append(contentsOf: episodes)
            }
        }

        let tokens = tokenize(trimmed)
        let filtered = gathered.filter { episode in
            let searchable = [
                episode.title,
                episode.feedTitle,
                episode.description ?? ""
            ]
            .joined(separator: " ")
            .lowercased()

            return tokens.allSatisfy { searchable.contains($0) }
        }

        var seen = Set<String>()
        let deduped = filtered.filter { episode in
            let key = "\(episode.id)::\(episode.feedID ?? -1)::\(episode.guid ?? "")"
            return seen.insert(key).inserted
        }

        return deduped
            .sorted {
                ($0.datePublished ?? .distantPast) > ($1.datePublished ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    private func searchFeeds(query: String, max: Int) async throws -> [PodcastFeedRecord] {
        let data = try await request(
            path: "/search/byterm",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "max", value: String(max))
            ]
        )

        let decoded = try JSONDecoder().decode(PodcastFeedSearchResponse.self, from: data)
        return decoded.feeds ?? []
    }

    private func fetchEpisodes(feedID: Int, max: Int) async throws -> [PodcastIndexEpisode] {
        let data = try await request(
            path: "/episodes/byfeedid",
            queryItems: [
                URLQueryItem(name: "id", value: String(feedID)),
                URLQueryItem(name: "max", value: String(max)),
                URLQueryItem(name: "fulltext", value: "true")
            ]
        )

        let decoded = try JSONDecoder().decode(PodcastEpisodeSearchResponse.self, from: data)
        let records = decoded.items ?? []
        return records.map { item in
            mapEpisode(item: item, fallbackFeedID: feedID)
        }
    }

    private func mapEpisode(item: PodcastEpisodeRecord, fallbackFeedID: Int?) -> PodcastIndexEpisode {
        let publishedDate = item.datePublished.flatMap { TimeInterval($0) }.map {
            Date(timeIntervalSince1970: $0)
        }

        return PodcastIndexEpisode(
            id: item.id,
            feedID: item.feedID ?? fallbackFeedID,
            title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
            feedTitle: item.feedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Podcast",
            description: htmlToPlainText(item.description),
            datePublished: publishedDate,
            durationMinutes: parseDurationMinutes(item.duration),
            enclosureURL: URL(string: item.enclosureURL ?? ""),
            imageURL: URL(string: item.image ?? item.feedImage ?? ""),
            feedURL: item.feedURL,
            guid: item.guid
        )
    }

    private func mapShow(feed: PodcastFeedRecord) -> PodcastIndexShow {
        PodcastIndexShow(
            id: feed.id,
            title: feed.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Podcast",
            author: feed.author?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            description: htmlToPlainText(feed.description),
            imageURL: URL(string: feed.image ?? ""),
            feedURL: feed.url
        )
    }

    private func dedupeKey(for show: PodcastIndexShow) -> String {
        normalizeSearchText(show.title)
    }

    private func showSearchScore(show: PodcastIndexShow, query: String, tokens: [String]) -> Int {
        let title = normalizeSearchText(show.title)
        let author = normalizeSearchText(show.author ?? "")
        var score = 0

        if title == query { score += 500 }
        if title.hasPrefix(query) { score += 220 }
        if title.contains(query) { score += 120 }
        if author.contains(query) { score += 50 }

        for token in tokens where token.count > 1 {
            if title == token { score += 80 }
            if title.hasPrefix(token) { score += 35 }
            if title.contains(token) { score += 20 }
            if author.contains(token) { score += 10 }
        }

        // Light quality signals to prefer official/complete feeds.
        if show.imageURL != nil { score += 8 }
        if (show.description?.count ?? 0) > 80 { score += 6 }
        if let feedURL = show.feedURL?.lowercased(), feedURL.contains("npr.org") {
            score += 8
        }

        // Push obvious test feeds down.
        if author == "tester" || author == "test" || author.contains("dummy") {
            score -= 200
        }

        return score
    }

    private func normalizeSearchText(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let stripped = lowered.replacingOccurrences(
            of: "[^a-z0-9\\s]",
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        guard let credentials = credentials else {
            throw PodcastIndexServiceError.missingCredentials
        }

        var components = URLComponents(string: baseURL + path)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw PodcastIndexServiceError.invalidURL
        }

        let authDate = String(Int(Date().timeIntervalSince1970))
        let authToken = Self.sha1Hex(credentials.key + credentials.secret + authDate)

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(credentials.key, forHTTPHeaderField: "X-Auth-Key")
        request.setValue(authDate, forHTTPHeaderField: "X-Auth-Date")
        request.setValue(authToken, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PodcastIndexServiceError.requestFailed(status: -1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PodcastIndexServiceError.requestFailed(status: http.statusCode)
        }

        return data
    }

    private var credentials: Credentials? {
        let keys = Bundle.main.object(forInfoDictionaryKey: "APIKeys") as? [String: String]
        let key = keys?["PodcastIndexKey"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? keys?["Podcast"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let secret = keys?["PodcastIndexSecret"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? keys?["PodcastSecret"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !key.isEmpty, !secret.isEmpty else { return nil }
        return Credentials(key: key, secret: secret)
    }

    private static func sha1Hex(_ input: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func parseDurationMinutes(_ raw: Int?) -> Int? {
        guard let raw, raw > 0 else { return nil }
        if raw >= 3600 {
            return raw / 60
        }
        if raw >= 60 {
            return raw / 60
        }
        return raw
    }

    private func htmlToPlainText(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let withoutTags = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let compact = withoutTags.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? nil : compact
    }

    private func tokenize(_ query: String) -> [String] {
        query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 }
    }
}

private struct Credentials {
    let key: String
    let secret: String
}

private struct PodcastFeedSearchResponse: Decodable {
    let feeds: [PodcastFeedRecord]?
}

private struct PodcastFeedRecord: Decodable {
    let id: Int
    let title: String?
    let author: String?
    let description: String?
    let image: String?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case description
        case image
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeFlexibleInt(forKey: .id)
        self.title = try? container.decode(String.self, forKey: .title)
        self.author = try? container.decode(String.self, forKey: .author)
        self.description = try? container.decode(String.self, forKey: .description)
        self.image = try? container.decode(String.self, forKey: .image)
        self.url = try? container.decode(String.self, forKey: .url)
    }
}

private struct PodcastEpisodeSearchResponse: Decodable {
    let items: [PodcastEpisodeRecord]?
}

private struct PodcastEpisodeRecord: Decodable {
    let id: Int
    let title: String
    let description: String?
    let datePublished: Int?
    let duration: Int?
    let enclosureURL: String?
    let image: String?
    let feedImage: String?
    let feedTitle: String?
    let feedURL: String?
    let feedID: Int?
    let guid: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case datePublished
        case duration
        case enclosureURL = "enclosureUrl"
        case image
        case feedImage
        case feedTitle
        case feedURL
        case feedID = "feedId"
        case guid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleInt(forKey: .id)
        title = (try? container.decode(String.self, forKey: .title)) ?? "Untitled Episode"
        description = try? container.decode(String.self, forKey: .description)
        datePublished = try container.decodeFlexibleIntIfPresent(forKey: .datePublished)
        duration = try container.decodeFlexibleIntIfPresent(forKey: .duration)
        enclosureURL = try? container.decode(String.self, forKey: .enclosureURL)
        image = try? container.decode(String.self, forKey: .image)
        feedImage = try? container.decode(String.self, forKey: .feedImage)
        feedTitle = try? container.decode(String.self, forKey: .feedTitle)
        feedURL = try? container.decode(String.self, forKey: .feedURL)
        feedID = try container.decodeFlexibleIntIfPresent(forKey: .feedID)
        guid = try? container.decode(String.self, forKey: .guid)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? decode(String.self, forKey: key), let intValue = Int(stringValue) {
            return intValue
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected int or int string")
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? decode(String.self, forKey: key), let intValue = Int(stringValue) {
            return intValue
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
