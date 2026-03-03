import Foundation

struct OpenLibraryBook: Identifiable, Hashable {
    let key: String
    let title: String
    let author: String?
    let year: Int?
    let coverID: Int?
    let subjects: [String]
    let isbn: String?
    let pageCount: Int?

    var id: String { key }

    var coverURL: URL? {
        guard let coverID else { return nil }
        return URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg")
    }
}

final class OpenLibraryService {
    static let shared = OpenLibraryService()

    private init() {}

    func searchBooks(query: String, limit: Int = 20) async throws -> [OpenLibraryBook] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 50))))
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data)
        return decoded.docs.map { doc in
            OpenLibraryBook(
                key: doc.key ?? UUID().uuidString,
                title: doc.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled",
                author: doc.authorName?.first,
                year: doc.firstPublishYear,
                coverID: doc.coverI,
                subjects: Array((doc.subject ?? []).prefix(8)),
                isbn: doc.isbn?.first,
                pageCount: doc.numberOfPagesMedian
            )
        }
    }
}

private struct OpenLibrarySearchResponse: Decodable {
    let docs: [OpenLibraryDoc]
}

private struct OpenLibraryDoc: Decodable {
    let key: String?
    let title: String?
    let authorName: [String]?
    let firstPublishYear: Int?
    let coverI: Int?
    let subject: [String]?
    let isbn: [String]?
    let numberOfPagesMedian: Int?

    enum CodingKeys: String, CodingKey {
        case key
        case title
        case authorName = "author_name"
        case firstPublishYear = "first_publish_year"
        case coverI = "cover_i"
        case subject
        case isbn
        case numberOfPagesMedian = "number_of_pages_median"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
