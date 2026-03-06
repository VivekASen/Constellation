import Foundation

final class HardcoverBooksService {
    static let shared = HardcoverBooksService()

    struct SearchBook: Identifiable {
        let id: String
        let title: String
        let author: String?
        let year: Int?
        let coverURL: URL?
        let pageCount: Int?
        let description: String?
        let isbn: String?
        let subjects: [String]
        let primaryGenre: String?
        let rating: Double?
        let ratingCount: Int?
        let hasAudiobook: Bool
        let hasEbook: Bool
        let slug: String?
    }

    struct BookMetadata {
        let averageRating: Double?
        let pageCount: Int?
        let description: String?
        let infoURL: URL?
        let coverURL: URL?
        let primaryGenre: String?
        let ratingCount: Int?
        let hasAudiobook: Bool
        let hasEbook: Bool
    }

    private let endpoint = URL(string: "https://api.hardcover.app/v1/graphql")!

    private init() {}

    func searchBooks(query: String, limit: Int = 25) async throws -> [SearchBook] {
        guard let token = apiToken, !token.isEmpty else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let gql = """
        query HardcoverBookSearch($query: String!, $perPage: Int!) {
          search(query: $query, query_type: "Book", per_page: $perPage, page: 1) {
            results
          }
        }
        """

        let payload: [String: Any] = [
            "query": gql,
            "variables": [
                "query": trimmed,
                "perPage": max(1, min(limit, 50))
            ]
        ]

        let json = try await performGraphQL(token: token, payload: payload)
        guard
            let data = json["data"] as? [String: Any],
            let search = data["search"] as? [String: Any],
            let results = search["results"] as? [String: Any],
            let hits = results["hits"] as? [[String: Any]]
        else {
            return []
        }

        return hits.compactMap { hit in
            guard let document = hit["document"] as? [String: Any] else { return nil }
            return searchBook(from: document)
        }
    }

    func lookupMetadata(isbn: String?, title: String, author: String?) async throws -> BookMetadata? {
        guard let token = apiToken, !token.isEmpty else { return nil }

        var merged = BookMetadata(
            averageRating: nil,
            pageCount: nil,
            description: nil,
            infoURL: nil,
            coverURL: nil,
            primaryGenre: nil,
            ratingCount: nil,
            hasAudiobook: false,
            hasEbook: false
        )

        if let isbn, !isbn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let isbnMetadata = try await queryByISBN(token: token, isbn: isbn) {
                merged = merge(base: merged, incoming: isbnMetadata)
            }
        }

        let query = [title, author].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !query.isEmpty {
            if let searchMetadata = try await queryBySearch(token: token, query: query) {
                merged = merge(base: merged, incoming: searchMetadata)
            }
        }

        if merged.averageRating == nil,
           merged.pageCount == nil,
           (merged.description ?? "").isEmpty,
           merged.infoURL == nil,
           merged.coverURL == nil,
           (merged.primaryGenre ?? "").isEmpty,
           merged.ratingCount == nil,
           !merged.hasAudiobook,
           !merged.hasEbook {
            return nil
        }

