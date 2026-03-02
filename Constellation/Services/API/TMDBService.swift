//
//  TMDBService.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/27/26.
//


import Foundation

class TMDBService {
    static let shared = TMDBService()
    
    private let apiKey = "REDACTED_TMDB_KEY"
    private let baseURL = "https://api.themoviedb.org/3"
    private let cache = TMDBDataCache()
    private let searchTTL: TimeInterval = 60 * 12
    private let popularTTL: TimeInterval = 60 * 10
    private let detailTTL: TimeInterval = 60 * 60 * 6
    
    private init() {}
    
    // MARK: - Movies
    
    func searchMovies(query: String, page: Int = 1) async throws -> [TMDBMovie] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(baseURL)/search/movie?api_key=\(apiKey)&query=\(encodedQuery)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: searchTTL)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }
    
    func getMovieDetails(id: Int) async throws -> TMDBMovieDetail {
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)&append_to_response=credits"
        let data = try await fetchData(urlString: urlString, ttl: detailTTL)
        return try JSONDecoder().decode(TMDBMovieDetail.self, from: data)
    }
    
    func getPopularMovies(page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/movie/popular?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: popularTTL)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }

    func getTopRatedMovies(page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/movie/top_rated?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: popularTTL)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }

    func discoverMovies(genreID: Int, page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/discover/movie?api_key=\(apiKey)&with_genres=\(genreID)&sort_by=vote_count.desc&vote_count.gte=200&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: popularTTL)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }

    func getSimilarMovies(movieID: Int, page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/movie/\(movieID)/similar?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: searchTTL)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }

    func getMovieRecommendations(movieID: Int, page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/movie/\(movieID)/recommendations?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: searchTTL)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }

    func getMovieVideos(movieID: Int) async throws -> [TMDBVideo] {
        let urlString = "\(baseURL)/movie/\(movieID)/videos?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString, ttl: detailTTL)
        let response = try JSONDecoder().decode(TMDBVideosResponse.self, from: data)
        return response.results
    }

    func getMovieWatchProviders(movieID: Int, region: String = "US") async throws -> [TMDBWatchProvider] {
        let urlString = "\(baseURL)/movie/\(movieID)/watch/providers?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString, ttl: detailTTL)
        let response = try JSONDecoder().decode(TMDBWatchProvidersResponse.self, from: data)
        return response.results[region]?.allProviders ?? []
    }

    func getMovieKeywords(movieID: Int) async throws -> [String] {
        let urlString = "\(baseURL)/movie/\(movieID)/keywords?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString, ttl: detailTTL)
        let response = try JSONDecoder().decode(TMDBMovieKeywordsResponse.self, from: data)
        return response.keywords.map(\.name)
    }

    func discoverMovies(keywordID: Int, page: Int = 1) async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/discover/movie?api_key=\(apiKey)&with_keywords=\(keywordID)&sort_by=vote_count.desc&vote_count.gte=60&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: popularTTL)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }
    
    // MARK: - TV Shows
    
    func searchTVShows(query: String, page: Int = 1) async throws -> [TMDBTVShow] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(baseURL)/search/tv?api_key=\(apiKey)&query=\(encodedQuery)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: searchTTL)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }
    
    func getTVShowDetails(id: Int) async throws -> TMDBTVShowDetail {
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString, ttl: detailTTL)
        return try JSONDecoder().decode(TMDBTVShowDetail.self, from: data)
    }
    
    func getPopularTVShows(page: Int = 1) async throws -> [TMDBTVShow] {
        let urlString = "\(baseURL)/tv/popular?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: popularTTL)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }

    func getTopRatedTVShows(page: Int = 1) async throws -> [TMDBTVShow] {
        let urlString = "\(baseURL)/tv/top_rated?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: popularTTL)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }

    func discoverTVShows(genreID: Int, page: Int = 1) async throws -> [TMDBTVShow] {
        let urlString = "\(baseURL)/discover/tv?api_key=\(apiKey)&with_genres=\(genreID)&sort_by=vote_count.desc&vote_count.gte=150&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: popularTTL)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }

    func getSimilarTVShows(tvID: Int, page: Int = 1) async throws -> [TMDBTVShow] {
        let urlString = "\(baseURL)/tv/\(tvID)/similar?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: searchTTL)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }

    func getTVRecommendations(tvID: Int, page: Int = 1) async throws -> [TMDBTVShow] {
        let urlString = "\(baseURL)/tv/\(tvID)/recommendations?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: searchTTL)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }

    func getTVVideos(tvID: Int) async throws -> [TMDBVideo] {
        let urlString = "\(baseURL)/tv/\(tvID)/videos?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString, ttl: detailTTL)
        let response = try JSONDecoder().decode(TMDBVideosResponse.self, from: data)
        return response.results
    }

    func getTVWatchProviders(tvID: Int, region: String = "US") async throws -> [TMDBWatchProvider] {
        let urlString = "\(baseURL)/tv/\(tvID)/watch/providers?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString, ttl: detailTTL)
        let response = try JSONDecoder().decode(TMDBWatchProvidersResponse.self, from: data)
        return response.results[region]?.allProviders ?? []
    }

    func getTVKeywords(tvID: Int) async throws -> [String] {
        let urlString = "\(baseURL)/tv/\(tvID)/keywords?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString, ttl: detailTTL)
        let response = try JSONDecoder().decode(TMDBTVKeywordsResponse.self, from: data)
        return response.results.map(\.name)
    }

    func discoverTVShows(keywordID: Int, page: Int = 1) async throws -> [TMDBTVShow] {
        let urlString = "\(baseURL)/discover/tv?api_key=\(apiKey)&with_keywords=\(keywordID)&sort_by=vote_count.desc&vote_count.gte=40&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: popularTTL)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }

    func searchKeywords(query: String) async throws -> [TMDBKeyword] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(baseURL)/search/keyword?api_key=\(apiKey)&query=\(encodedQuery)"
        let data = try await fetchData(urlString: urlString, ttl: searchTTL)
        let response = try JSONDecoder().decode(TMDBKeywordSearchResponse.self, from: data)
        return response.results
    }

    // MARK: - Trending

    func getTrendingAll(timeWindow: TMDBTrendingWindow = .day, page: Int = 1) async throws -> [TMDBTrendingItem] {
        let urlString = "\(baseURL)/trending/all/\(timeWindow.rawValue)?api_key=\(apiKey)&page=\(max(1, page))"
        let data = try await fetchData(urlString: urlString, ttl: searchTTL)
        let response = try JSONDecoder().decode(TMDBTrendingResponse.self, from: data)
        return response.results
    }
    
    // MARK: - Shared Request Helper
    
    private func fetchData(urlString: String, ttl: TimeInterval) async throws -> Data {
        if let cached = await cache.data(for: urlString) {
            return cached
        }

        guard let url = URL(string: urlString) else {
            throw TMDBError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TMDBError.networkError
        }
        
        await cache.store(data, for: urlString, ttl: ttl)
        return data
    }
}

private actor TMDBDataCache {
    private struct Entry {
        let data: Data
        let expiresAt: Date
    }

    private var store: [String: Entry] = [:]

    func data(for key: String) -> Data? {
        guard let entry = store[key] else { return nil }
        if entry.expiresAt < Date() {
            store[key] = nil
            return nil
        }
        return entry.data
    }

    func store(_ data: Data, for key: String, ttl: TimeInterval) {
        store[key] = Entry(data: data, expiresAt: Date().addingTimeInterval(ttl))
    }
}

// MARK: - Movie Models

struct TMDBSearchResponse: Codable {
    let results: [TMDBMovie]
}

struct TMDBMovie: Codable, Identifiable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIDs: [Int]?
    
    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIDs = "genre_ids"
    }
    
    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    var year: Int? {
        guard let releaseDate else { return nil }
        return Int(releaseDate.split(separator: "-").first ?? "")
    }
}

struct TMDBMovieDetail: Codable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let voteAverage: Double?
    let runtime: Int?
    let genres: [TMDBGenre]
    let credits: TMDBCredits?
    
    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres, credits
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
    }
    
    var director: String? {
        credits?.crew.first { $0.job == "Director" }?.name
    }
    
    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    var year: Int? {
        guard let releaseDate else { return nil }
        return Int(releaseDate.split(separator: "-").first ?? "")
    }
}

