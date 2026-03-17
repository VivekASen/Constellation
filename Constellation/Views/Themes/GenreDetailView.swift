import SwiftUI
import SwiftData

struct GenreDetailView: View {
    @Query private var allMovies: [Movie]
    @Query private var allTVShows: [TVShow]
    @Query private var allBooks: [Book]

    @State private var isDeepDiveExpanded = false

    let genreName: String

    private var normalizedGenre: String {
        normalizeGenre(genreName)
    }

    private var displayGenre: String {
        normalizedGenre.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var moviesInGenre: [Movie] {
        allMovies.filter { normalizeGenres($0.genres).contains(normalizedGenre) }
    }

    private var showsInGenre: [TVShow] {
        allTVShows.filter { normalizeGenres($0.genres).contains(normalizedGenre) }
    }

    private var booksInGenre: [Book] {
        allBooks.filter { normalizeGenres($0.genres).contains(normalizedGenre) }
    }

    private var totalCount: Int {
        moviesInGenre.count + showsInGenre.count + booksInGenre.count
    }

    private var topLinkedThemes: [String] {
        let themes = moviesInGenre.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
            + showsInGenre.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
            + booksInGenre.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        let counts = Dictionary(grouping: themes, by: { $0 }).mapValues(\.count)
        return counts
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(5)
            .map(\.key)
    }

    private var yearRangeText: String {
        let years = (moviesInGenre.compactMap(\.year) + showsInGenre.compactMap(\.year) + booksInGenre.compactMap(\.year)).sorted()
        guard let first = years.first, let last = years.last else { return "Unknown span" }
        if first == last { return "\(first)" }
        return "\(first)-\(last)"
    }

    private var explanation: GenreExplanation {
        GenreDefinitionService.shared.explanation(
            for: normalizedGenre,
            connectedItemCount: totalCount,
            topThemes: topLinkedThemes
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayGenre)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("\(totalCount) connected items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    DisclosureGroup(isExpanded: $isDeepDiveExpanded) {
                        Text(deepDiveText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    } label: {
                        Text("Genre Deep Dive")
                            .font(.headline)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)

                if !topLinkedThemes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top Linked Themes")
                            .font(.headline)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(topLinkedThemes, id: \.self) { theme in
                                    NavigationLink(destination: ThemeDetailView(themeName: theme)) {
                                        Text(theme.replacingOccurrences(of: "-", with: " ").capitalized)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(Color.blue.opacity(0.14))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                if totalCount == 0 {
                    ContentUnavailableView(
                        "No Connected Items",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No movies, shows, or books currently map to this genre.")
                    )
                } else {
                    if !moviesInGenre.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Movies")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(moviesInGenre) { movie in
                                NavigationLink(destination: MovieDetailView(movie: movie)) {
                                    ThemeMovieCard(movie: movie)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !showsInGenre.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TV Shows")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(showsInGenre) { show in
                                NavigationLink(destination: TVShowDetailView(show: show)) {
                                    ThemeTVShowCard(show: show)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !booksInGenre.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Books")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(booksInGenre) { book in
                                NavigationLink(destination: BookDetailView(book: book)) {
                                    ThemeBookCard(book: book)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var deepDiveText: String {
        return """
        What it is: \(explanation.definition)

        Hallmarks: \(explanation.hallmarks)

        Historical context: \(explanation.historicalArc)

        Expert lens: \(explanation.analysisLens)

        In your library: this genre spans \(yearRangeText) across \(moviesInGenre.count) movies, \(showsInGenre.count) TV shows, and \(booksInGenre.count) books.
        """
    }

    private func normalizeGenres(_ rawGenres: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for genre in rawGenres {
            let normalized = normalizeGenre(genre)
            guard normalized.count >= 3 else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }

    private func normalizeGenre(_ raw: String) -> String {
        raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