        return merged
    }

    private func merge(base: BookMetadata, incoming: BookMetadata) -> BookMetadata {
        BookMetadata(
            averageRating: max(base.averageRating ?? 0, incoming.averageRating ?? 0) > 0
                ? max(base.averageRating ?? 0, incoming.averageRating ?? 0)
                : nil,
            pageCount: max(base.pageCount ?? 0, incoming.pageCount ?? 0) > 0
                ? max(base.pageCount ?? 0, incoming.pageCount ?? 0)
                : nil,
            description: {
                let incomingText = incoming.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !incomingText.isEmpty { return incomingText }
                let baseText = base.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return baseText.isEmpty ? nil : baseText
            }(),
            infoURL: incoming.infoURL ?? base.infoURL,
            coverURL: incoming.coverURL ?? base.coverURL,
            primaryGenre: incoming.primaryGenre ?? base.primaryGenre,
            ratingCount: max(base.ratingCount ?? 0, incoming.ratingCount ?? 0) > 0
                ? max(base.ratingCount ?? 0, incoming.ratingCount ?? 0)
                : nil,
            hasAudiobook: base.hasAudiobook || incoming.hasAudiobook,
            hasEbook: base.hasEbook || incoming.hasEbook
        )
    }

    private func queryByISBN(token: String, isbn: String) async throws -> BookMetadata? {
        let cleaned = isbn.filter { $0.isNumber || $0 == "X" || $0 == "x" }
        let query = """
        query HardcoverByISBN($isbn13: String!, $isbn10: String!) {
          editions(
            where: {
              _or: [
                { isbn_13: { _eq: $isbn13 } },
                { isbn_10: { _eq: $isbn10 } }
              ]
            },
            limit: 5
          ) {
            pages
            book {
              rating
              ratings_count
              description
              slug
              image
              cached_tags
              has_audiobook
              has_ebook
            }
          }
        }
        """

        let payload: [String: Any] = [
            "query": query,
            "variables": [
                "isbn13": cleaned,
                "isbn10": cleaned
            ]
        ]

        let json = try await performGraphQL(token: token, payload: payload)
        guard
            let data = json["data"] as? [String: Any],
            let editions = data["editions"] as? [[String: Any]],
            !editions.isEmpty
        else {
            return nil
        }

        return metadataFromEditions(editions)
    }

    private func queryBySearch(token: String, query: String) async throws -> BookMetadata? {
        let gql = """
        query HardcoverSearch($query: String!) {
          search(query: $query, query_type: "Book", per_page: 5, page: 1) {
            results
          }
        }
        """

        let payload: [String: Any] = [
            "query": gql,
            "variables": ["query": query]
        ]

        let json = try await performGraphQL(token: token, payload: payload)
        guard
            let data = json["data"] as? [String: Any],
            let search = data["search"] as? [String: Any],
            let results = search["results"] as? [String: Any],
            let hits = results["hits"] as? [[String: Any]]
        else {
            return nil
        }

        let documents = hits.compactMap { $0["document"] as? [String: Any] }
        guard !documents.isEmpty else { return nil }
        var metadata = metadataFromSearch(documents)
        if metadata.primaryGenre == nil {
            var topGenre: String?
            for bookID in documents.compactMap({ intValue($0["id"]) }) {
                if let candidate = try? await queryPrimaryGenre(token: token, bookID: bookID),
                   !candidate.isEmpty {
                    topGenre = candidate
                    break
                }
            }
            if let topGenre {
                metadata = BookMetadata(
                    averageRating: metadata.averageRating,
                    pageCount: metadata.pageCount,
                    description: metadata.description,
                    infoURL: metadata.infoURL,
                    coverURL: metadata.coverURL,
                    primaryGenre: topGenre,
                    ratingCount: metadata.ratingCount,
                    hasAudiobook: metadata.hasAudiobook,
                    hasEbook: metadata.hasEbook
                )
            }
        }
        return metadata
    }

    private func metadataFromEditions(_ editions: [[String: Any]]) -> BookMetadata {
        var bestRating: Double?
        var bestPages: Int?
        var firstDescription: String?
        var firstSlug: String?
        var firstCoverURL: URL?
        var firstGenre: String?
        var bestRatingCount: Int?
        var hasAudiobook = false
        var hasEbook = false

        for edition in editions {
            if let pages = intValue(edition["pages"]) {
                bestPages = max(bestPages ?? 0, pages)
            }
            guard let book = edition["book"] as? [String: Any] else { continue }

            if let rating = doubleValue(book["rating"]) {
                bestRating = max(bestRating ?? 0, rating)
            }
            if let ratingCount = intValue(book["ratings_count"]) {
                bestRatingCount = max(bestRatingCount ?? 0, ratingCount)
            }
            if let description = (book["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty,
               firstDescription == nil {
                firstDescription = description
            }
            if let slug = book["slug"] as? String, !slug.isEmpty, firstSlug == nil {
                firstSlug = slug
            }
            if firstCoverURL == nil {
                firstCoverURL = imageURL(from: book["image"])
            }
            if firstGenre == nil {
                firstGenre = primaryGenreFrom(book["cached_tags"])
            }
            hasAudiobook = hasAudiobook || boolValue(book["has_audiobook"])
            hasEbook = hasEbook || boolValue(book["has_ebook"])
        }

        return BookMetadata(
            averageRating: normalizedRating(bestRating),
            pageCount: bestPages,
            description: firstDescription,
            infoURL: firstSlug.flatMap { URL(string: "https://hardcover.app/books/\($0)") },
            coverURL: firstCoverURL,
            primaryGenre: firstGenre,
            ratingCount: bestRatingCount,
            hasAudiobook: hasAudiobook,
            hasEbook: hasEbook
        )
    }

    private func metadataFromSearch(_ results: [[String: Any]]) -> BookMetadata {
        var bestRating: Double?
        var bestPages: Int?
        var firstDescription: String?
        var firstSlug: String?
        var firstCoverURL: URL?
        var firstGenre: String?
        var bestRatingCount: Int?
        var hasAudiobook = false
        var hasEbook = false

        for result in results {
            if let rating = doubleValue(result["rating"]) {
                bestRating = max(bestRating ?? 0, rating)
            }
            if let ratingCount = intValue(result["ratings_count"]) {
                bestRatingCount = max(bestRatingCount ?? 0, ratingCount)
            }
            if let pages = intValue(result["pages"]) {
                bestPages = max(bestPages ?? 0, pages)
            }
            if let description = (result["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty,
               firstDescription == nil {
                firstDescription = description
            }
            if let slug = result["slug"] as? String, !slug.isEmpty, firstSlug == nil {
                firstSlug = slug
            }
            if firstCoverURL == nil {
                firstCoverURL = imageURL(from: result["image"])
            }
            if firstGenre == nil, let genres = result["genres"] as? [String] {
                firstGenre = genres
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first(where: { !$0.isEmpty })
            }
            hasAudiobook = hasAudiobook || boolValue(result["has_audiobook"])
            hasEbook = hasEbook || boolValue(result["has_ebook"])
        }

        return BookMetadata(
            averageRating: normalizedRating(bestRating),
            pageCount: bestPages,
            description: firstDescription,
            infoURL: firstSlug.flatMap { URL(string: "https://hardcover.app/books/\($0)") },
            coverURL: firstCoverURL,
            primaryGenre: firstGenre,
            ratingCount: bestRatingCount,
            hasAudiobook: hasAudiobook,
            hasEbook: hasEbook
        )
    }

    private func searchBook(from document: [String: Any]) -> SearchBook? {
        let id = stringValue(document["id"]) ?? UUID().uuidString
        guard let title = stringValue(document["title"]), !title.isEmpty else { return nil }

        let author: String? = {
            if let names = document["author_names"] as? [String], let first = names.first, !first.isEmpty {
                return first
            }
            if let names = document["author_names"] as? [Any] {
                return names.compactMap { stringValue($0) }.first
            }
            return nil
        }()

        let year = intValue(document["release_year"])
        let pageCount = intValue(document["pages"])
        let description = stringValue(document["description"])
        let coverURL = imageURL(from: document["image"])
        let isbn: String? = {
            if let isbns = document["isbns"] as? [String], let first = isbns.first, !first.isEmpty {
                return first
            }
            if let isbns = document["isbns"] as? [Any] {
                return isbns.compactMap { stringValue($0) }.first
            }
            return nil
        }()

        let genres = ((document["genres"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let tags = (document["tags"] as? [String]) ?? []
        let moods = (document["moods"] as? [String]) ?? []
        let subjects = Array(Set((genres + tags + moods).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()

        return SearchBook(
            id: id,
            title: title,
            author: author,
            year: year,
            coverURL: coverURL,
            pageCount: pageCount,
            description: description,
            isbn: isbn,
            subjects: subjects,
            primaryGenre: genres.first,
            rating: normalizedRating(doubleValue(document["rating"])),
            ratingCount: intValue(document["ratings_count"]),
            hasAudiobook: boolValue(document["has_audiobook"]),
            hasEbook: boolValue(document["has_ebook"]),
            slug: stringValue(document["slug"])
        )
    }

    private func normalizedRating(_ raw: Double?) -> Double? {
        guard let raw else { return nil }
        let clamped = max(0, min(5, raw))
        return (clamped * 10).rounded() / 10
    }

    private func queryPrimaryGenre(token: String, bookID: Int) async throws -> String? {
        let gql = """
        query HardcoverPrimaryGenre($id: Int!) {
          books(where: { id: { _eq: $id } }, limit: 1) {
            cached_tags
          }
        }
        """

        let payload: [String: Any] = [
            "query": gql,
            "variables": ["id": bookID]
        ]

        let json = try await performGraphQL(token: token, payload: payload)
        guard
            let data = json["data"] as? [String: Any],
            let books = data["books"] as? [[String: Any]],
            let first = books.first
        else {
            return nil
        }

        return primaryGenreFrom(first["cached_tags"])
    }

    private func primaryGenreFrom(_ cachedTags: Any?) -> String? {
        guard
            let tags = cachedTags as? [String: Any],
            let genres = tags["Genre"] as? [[String: Any]],
            !genres.isEmpty
        else {
            return nil
        }

        let topGenre = genres.max { lhs, rhs in
            intValue(lhs["count"]) ?? 0 < intValue(rhs["count"]) ?? 0
        }

        return topGenre.flatMap { stringValue($0["tag"]) }
    }

    private func performGraphQL(token: String, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            throw NSError(domain: "HardcoverBooksService", code: 1, userInfo: ["errors": errors])
        }

        return json
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool:
            return b
        case let n as NSNumber:
            return n.boolValue
        case let s as String:
            return ["true", "1", "yes"].contains(s.lowercased())
        default:
            return false
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let n as NSNumber:
            return n.stringValue
        default:
            return nil
        }
    }

    private func imageURL(from value: Any?) -> URL? {
        if let string = stringValue(value) {
            return URL(string: string)
        }

        if let image = value as? [String: Any],
           let urlString = stringValue(image["url"]) {
            return URL(string: urlString)
        }

        return nil
    }

    private var apiToken: String? {
        let envToken = ProcessInfo.processInfo.environment["HARDCOVER_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let envToken, !envToken.isEmpty { return envToken }

        let keys = Bundle.main.object(forInfoDictionaryKey: "APIKeys") as? [String: String]
        let explicit = keys?["Hardcover"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit, !explicit.isEmpty { return explicit }
        let legacy = keys?["Books"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let legacy, !legacy.isEmpty { return legacy }
        return nil
    }
}