// MARK: - TV Models

struct TMDBTVSearchResponse: Codable {
    let results: [TMDBTVShow]
}

struct TMDBTVShow: Codable, Identifiable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIDs: [Int]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIDs = "genre_ids"
    }
    
    var title: String { name }
    
    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    var year: Int? {
        guard let firstAirDate else { return nil }
        return Int(firstAirDate.split(separator: "-").first ?? "")
    }
}

struct TMDBTVShowDetail: Codable {
    let id: Int
    let name: String
    let overview: String?
    let posterPath: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genres: [TMDBGenre]
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let createdBy: [TMDBCreator]
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case createdBy = "created_by"
    }
    
    var title: String { name }
    
    var creator: String? {
        createdBy.first?.name
    }
    
    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
    
    var year: Int? {
        guard let firstAirDate else { return nil }
        return Int(firstAirDate.split(separator: "-").first ?? "")
    }
}

// MARK: - Shared Models

struct TMDBGenre: Codable {
    let id: Int
    let name: String
}

struct TMDBCredits: Codable {
    let crew: [TMDBCrewMember]
}

struct TMDBCrewMember: Codable {
    let name: String
    let job: String
}

struct TMDBCreator: Codable {
    let id: Int
    let name: String
}

struct TMDBKeyword: Codable {
    let id: Int
    let name: String
}

