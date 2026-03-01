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
    
    private init() {}
    
    // MARK: - Movies
    
    func searchMovies(query: String) async throws -> [TMDBMovie] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(baseURL)/search/movie?api_key=\(apiKey)&query=\(encodedQuery)"
        let data = try await fetchData(urlString: urlString)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }
    
    func getMovieDetails(id: Int) async throws -> TMDBMovieDetail {
        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)&append_to_response=credits"
        let data = try await fetchData(urlString: urlString)
        return try JSONDecoder().decode(TMDBMovieDetail.self, from: data)
    }
    
    func getPopularMovies() async throws -> [TMDBMovie] {
        let urlString = "\(baseURL)/movie/popular?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString)
        let response = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return response.results
    }
    
    // MARK: - TV Shows
    
    func searchTVShows(query: String) async throws -> [TMDBTVShow] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(baseURL)/search/tv?api_key=\(apiKey)&query=\(encodedQuery)"
        let data = try await fetchData(urlString: urlString)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }
    
    func getTVShowDetails(id: Int) async throws -> TMDBTVShowDetail {
        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString)
        return try JSONDecoder().decode(TMDBTVShowDetail.self, from: data)
    }
    
    func getPopularTVShows() async throws -> [TMDBTVShow] {
        let urlString = "\(baseURL)/tv/popular?api_key=\(apiKey)"
        let data = try await fetchData(urlString: urlString)
        let response = try JSONDecoder().decode(TMDBTVSearchResponse.self, from: data)
        return response.results
    }
    
    // MARK: - Shared Request Helper
    
    private func fetchData(urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw TMDBError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TMDBError.networkError
        }
        
        return data
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
    
    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
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
    
    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
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

// MARK: - Errors

enum TMDBError: Error {
    case invalidURL
    case networkError
    case decodingError
}