struct TMDBMovieKeywordsResponse: Codable {
    let id: Int
    let keywords: [TMDBKeyword]
}

struct TMDBTVKeywordsResponse: Codable {
    let id: Int
    let results: [TMDBKeyword]
}

struct TMDBKeywordSearchResponse: Codable {
    let results: [TMDBKeyword]
}

struct TMDBVideosResponse: Codable {
    let results: [TMDBVideo]
}

struct TMDBVideo: Codable, Identifiable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
    let official: Bool?

    var youtubeURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }
}

struct TMDBWatchProvidersResponse: Codable {
    let results: [String: TMDBWatchProviderRegion]
}

struct TMDBWatchProviderRegion: Codable {
    let flatrate: [TMDBWatchProvider]?
    let rent: [TMDBWatchProvider]?
    let buy: [TMDBWatchProvider]?

    var allProviders: [TMDBWatchProvider] {
        let merged = (flatrate ?? []) + (rent ?? []) + (buy ?? [])
        var seen = Set<Int>()
        return merged.filter { provider in
            guard !seen.contains(provider.providerID) else { return false }
            seen.insert(provider.providerID)
            return true
        }
    }
}

struct TMDBWatchProvider: Codable, Identifiable {
    let providerID: Int
    let providerName: String
    let logoPath: String?

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
    }

    var id: Int { providerID }

    var logoURL: URL? {
        guard let logoPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(logoPath)")
    }
}

enum TMDBTrendingWindow: String {
    case day
    case week
}

struct TMDBTrendingResponse: Codable {
    let results: [TMDBTrendingItem]
}

struct TMDBTrendingItem: Codable, Identifiable {
    let id: Int
    let mediaType: String
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    var resolvedTitle: String {
        title ?? name ?? "Unknown"
    }

    var year: Int? {
        if let releaseDate {
            return Int(releaseDate.split(separator: "-").first ?? "")
        }
        if let firstAirDate {
            return Int(firstAirDate.split(separator: "-").first ?? "")
        }
        return nil
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
}

// MARK: - TasteDive (Optional Signal Source)

final class TasteDiveService {
    static let shared = TasteDiveService()

    private let baseURL = "https://tastedive.com/api/similar"
    private let ttl: TimeInterval = 60 * 30
    private let cache = TMDBDataCache()

    private init() {}

    func similar(
        query: String,
        type: TasteDiveMediaType? = nil,
        limit: Int = 8
    ) async throws -> [TasteDiveResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let apiKey = UserDefaults.standard.string(forKey: "tastedive.apiKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            throw TasteDiveError.missingAPIKey
        }

        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "k", value: apiKey),
            URLQueryItem(name: "info", value: "1"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 20))))
        ]
        if let type {
            components?.queryItems?.append(URLQueryItem(name: "type", value: type.rawValue))
        }

        guard let url = components?.url else {
            throw TasteDiveError.invalidURL
        }

        let key = url.absoluteString
        if let cached = await cache.data(for: key) {
            let response = try JSONDecoder().decode(TasteDiveEnvelope.self, from: cached)
            return response.similar.results
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TasteDiveError.networkError
        }

        await cache.store(data, for: key, ttl: ttl)
        let decoded = try JSONDecoder().decode(TasteDiveEnvelope.self, from: data)
        return decoded.similar.results
    }
}

enum TasteDiveMediaType: String {
    case movies
    case shows
}

private struct TasteDiveEnvelope: Codable {
    let similar: TasteDiveSimilar

    enum CodingKeys: String, CodingKey {
        case similar = "Similar"
    }
}

private struct TasteDiveSimilar: Codable {
    let results: [TasteDiveResult]

    enum CodingKeys: String, CodingKey {
        case results = "Results"
    }
}

struct TasteDiveResult: Codable, Identifiable {
    let name: String
    let type: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case type = "Type"
    }

    var id: String { "\(type ?? "unknown")-\(name.lowercased())" }
}

enum TasteDiveError: Error {
    case missingAPIKey
    case invalidURL
    case networkError
}

// MARK: - Errors

enum TMDBError: Error {
    case invalidURL
    case networkError
    case decodingError
}
