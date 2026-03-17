//
//  ContentView.swift
//  Constellation
//
//  Created by Vivek  Sen on 2/25/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Movie.dateAdded, order: .reverse) private var movies: [Movie]
    @Query(sort: \TVShow.dateAdded, order: .reverse) private var tvShows: [TVShow]
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @StateObject private var podcastPlayerStore = PodcastPlayerStore()
    @State private var themeBackfillTask: Task<Void, Never>?
    @State private var themeBackfillRunning = false

    private var themeBackfillFingerprint: String {
        movies.map(\.id).description
            + tvShows.map(\.id).description
            + books.map(\.id).description
            + movies.map(\.themes).description
            + tvShows.map(\.themes).description
            + books.map(\.themes).description
    }
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
            
            CollectionsView()
                .tabItem {
                    Label("Collections", systemImage: "square.stack.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(ConstellationPalette.accent)
        .environmentObject(podcastPlayerStore)
        .task(id: themeBackfillFingerprint) {
            scheduleThemeBackfill()
        }
        .onDisappear {
            themeBackfillTask?.cancel()
        }
    }

    private func scheduleThemeBackfill() {
        themeBackfillTask?.cancel()
        themeBackfillTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await runThemeBackfill()
        }
    }

    @MainActor
    private func runThemeBackfill() async {
        guard !themeBackfillRunning else { return }
        themeBackfillRunning = true
        DebugDiagnosticsRecorder.themeBackfillStarted()
        defer { themeBackfillRunning = false }

        var didUpdate = false

        for movie in movies.filter({ $0.themes.isEmpty }).prefix(2) {
            if Task.isCancelled { return }
            let generated = await ThemeExtractor.shared.extractThemes(from: movie)
            if !generated.isEmpty, movie.themes.isEmpty {
                movie.themes = generated
                didUpdate = true
                DebugDiagnosticsRecorder.movieThemeGenerated()
            }
        }

        for show in tvShows.filter({ $0.themes.isEmpty }).prefix(2) {
            if Task.isCancelled { return }
            let generated = await ThemeExtractor.shared.extractThemes(from: show)
            if !generated.isEmpty, show.themes.isEmpty {
                show.themes = generated
                didUpdate = true
                DebugDiagnosticsRecorder.tvThemeGenerated()
            }
        }

        for book in books.filter({ $0.themes.isEmpty }).prefix(2) {
            if Task.isCancelled { return }
            let generated = await ThemeExtractor.shared.extractThemes(from: book)
            if !generated.isEmpty, book.themes.isEmpty {
                book.themes = generated
                didUpdate = true
                DebugDiagnosticsRecorder.bookThemeGenerated()
            }
        }

        if didUpdate {
            try? modelContext.save()
            DebugDiagnosticsRecorder.themeBackfillUpdated()
        }
    }
}

private enum AddMediaSheet: String, Identifiable {
    case movie
    case tvShow
    case book
    case podcast
    
    var id: String { rawValue }
}

private enum DiscoverTargetFilter: String, CaseIterable, Identifiable {
    case all
    case movie
    case tv
    case book

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .movie: return "Movies"
        case .tv: return "TV"
        case .book: return "Books"
        }
    }
}

private enum DiscoverPathFilter: String, CaseIterable, Identifiable, Codable {
    case all
    case adaptation
    case sharedCreator
    case crossMedia
    case themeBridge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All Paths"
        case .adaptation: return "Adaptations"
        case .sharedCreator: return "Shared Creator"
        case .crossMedia: return "Cross-Media"
        case .themeBridge: return "Theme Bridge"
        }
    }
}

private enum DiscoverDepth: String, CaseIterable, Identifiable {
    case short
    case deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short: return "Short"
        case .deep: return "Deep"
        }
    }
}

private enum DiscoverSeedScope: String, CaseIterable, Identifiable {
    case strongest
    case recent
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strongest: return "Strongest"
        case .recent: return "Recent"
        case .all: return "All Library"
        }
    }
}

private enum DiscoverTargetType: String, Codable {
    case movie
    case tv
    case book
}

private struct DiscoverSeedItem {
    let title: String
    let targetType: DiscoverTargetType
    let authorOrCreator: String?
    let themes: [String]
    let genres: [String]
    let score: Double
}

private struct DiscoverRecommendation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let posterURL: URL?
    let targetType: DiscoverTargetType
    let pathFilter: DiscoverPathFilter
    let reason: String
    let path: [String]
    let confidence: Double
    let score: Double
    let movie: TMDBMovie?
    let tvShow: TMDBTVShow?
    let book: HardcoverBooksService.SearchBook?
}

private struct HomeSuggestionCacheItem: Codable {
    let id: String
    let title: String
    let subtitle: String
    let posterURL: String?
    let reason: String
    let mediaType: HomeSuggestionMediaType
    let score: Double
}

private struct DiscoverRecommendationCacheItem: Codable {
    let id: String
    let title: String
    let subtitle: String
    let posterURL: String?
    let targetType: DiscoverTargetType
    let pathFilter: DiscoverPathFilter
    let reason: String
    let path: [String]
    let confidence: Double
    let score: Double
}

private struct HomeSignalEntry {
    let title: String
    let mediaLabel: String
    let themes: [String]
}

private struct HomeCrossMediaInsight {
    let theme: String
    let entries: [HomeSignalEntry]
}

private enum RecommendationCacheStore {
    private static let defaults = UserDefaults.standard

    private struct Envelope<T: Codable>: Codable {
        let createdAt: Date
        let payload: T
    }

    static func load<T: Codable>(key: String, maxAge: TimeInterval, as type: T.Type) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data) else { return nil }
        guard Date().timeIntervalSince(envelope.createdAt) <= maxAge else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return envelope.payload
    }

    static func store<T: Codable>(key: String, payload: T) {
        let envelope = Envelope(createdAt: Date(), payload: payload)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: key)
    }

    static func makeKey(prefix: String, raw: String) -> String {
        "\(prefix).\(stableDigest(raw))"
    }

    private static func stableDigest(_ text: String) -> String {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

private actor BookRecommendationResolver {
    static let shared = BookRecommendationResolver()

    private var hardcoverCache: [String: [HardcoverBooksService.SearchBook]] = [:]
    private var openLibraryCache: [String: [OpenLibraryBook]] = [:]
    private var bestCache: [String: HardcoverBooksService.SearchBook] = [:]
    private var missCache: Set<String> = []

    func bestBookMatch(query: String) async -> HardcoverBooksService.SearchBook? {
        let top = await topBookMatches(query: query, limit: 1)
        return top.first
    }

    func topBookMatches(query: String, limit: Int = 5) async -> [HardcoverBooksService.SearchBook] {
        let key = normalizeQuery(query)
        guard !key.isEmpty else { return [] }
        if let cached = bestCache[key], limit <= 1 { return [cached] }
        if missCache.contains(key) { return [] }

        let variants = queryVariants(from: key).prefix(3)
        var candidates: [HardcoverBooksService.SearchBook] = []
        for variant in variants {
            candidates.append(contentsOf: await hardcoverSearchCached(query: variant, limit: 12))
        }

        let open = await openLibrarySearchCached(query: key, limit: 20)
        let expansionTerms = expansionTermsFromOpenLibrary(open, fallbackQuery: key).prefix(4)
        for term in expansionTerms {
            candidates.append(contentsOf: await hardcoverSearchCached(query: term, limit: 8))
        }

        let deduped = dedupeBooks(candidates)
        let sorted = deduped.sorted { lhs, rhs in
            bookScore(lhs, query: key) > bookScore(rhs, query: key)
        }

        let strict = sorted.filter(meetsStrictBookQuality)
        if !strict.isEmpty {
            bestCache[key] = strict[0]
            return Array(strict.prefix(max(1, limit)))
        }
        let medium = sorted.filter(meetsMediumBookQuality)
        if !medium.isEmpty {
            bestCache[key] = medium[0]
            return Array(medium.prefix(max(1, limit)))
        }

        let soft = sorted.filter(meetsSoftBookQuality)
        if !soft.isEmpty {
            bestCache[key] = soft[0]
            return Array(soft.prefix(max(1, limit)))
        }

        if let first = sorted.first {
            bestCache[key] = first
            return Array(sorted.prefix(max(1, limit)))
        }

        missCache.insert(key)
        return []
    }

    private func hardcoverSearchCached(query: String, limit: Int) async -> [HardcoverBooksService.SearchBook] {
        let key = "\(normalizeQuery(query))|\(limit)"
        if let cached = hardcoverCache[key] { return cached }
        let results = (try? await HardcoverBooksService.shared.searchBooks(query: query, limit: limit)) ?? []
        hardcoverCache[key] = results
        return results
    }

    private func openLibrarySearchCached(query: String, limit: Int) async -> [OpenLibraryBook] {
        let key = "\(normalizeQuery(query))|\(limit)"
        if let cached = openLibraryCache[key] { return cached }
        let results = (try? await OpenLibraryService.shared.searchBooks(query: query, limit: limit)) ?? []
        openLibraryCache[key] = results
        return results
    }

    private func queryVariants(from query: String) -> [String] {
        let tokens = tokenize(query)
        var variants: [String] = [query]
        if tokens.count >= 2 {
            variants.append(tokens.prefix(3).joined(separator: " "))
            variants.append(tokens.prefix(2).joined(separator: " "))
        }
        return Array(NSOrderedSet(array: variants)) as? [String] ?? variants
    }

    private func expansionTermsFromOpenLibrary(_ books: [OpenLibraryBook], fallbackQuery: String) -> [String] {
        var terms: [String] = []
        for author in books.compactMap(\.author).prefix(2) {
            terms.append(author)
        }
        let subjectTokens = books
            .flatMap(\.subjects)
            .flatMap(tokenize)
            .filter { !$0.isEmpty }
        let grouped = Dictionary(grouping: subjectTokens, by: { $0 }).mapValues(\.count)
        let topSubjects = grouped
            .sorted { $0.value > $1.value }
            .map(\.key)
            .filter { $0.count >= 5 }
            .prefix(3)
        terms.append(contentsOf: topSubjects)
        if terms.isEmpty { terms.append(fallbackQuery) }
        return Array(NSOrderedSet(array: terms)) as? [String] ?? terms
    }

    private func dedupeBooks(_ books: [HardcoverBooksService.SearchBook]) -> [HardcoverBooksService.SearchBook] {
        var byKey: [String: HardcoverBooksService.SearchBook] = [:]
        for book in books {
            let key = dedupeKey(for: book)
            if let current = byKey[key] {
                if bookScore(book, query: book.title) > bookScore(current, query: current.title) {
                    byKey[key] = book
                }
            } else {
                byKey[key] = book
            }
        }
        return Array(byKey.values)
    }

    private func dedupeKey(for book: HardcoverBooksService.SearchBook) -> String {
        let title = normalizeTitleForDedup(book.title)
        let author = normalizeQuery(book.author ?? "")
        return "\(title)|\(author)"
    }

    private func normalizeTitleForDedup(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"\b(vol(\.|ume)?|book|part)\s*\d+\b.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[,:-].*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func meetsStrictBookQuality(_ book: HardcoverBooksService.SearchBook) -> Bool {
        let rating = book.rating ?? 0
        let count = book.ratingCount ?? 0
        return (rating >= 4.0 && count >= 120) || (rating >= 4.2 && count >= 50)
    }

    private func meetsMediumBookQuality(_ book: HardcoverBooksService.SearchBook) -> Bool {
        let rating = book.rating ?? 0
        let count = book.ratingCount ?? 0
        return (rating >= 3.9 && count >= 60) || (rating >= 4.15 && count >= 20)
    }

    private func meetsSoftBookQuality(_ book: HardcoverBooksService.SearchBook) -> Bool {
        let rating = book.rating ?? 0
        let count = book.ratingCount ?? 0
        return (rating >= 3.75 && count >= 25) || (rating >= 4.1 && count >= 8)
    }

    private func bookScore(_ book: HardcoverBooksService.SearchBook, query: String) -> Double {
        let rating = min(max(book.rating ?? 0, 0), 5)
        let count = Double(max(book.ratingCount ?? 0, 0))
        let bayes = bayesian5(rating: rating, count: count)
        let pop = log10(count + 1)
        let title = jaccardSimilarity(tokenize(query), tokenize(book.title))
        let signalCorpus = ([book.primaryGenre ?? ""] + book.subjects + [book.description ?? ""]).joined(separator: " ")
        let signal = jaccardSimilarity(tokenize(query), tokenize(signalCorpus))
        let descriptionBoost = (book.description?.isEmpty == false) ? 0.18 : 0
        return bayes * 2.1 + pop * 0.7 + title * 2.8 + signal * 1.55 + descriptionBoost
    }

    private func bayesian5(rating: Double, count: Double) -> Double {
        let prior = 3.85
        let minVotes = 90.0
        guard count > 0 else { return prior }
        return (count / (count + minVotes)) * rating + (minVotes / (count + minVotes)) * prior
    }

    private func jaccardSimilarity(_ lhs: [String], _ rhs: [String]) -> Double {
        let l = Set(lhs)
        let r = Set(rhs)
        guard !l.isEmpty, !r.isEmpty else { return 0 }
        let i = l.intersection(r).count
        let u = l.union(r).count
        return u == 0 ? 0 : Double(i) / Double(u)
    }

    private func normalizeQuery(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenize(_ raw: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "from", "that", "this", "into", "about",
            "book", "novel", "volume", "vol", "part", "series"
        ]
        return normalizeQuery(raw)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}

struct DiscoverView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Movie.dateAdded, order: .reverse) private var movies: [Movie]
    @Query(sort: \TVShow.dateAdded, order: .reverse) private var tvShows: [TVShow]
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var targetFilter: DiscoverTargetFilter = .all
    @State private var pathFilter: DiscoverPathFilter = .all
    @State private var depth: DiscoverDepth = .short
    @State private var seedScope: DiscoverSeedScope = .strongest
    @State private var recommendations: [DiscoverRecommendation] = []
    @State private var isLoading = false
    @State private var refreshNonce: Int = 0
    @State private var sessionHiddenSuggestionIDs: Set<String> = []
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?
    @State private var movieMatchCache: [String: TMDBMovie] = [:]
    @State private var tvMatchCache: [String: TMDBTVShow] = [:]
    @State private var movieMissCache: Set<String> = []
    @State private var tvMissCache: Set<String> = []
    @State private var topUpInFlight = false
    @AppStorage("discover_hidden_ids_v1") private var hiddenSuggestionIDsRaw = ""
    @AppStorage("discover_feedback_type_v1") private var feedbackTypeRaw = ""
    @AppStorage("discover_feedback_path_v1") private var feedbackPathRaw = ""

    @State private var selectedMovie: TMDBMovie?
    @State private var selectedShow: TMDBTVShow?
    @State private var selectedBook: HardcoverBooksService.SearchBook?
    private let initialDiscoverLatencyBudget: TimeInterval = 2.4
    private let backgroundTopUpBudget: TimeInterval = 3.5

    private var refreshKey: String {
        targetFilter.rawValue
            + pathFilter.rawValue
            + depth.rawValue
            + seedScope.rawValue
            + String(refreshNonce)
    }

    private var libraryFingerprint: String {
        movies.map(\.id).description
            + tvShows.map(\.id).description
            + books.map(\.id).description
    }

    private var discoverCacheKey: String {
        RecommendationCacheStore.makeKey(prefix: "discover.paths.v4", raw: libraryFingerprint + refreshKey)
    }

    private var hiddenSuggestionIDs: Set<String> {
        Set(
            hiddenSuggestionIDsRaw
                .split(separator: "|")
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    private var visibleRecommendations: [DiscoverRecommendation] {
        recommendations.filter {
            !hiddenSuggestionIDs.contains($0.id)
                && !sessionHiddenSuggestionIDs.contains($0.id)
                && !isRecommendationAlreadyInLibrary($0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Discover")
                            .font(ConstellationTypeScale.heroTitle)
                            .foregroundStyle(.white)
                        Text("Find what to explore next through explainable paths.")
                            .font(ConstellationTypeScale.supporting)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(.horizontal, 16)

                    DiscoverFilterBar(
                        targetFilter: $targetFilter,
                        pathFilter: $pathFilter,
                        depth: $depth,
                        seedScope: $seedScope
                    )
                    .padding(.horizontal, 16)

                    if isLoading {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Building explainable recommendation paths...")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if visibleRecommendations.isEmpty {
                        ContentUnavailableView(
                            "No Discover Suggestions",
                            systemImage: "sparkles.rectangle.stack",
                            description: Text("Add more items or adjust filters to refresh Discover.")
                        )
                        .padding(.top, 30)
                        .tint(.white)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleRecommendations) { recommendation in
                                DiscoverPathCard(recommendation: recommendation) {
                                    openRecommendation(recommendation)
                                } onQuickAdd: {
                                    Task { await quickAddRecommendation(recommendation) }
                                } onLike: {
                                    reinforceRecommendation(recommendation)
                                } onDislike: {
                                    dampenRecommendation(recommendation)
                                } onHide: {
                                    hideSuggestionForSession(recommendation)
                                } onDismiss: {
                                    dismissRecommendation(recommendation)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(HomeStarfieldBackground().ignoresSafeArea())
            .refreshable {
                await refreshDiscoverRecommendations()
            }
            .task(id: refreshKey) {
                await loadDiscoverRecommendations()
            }
            .onChange(of: libraryFingerprint) { _, _ in
                Task { await pruneAndTopUpForLibraryChange() }
            }
            .sheet(item: $selectedMovie) { movie in
                MovieDetailSheet(movie: movie)
            }
            .sheet(item: $selectedShow) { show in
                TVShowDetailSheet(show: show)
            }
            .sheet(item: $selectedBook) { book in
                BookDetailSheet(book: book)
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func loadDiscoverRecommendations() async {
        guard !movies.isEmpty || !tvShows.isEmpty || !books.isEmpty else {
            recommendations = []
            return
        }

        if let cached: [DiscoverRecommendationCacheItem] = RecommendationCacheStore.load(
            key: discoverCacheKey,
            maxAge: 60 * 60 * 8,
            as: [DiscoverRecommendationCacheItem].self
        ) {
            let hydrated = cached.map { item in
                DiscoverRecommendation(
                    id: item.id,
                    title: item.title,
                    subtitle: item.subtitle,
                    posterURL: normalizedRemoteURL(from: item.posterURL),
                    targetType: item.targetType,
                    pathFilter: item.pathFilter,
                    reason: item.reason,
                    path: item.path,
                    confidence: item.confidence,
                    score: item.score,
                    movie: nil,
                    tvShow: nil,
                    book: nil
                )
            }
            let visibleCachedCount = hydrated.filter {
                !hiddenSuggestionIDs.contains($0.id) && !sessionHiddenSuggestionIDs.contains($0.id)
            }.count
            recommendations = hydrated
            if visibleCachedCount >= 15 {
                return
            }
            Task { await topUpDiscoverRecommendations() }
            return
        }

        isLoading = true
        defer { isLoading = false }

        let existingMovieIDs = Set(movies.compactMap(\.tmdbID))
        let existingTVIDs = Set(tvShows.compactMap(\.tmdbID))
        let existingBookTitles = Set(books.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let existingBookISBNs = Set(books.compactMap(\.isbn))
        let preferenceProfile = buildPreferenceProfile()
        let seedItems = Array(buildSeeds().prefix(seedScope == .all ? 8 : 6))
        let hopLimit = depth == .short ? 3 : 5

        var candidates: [DiscoverRecommendation] = []
        let deadline = Date().addingTimeInterval(initialDiscoverLatencyBudget)

        for seed in seedItems {
            if Date() > deadline, candidates.count >= 15 {
                break
            }
            if pathFilter == .all || pathFilter == .crossMedia {
                    let crossMediaResults = (try? await TasteDiveService.shared.similar(query: seed.title, limit: min(hopLimit + 4, 7))) ?? []
                for result in crossMediaResults.prefix(max(hopLimit + 1, 4)) {
                    if Date() > deadline, candidates.count >= 12 { break }
                    let parsedType = parseTasteDiveType(result.type)
                    switch parsedType {
                    case .movie:
                        if let movie = await bestMovieMatch(for: result.name), !existingMovieIDs.contains(movie.id) {
                            candidates.append(
                                buildDiscoverMovie(
                                    movie,
                                    filter: .crossMedia,
                                    reason: "Cross-media signal from \(seed.title)",
                                    path: [seed.title, "Cross-media signal", movie.title],
                                    confidence: 0.69,
                                    profile: preferenceProfile
                                )
                            )
                        }
                    case .tv:
                        if let show = await bestTVMatch(for: result.name), !existingTVIDs.contains(show.id) {
                            candidates.append(
                                buildDiscoverTV(
                                    show,
                                    filter: .crossMedia,
                                    reason: "Cross-media signal from \(seed.title)",
                                    path: [seed.title, "Cross-media signal", show.title],
                                    confidence: 0.69,
                                    profile: preferenceProfile
                                )
                            )
                        }
                    case .book:
                        if let book = await bestBookMatch(for: result.name) {
                            let normalized = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            if existingBookTitles.contains(normalized) { continue }
                            if let isbn = book.isbn, existingBookISBNs.contains(isbn) { continue }
                            candidates.append(
                                buildDiscoverBook(
                                    book,
                                    filter: .crossMedia,
                                    reason: "Cross-media signal from \(seed.title)",
                                    path: [seed.title, "Cross-media signal", book.title],
                                    confidence: 0.69,
                                    profile: preferenceProfile
                                )
                            )
                        }
                    case .unknown:
                        continue
                    }
                }
            }

            if pathFilter == .all || pathFilter == .adaptation {
                if Date() > deadline, candidates.count >= 12 { continue }
                if let sourceBook = await bestBookMatch(for: seed.title) {
                    guard isStrongSourceMaterialLink(seedTitle: seed.title, sourceTitle: sourceBook.title) else {
                        continue
                    }
                    guard isAdaptationSourceBookQuality(sourceBook) else {
                        continue
                    }
                    let normalized = sourceBook.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !existingBookTitles.contains(normalized),
                       !(sourceBook.isbn.map { existingBookISBNs.contains($0) } ?? false) {
                        candidates.append(
                            buildDiscoverBook(
                                sourceBook,
                                filter: .adaptation,
                                reason: "Likely source material path from \(seed.title)",
                                path: [seed.title, "Source material", sourceBook.title],
                                confidence: 0.76,
                                profile: preferenceProfile
                            )
                        )
                    }

                    if let movie = await bestMovieMatch(for: sourceBook.title),
                       !existingMovieIDs.contains(movie.id),
                       isStrongAdaptationLink(sourceTitle: sourceBook.title, targetTitle: movie.title) {
                        candidates.append(
                            buildDiscoverMovie(
                                movie,
                                filter: .adaptation,
                                reason: "Adaptation chain from \(seed.title)",
                                path: [seed.title, sourceBook.title, "Adaptation", movie.title],
                                confidence: 0.82,
                                profile: preferenceProfile
                            )
                        )
                    } else if let show = await bestTVMatch(for: sourceBook.title),
                              !existingTVIDs.contains(show.id),
                              isStrongAdaptationLink(sourceTitle: sourceBook.title, targetTitle: show.title) {
                        candidates.append(
                            buildDiscoverTV(
                                show,
                                filter: .adaptation,
                                reason: "Adaptation chain from \(seed.title)",
                                path: [seed.title, sourceBook.title, "Adaptation", show.title],
                                confidence: 0.8,
                                profile: preferenceProfile
                            )
                        )
                    }
                }
            }

            if (pathFilter == .all || pathFilter == .sharedCreator), let creator = seed.authorOrCreator, !creator.isEmpty {
                if Date() > deadline, candidates.count >= 12 { continue }
                let byCreator = (try? await HardcoverBooksService.shared.searchBooks(query: creator, limit: 8)) ?? []
                if let relatedBook = byCreator.first(where: {
                    creatorMatchConfidence(source: creator, candidate: $0.author) >= 0.9 &&
                    isAdaptationSourceBookQuality($0) &&
                    $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        != seed.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }) {
                    let creatorConfidence = creatorMatchConfidence(source: creator, candidate: relatedBook.author)
                    guard creatorConfidence >= 0.9 else { continue }
                    let normalized = relatedBook.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !existingBookTitles.contains(normalized),
                       !(relatedBook.isbn.map { existingBookISBNs.contains($0) } ?? false) {
                        candidates.append(
                            buildDiscoverBook(
                                relatedBook,
                                filter: .sharedCreator,
                                reason: "Shared creator path via \(creator)",
                                path: [seed.title, "Creator: \(creator)", relatedBook.title],
                                confidence: 0.78 * creatorConfidence,
                                profile: preferenceProfile
                            )
                        )
                    }

                    if let movie = await bestMovieMatch(for: relatedBook.title),
                       !existingMovieIDs.contains(movie.id),
                       isStrongAdaptationLink(sourceTitle: relatedBook.title, targetTitle: movie.title) {
                        candidates.append(
                            buildDiscoverMovie(
                                movie,
                                filter: .sharedCreator,
                                reason: "Creator-to-adaptation path via \(creator)",
                                path: [seed.title, "Creator: \(creator)", relatedBook.title, movie.title],
                                confidence: 0.84 * creatorConfidence,
                                profile: preferenceProfile
                            )
                        )
                    }
                }
            }

            if pathFilter == .all || pathFilter == .themeBridge {
                if Date() > deadline, candidates.count >= 12 { continue }
                if let bridge = strongestBridgePair(for: seed, profile: preferenceProfile) {
                    let tokenA = bridge.0
                    let tokenB = bridge.1
                    let bridgeQuery = "\(tokenA.replacingOccurrences(of: "-", with: " ")) \(tokenB.replacingOccurrences(of: "-", with: " "))"

                    let movieTheme = (try? await TasteDiveService.shared.similar(query: bridgeQuery, type: .movie, limit: 4)) ?? []
                    if let match = movieTheme.first,
                       let movie = await bestMovieMatch(for: match.name),
                       !existingMovieIDs.contains(movie.id),
                       passesThemeBridgeSemanticGuard(
                        seed: seed,
                        tokenA: tokenA,
                        tokenB: tokenB,
                        candidateTitle: movie.title,
                        candidateOverview: movie.overview
                       ) {
                        candidates.append(
                            buildDiscoverMovie(
                                movie,
                                filter: .themeBridge,
                                reason: "Bridge from \(seed.title): \(tokenA.replacingOccurrences(of: "-", with: " ")) + \(tokenB.replacingOccurrences(of: "-", with: " "))",
                                path: [seed.title, "Theme bridge: \(tokenA) + \(tokenB)", movie.title],
                                confidence: 0.74,
                                profile: preferenceProfile
                            )
                        )
                    }
                }
            }
        }

        var deduped: [String: DiscoverRecommendation] = [:]
        for candidate in candidates {
            if hiddenSuggestionIDs.contains(candidate.id) || sessionHiddenSuggestionIDs.contains(candidate.id) {
                continue
            }
            let key = canonicalRecommendationDedupKey(candidate)
            if let current = deduped[key], current.score >= candidate.score { continue }
            deduped[key] = candidate
        }

        var sortedAll = deduped.values.sorted { $0.score > $1.score }
        if targetFilter != .all {
            sortedAll = sortedAll.filter {
                switch targetFilter {
                case .all: return true
                case .movie: return $0.targetType == .movie
                case .tv: return $0.targetType == .tv
                case .book: return $0.targetType == .book
                }
            }
        }

        let minimumRecommendationCount = 15
        let connected = connectedCandidates(
            from: sortedAll.filter { meetsHardQualityFloor($0) },
            profile: preferenceProfile,
            minimumCount: minimumRecommendationCount
        )
        let preferred = connected
            .filter { meetsQualityBaseline($0) }
            .filter { meetsPathSpecificQuality($0) }
        var chosenPool = preferred.count >= minimumRecommendationCount ? preferred : connected

        let visibleFirst = chosenPool.filter { !hiddenSuggestionIDs.contains($0.id) && !sessionHiddenSuggestionIDs.contains($0.id) }
        if visibleFirst.count < minimumRecommendationCount {
            let fallback = await buildDiscoverFallbackCandidates(
                existingMovieIDs: existingMovieIDs,
                existingTVIDs: existingTVIDs,
                existingBookTitles: existingBookTitles,
                existingBookISBNs: existingBookISBNs,
                seedItems: seedItems,
                profile: preferenceProfile,
                deadline: Date().addingTimeInterval(backgroundTopUpBudget)
            )
            for candidate in fallback {
                if hiddenSuggestionIDs.contains(candidate.id) || sessionHiddenSuggestionIDs.contains(candidate.id) {
                    continue
                }
                let key = canonicalRecommendationDedupKey(candidate)
                if let current = deduped[key], current.score >= candidate.score { continue }
                deduped[key] = candidate
            }
            var merged = deduped.values.sorted { $0.score > $1.score }
            if targetFilter != .all {
                merged = merged.filter {
                    switch targetFilter {
                    case .all: return true
                    case .movie: return $0.targetType == .movie
                    case .tv: return $0.targetType == .tv
                    case .book: return $0.targetType == .book
                    }
                }
            }
            let mergedConnected = connectedCandidates(
                from: merged.filter { meetsHardQualityFloor($0) },
                profile: preferenceProfile,
                minimumCount: minimumRecommendationCount
            )
            let mergedPreferred = mergedConnected
                .filter { meetsQualityBaseline($0) }
                .filter { meetsPathSpecificQuality($0) }
            chosenPool = mergedPreferred.count >= minimumRecommendationCount ? mergedPreferred : mergedConnected
        }

        var ranked = diversifyDiscoverRecommendations(chosenPool, limit: 50)
        if targetFilter == .all || targetFilter == .book {
            ranked = await enforcePerTypeMinimums(
                in: ranked,
                minimumPerType: targetFilter == .book ? 15 : 5,
                existingMovieIDs: existingMovieIDs,
                existingTVIDs: existingTVIDs,
                existingBookTitles: existingBookTitles,
                existingBookISBNs: existingBookISBNs,
                seedItems: seedItems,
                profile: preferenceProfile
            )
        }
        let visible = ranked.filter { !hiddenSuggestionIDs.contains($0.id) && !sessionHiddenSuggestionIDs.contains($0.id) }
        let capped = Array(visible.prefix(40))
        recommendations = capped
        let cachePayload = capped.map { item in
            DiscoverRecommendationCacheItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                posterURL: item.posterURL?.absoluteString,
                targetType: item.targetType,
                pathFilter: item.pathFilter,
                reason: item.reason,
                path: item.path,
                confidence: item.confidence,
                score: item.score
            )
        }
        RecommendationCacheStore.store(key: discoverCacheKey, payload: cachePayload)
    }

private func reinforceRecommendation(_ recommendation: DiscoverRecommendation) {
    applyFeedback(targetType: recommendation.targetType, pathFilter: recommendation.pathFilter, delta: 1)
    showToast("Got it. We'll bias toward this style.")
    rerankRecommendationsByFeedback()
}

private func dampenRecommendation(_ recommendation: DiscoverRecommendation) {
    applyFeedback(targetType: recommendation.targetType, pathFilter: recommendation.pathFilter, delta: -1)
    showToast("Understood. We'll show less like this.")
    rerankRecommendationsByFeedback()
}

private func applyFeedback(targetType: DiscoverTargetType, pathFilter: DiscoverPathFilter, delta: Int) {
    var typeMap = decodeFeedbackMap(feedbackTypeRaw)
    var pathMap = decodeFeedbackMap(feedbackPathRaw)

    let typeKey = targetType.rawValue
    let pathKey = pathFilter.rawValue

    typeMap[typeKey] = min(8, max(-8, (typeMap[typeKey] ?? 0) + delta))
    pathMap[pathKey] = min(8, max(-8, (pathMap[pathKey] ?? 0) + delta))

    feedbackTypeRaw = encodeFeedbackMap(typeMap)
    feedbackPathRaw = encodeFeedbackMap(pathMap)
}

private func rerankRecommendationsByFeedback() {
    recommendations = recommendations.sorted {
        effectiveDiscoverScore($0) > effectiveDiscoverScore($1)
    }
}

private func effectiveDiscoverScore(_ recommendation: DiscoverRecommendation) -> Double {
    recommendation.score + feedbackAdjustment(targetType: recommendation.targetType, pathFilter: recommendation.pathFilter)
}

private func feedbackAdjustment(targetType: DiscoverTargetType, pathFilter: DiscoverPathFilter) -> Double {
    let typeMap = decodeFeedbackMap(feedbackTypeRaw)
    let pathMap = decodeFeedbackMap(feedbackPathRaw)
    let typeWeight = Double(typeMap[targetType.rawValue] ?? 0) * 0.38
    let pathWeight = Double(pathMap[pathFilter.rawValue] ?? 0) * 0.56
    return min(2.5, max(-2.5, typeWeight + pathWeight))
}

private func decodeFeedbackMap(_ raw: String) -> [String: Int] {
    guard !raw.isEmpty else { return [:] }
    var map: [String: Int] = [:]
    for part in raw.split(separator: "|") {
        let pieces = part.split(separator: "=", maxSplits: 1)
        guard pieces.count == 2 else { continue }
        let key = String(pieces[0])
        let value = Int(pieces[1]) ?? 0
        map[key] = value
    }
    return map
}

private func encodeFeedbackMap(_ map: [String: Int]) -> String {
    map.keys.sorted().compactMap { key in
        guard let value = map[key], value != 0 else { return nil }
        return "\(key)=\(value)"
    }.joined(separator: "|")
}

    private func dismissRecommendation(_ recommendation: DiscoverRecommendation) {
        var ids = hiddenSuggestionIDs
        ids.insert(recommendation.id)
        hiddenSuggestionIDsRaw = ids.sorted().joined(separator: "|")
        showToast("Got it. We won't suggest this again.")
    }

    private func hideSuggestionForSession(_ recommendation: DiscoverRecommendation) {
        sessionHiddenSuggestionIDs.insert(recommendation.id)
        showToast("Suggestion hidden for now.")
    }

    private func refreshDiscoverRecommendations() async {
        sessionHiddenSuggestionIDs.removeAll()
        movieMatchCache.removeAll()
        tvMatchCache.removeAll()
        movieMissCache.removeAll()
        tvMissCache.removeAll()
        refreshNonce += 1
        await loadDiscoverRecommendations()
    }

    private func pruneAndTopUpForLibraryChange() async {
        recommendations.removeAll(where: isRecommendationAlreadyInLibrary)
        await topUpDiscoverRecommendations()
    }

    private func isRecommendationAlreadyInLibrary(_ recommendation: DiscoverRecommendation) -> Bool {
        switch recommendation.targetType {
        case .movie:
            if let movieID = recommendation.movie?.id {
                return movies.contains(where: { $0.tmdbID == movieID })
            }
            if let id = Int(recommendation.id.replacingOccurrences(of: "movie-", with: "")) {
                return movies.contains(where: { $0.tmdbID == id })
            }
            let normalized = recommendation.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return movies.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
        case .tv:
            if let showID = recommendation.tvShow?.id {
                return tvShows.contains(where: { $0.tmdbID == showID })
            }
            if let id = Int(recommendation.id.replacingOccurrences(of: "tv-", with: "")) {
                return tvShows.contains(where: { $0.tmdbID == id })
            }
            let normalized = recommendation.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return tvShows.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
        case .book:
            if let isbn = recommendation.book?.isbn, !isbn.isEmpty,
               books.contains(where: { $0.isbn == isbn }) {
                return true
            }
            let normalized = recommendation.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return books.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
        }
    }

    private func quickAddRecommendation(_ recommendation: DiscoverRecommendation) async {
        switch recommendation.targetType {
        case .movie:
            let movie: TMDBMovie?
            if let existing = recommendation.movie {
                movie = existing
            } else {
                movie = await bestMovieMatch(for: recommendation.title)
            }
            guard let movie else {
                showToast("Couldn't quick-add this movie.")
                return
            }
            guard !movies.contains(where: { $0.tmdbID == movie.id }) else {
                hideSuggestionForSession(recommendation)
                showToast("Already in your library.")
                await topUpDiscoverRecommendations()
                return
            }
            let item = Movie(
                title: movie.title,
                year: movie.year,
                posterURL: movie.posterURL?.absoluteString,
                overview: movie.overview,
                publicRating: movie.voteAverage,
                publicRatingCount: movie.voteCount,
                tmdbID: movie.id
            )
            modelContext.insert(item)
            try? modelContext.save()
            hideSuggestionForSession(recommendation)
            showToast("Added movie to library.")
            await topUpDiscoverRecommendations()
        case .tv:
            let show: TMDBTVShow?
            if let existing = recommendation.tvShow {
                show = existing
            } else {
                show = await bestTVMatch(for: recommendation.title)
            }
            guard let show else {
                showToast("Couldn't quick-add this TV show.")
                return
            }
            guard !tvShows.contains(where: { $0.tmdbID == show.id }) else {
                hideSuggestionForSession(recommendation)
                showToast("Already in your library.")
                await topUpDiscoverRecommendations()
                return
            }
            let item = TVShow(
                title: show.title,
                year: show.year,
                posterURL: show.posterURL?.absoluteString,
                overview: show.overview,
                publicRating: show.voteAverage,
                publicRatingCount: show.voteCount,
                tmdbID: show.id
            )
            modelContext.insert(item)
            try? modelContext.save()
            hideSuggestionForSession(recommendation)
            showToast("Added TV show to library.")
            await topUpDiscoverRecommendations()
        case .book:
            let book: HardcoverBooksService.SearchBook?
            if let existing = recommendation.book {
                book = existing
            } else {
                book = await bestBookMatch(for: recommendation.title)
            }
            guard let book else {
                showToast("Couldn't quick-add this book.")
                return
            }
            let normalizedTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let duplicate = books.contains { existing in
                if let isbn = book.isbn, !isbn.isEmpty, existing.isbn == isbn { return true }
                return existing.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
            }
            guard !duplicate else {
                hideSuggestionForSession(recommendation)
                showToast("Already in your library.")
                await topUpDiscoverRecommendations()
                return
            }
            let item = Book(
                title: book.title,
                year: book.year,
                author: book.author,
                coverURL: book.coverURL?.absoluteString,
                overview: book.description,
                genres: book.primaryGenre.map { [$0] } ?? book.subjects,
                pageCount: book.pageCount,
                rating: book.rating,
                ratingCount: book.ratingCount,
                isbn: book.isbn,
                infoURL: book.slug.flatMap { "https://hardcover.app/books/\($0)" },
                hasAudiobook: book.hasAudiobook,
                hasEbook: book.hasEbook
            )
            modelContext.insert(item)
            try? modelContext.save()
            hideSuggestionForSession(recommendation)
            showToast("Added book to library.")
            await topUpDiscoverRecommendations()
        }
    }

    private func topUpDiscoverRecommendations(minimumVisible: Int = 15) async {
        guard !topUpInFlight else { return }
        topUpInFlight = true
        defer { topUpInFlight = false }

        let currentVisible = recommendations.filter {
            !hiddenSuggestionIDs.contains($0.id) && !sessionHiddenSuggestionIDs.contains($0.id)
        }.count
        guard currentVisible < minimumVisible else { return }

        let existingMovieIDs = Set(movies.compactMap(\.tmdbID))
        let existingTVIDs = Set(tvShows.compactMap(\.tmdbID))
        let existingBookTitles = Set(books.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let existingBookISBNs = Set(books.compactMap(\.isbn))
        let preferenceProfile = buildPreferenceProfile()
        let seedItems = Array(buildSeeds().prefix(seedScope == .all ? 8 : 6))

        let fallback = await buildDiscoverFallbackCandidates(
            existingMovieIDs: existingMovieIDs,
            existingTVIDs: existingTVIDs,
            existingBookTitles: existingBookTitles,
            existingBookISBNs: existingBookISBNs,
            seedItems: seedItems,
            profile: preferenceProfile,
            deadline: Date().addingTimeInterval(backgroundTopUpBudget)
        )

        var byKey: [String: DiscoverRecommendation] = [:]
        for item in recommendations {
            byKey[canonicalRecommendationDedupKey(item)] = item
        }
        for item in fallback {
            if hiddenSuggestionIDs.contains(item.id) || sessionHiddenSuggestionIDs.contains(item.id) { continue }
            let key = canonicalRecommendationDedupKey(item)
            if let current = byKey[key], current.score >= item.score { continue }
            byKey[key] = item
        }

        var ranked = diversifyDiscoverRecommendations(
            connectedCandidates(
                from: byKey.values
                    .filter { meetsHardQualityFloor($0) }
                    .sorted { $0.score > $1.score },
                profile: preferenceProfile,
                minimumCount: minimumVisible
            ),
            limit: 50
        )
        if targetFilter == .all || targetFilter == .book {
            ranked = await enforcePerTypeMinimums(
                in: ranked,
                minimumPerType: targetFilter == .book ? 15 : 5,
                existingMovieIDs: existingMovieIDs,
                existingTVIDs: existingTVIDs,
                existingBookTitles: existingBookTitles,
                existingBookISBNs: existingBookISBNs,
                seedItems: seedItems,
                profile: preferenceProfile
            )
        }
        recommendations = ranked
    }

    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            toastMessage = message
        }
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                toastMessage = nil
            }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func canonicalCreatorKey(_ value: String?) -> String {
        guard let value else { return "" }
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        return normalized.replacingOccurrences(of: " ", with: "-")
    }

    private func creatorAliasMap() -> [String: Set<String>] {
        [
            "j-k-rowling": ["joanne-rowling", "robert-galbraith"],
            "stephen-king": ["richard-bachman"]
        ]
    }

    private func creatorMatchConfidence(source: String?, candidate: String?) -> Double {
        let sourceKey = canonicalCreatorKey(source)
        let candidateKey = canonicalCreatorKey(candidate)
        guard !sourceKey.isEmpty, !candidateKey.isEmpty else { return 0 }
        if sourceKey == candidateKey { return 1.0 }

        let aliases = creatorAliasMap()
        if aliases[sourceKey]?.contains(candidateKey) == true || aliases[candidateKey]?.contains(sourceKey) == true {
            return 0.93
        }
        return 0
    }

    private func canonicalTitleTokens(_ value: String) -> Set<String> {
        let cleaned = value
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
        let parts = cleaned.split(separator: " ")
        var tokens: Set<String> = []
        tokens.reserveCapacity(parts.count)
        for part in parts {
            let token = String(part)
            guard token.count > 2 else { continue }
            guard token != "the", token != "and", token != "for" else { continue }
            tokens.insert(token)
        }
        return tokens
    }

    private func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = canonicalTitleTokens(lhs)
        let right = canonicalTitleTokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private func isStrongSourceMaterialLink(seedTitle: String, sourceTitle: String) -> Bool {
        titleSimilarity(seedTitle, sourceTitle) >= 0.46
    }

    private func isStrongAdaptationLink(sourceTitle: String, targetTitle: String) -> Bool {
        titleSimilarity(sourceTitle, targetTitle) >= 0.46
    }

    private func isAdaptationSourceBookQuality(_ book: HardcoverBooksService.SearchBook) -> Bool {
        let rating = book.rating ?? 0
        let count = book.ratingCount ?? 0
        return (rating >= 4.0 && count >= 120) || (rating >= 4.2 && count >= 50)
    }

    private func meetsHardQualityFloor(_ recommendation: DiscoverRecommendation) -> Bool {
        let (rating, count) = ratingAndCount(for: recommendation)
        switch recommendation.targetType {
        case .movie:
            return (rating >= 6.2 && count >= 80) || (rating >= 7.2 && count >= 20)
        case .tv:
            return (rating >= 6.3 && count >= 70) || (rating >= 7.2 && count >= 20)
        case .book:
            return (rating >= 3.95 && count >= 60) || (rating >= 4.2 && count >= 20)
        }
    }

    private func meetsPathSpecificQuality(_ recommendation: DiscoverRecommendation) -> Bool {
        guard recommendation.pathFilter == .adaptation || recommendation.pathFilter == .sharedCreator else {
            return true
        }
        if recommendation.targetType == .book {
            let (rating, count) = ratingAndCount(for: recommendation)
            return rating >= 4.0 && count >= 120
        }
        return true
    }

    private func canonicalSeriesTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: #"\b(vol(\.|ume)?|book|part)\s*\d+\b.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[,:-].*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func canonicalRecommendationDedupKey(_ recommendation: DiscoverRecommendation) -> String {
        let base: String
        switch recommendation.targetType {
        case .movie: base = "movie"
        case .tv: base = "tv"
        case .book: base = "book"
        }
        if recommendation.targetType == .book && recommendation.pathFilter == .themeBridge {
            return "\(base)-theme-\(canonicalSeriesTitle(recommendation.title))"
        }
        return recommendation.id
    }

    private func meetsQualityBaseline(_ recommendation: DiscoverRecommendation) -> Bool {
        let (rating, count) = ratingAndCount(for: recommendation)
        switch recommendation.targetType {
        case .movie:
            return (rating >= 7.0 && count >= 160) || (rating >= 6.5 && count >= 1600) || (rating >= 8.1 && count >= 70)
        case .tv:
            return (rating >= 7.1 && count >= 130) || (rating >= 6.6 && count >= 1300) || (rating >= 8.1 && count >= 55)
        case .book:
            return (rating >= 4.0 && count >= 90) || (rating >= 3.8 && count >= 600) || (rating >= 4.35 && count >= 30)
        }
    }

    private func ratingAndCount(for recommendation: DiscoverRecommendation) -> (Double, Int) {
        switch recommendation.targetType {
        case .movie:
            return (recommendation.movie?.voteAverage ?? 0, recommendation.movie?.voteCount ?? 0)
        case .tv:
            return (recommendation.tvShow?.voteAverage ?? 0, recommendation.tvShow?.voteCount ?? 0)
        case .book:
            return (recommendation.book?.rating ?? 0, recommendation.book?.ratingCount ?? 0)
        }
    }

    private func minimumCountFloor(for type: DiscoverTargetType) -> Int {
        switch type {
        case .movie, .tv: return 30
        case .book: return 15
        }
    }

    private var broadBridgeTerms: Set<String> {
        [
            "family", "adventure", "drama", "action", "comedy", "romance", "thriller",
            "fantasy", "sci", "science", "fiction", "mystery", "story", "life"
        ]
    }

    private func normalizeBridgeToken(_ value: String) -> [String] {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                token.count >= 4 && !broadBridgeTerms.contains(token)
            }
    }

    private func strongestBridgePair(for seed: DiscoverSeedItem, profile: [String: Double]) -> (String, String)? {
        var weighted: [String: Double] = [:]
        for raw in seed.themes + seed.genres {
            for token in normalizeBridgeToken(raw) {
                weighted[token, default: 0] += profile[token, default: 0] + 1.0
            }
        }
        let sorted = weighted.sorted { $0.value > $1.value }.map(\.key)
        guard sorted.count >= 2 else { return nil }
        return (sorted[0], sorted[1])
    }

    private func seedContextTokens(for seed: DiscoverSeedItem, excluding bridgeTokens: Set<String>) -> Set<String> {
        let titleTokens = canonicalTitleTokens(seed.title).filter { !$0.isEmpty }
        let conceptTokens = Set((seed.themes + seed.genres).flatMap(normalizeBridgeToken))
        return Set(titleTokens).union(conceptTokens).subtracting(bridgeTokens)
    }

    private func passesThemeBridgeSemanticGuard(
        seed: DiscoverSeedItem,
        tokenA: String,
        tokenB: String,
        candidateTitle: String,
        candidateOverview: String?,
        candidateExtras: [String] = []
    ) -> Bool {
        let combinedText = ([candidateTitle, candidateOverview ?? ""] + candidateExtras).joined(separator: " ").lowercased()
        let bridgeSet: Set<String> = [tokenA.lowercased(), tokenB.lowercased()]
        let hasA = combinedText.contains(tokenA.lowercased())
        let hasB = combinedText.contains(tokenB.lowercased())
        guard hasA || hasB else { return false }
        let contextTokens = seedContextTokens(for: seed, excluding: bridgeSet)
        let contextHit = contextTokens.contains { combinedText.contains($0) }
        return (hasA && hasB && contextHit) || ((hasA || hasB) && contextHit)
    }

    private func bestSeedAnchor(
        termA: String,
        termB: String,
        seedItems: [DiscoverSeedItem]
    ) -> DiscoverSeedItem? {
        seedItems
            .map { seed -> (DiscoverSeedItem, Double) in
                let tokens = Set((seed.themes + seed.genres).flatMap(normalizeBridgeToken))
                let score = (tokens.contains(termA) ? 1.2 : 0) + (tokens.contains(termB) ? 1.2 : 0)
                return (seed, score + seed.score * 0.01)
            }
            .sorted { $0.1 > $1.1 }
            .first?.0
    }

    private func pathReliabilityBoost(_ filter: DiscoverPathFilter) -> Double {
        switch filter {
        case .all: return 0.0
        case .adaptation: return 1.0
        case .sharedCreator: return 0.95
        case .themeBridge: return 0.55
        case .crossMedia: return 0.7
        }
    }

    private func sanitizedDiscoverPath(_ path: [String]) -> [String] {
        var output: [String] = []
        output.reserveCapacity(path.count)
        for node in path {
            let trimmed = node.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let last = output.last, last.caseInsensitiveCompare(trimmed) == .orderedSame {
                continue
            }
            output.append(trimmed)
        }
        return output
    }

    private func recommendationText(_ recommendation: DiscoverRecommendation) -> String {
        let overview: String
        switch recommendation.targetType {
        case .movie:
            overview = recommendation.movie?.overview ?? ""
        case .tv:
            overview = recommendation.tvShow?.overview ?? ""
        case .book:
            overview = recommendation.book?.description ?? ""
        }
        return (recommendation.title + " " + overview + " " + recommendation.path.joined(separator: " ")).lowercased()
    }

    private func isConnectedRecommendation(
        _ recommendation: DiscoverRecommendation,
        profile: [String: Double],
        relaxedBy: Double = 0
    ) -> Bool {
        if profile.isEmpty { return true }
        let text = recommendationText(recommendation)
        let topSignals = profile
            .sorted { $0.value > $1.value }
            .prefix(24)
        let profileScore = topSignals.reduce(0.0) { partial, pair in
            text.contains(pair.key) ? partial + min(pair.value, 3.0) : partial
        }
        let pathBonus: Double = {
            switch recommendation.pathFilter {
            case .adaptation: return 1.4
            case .sharedCreator: return 1.2
            case .themeBridge: return 1.1
            case .crossMedia: return 0.8
            case .all: return 0.5
            }
        }()
        if recommendation.pathFilter == .themeBridge {
            let compoundBridge = recommendation.path.contains { $0.contains("+") }
            return compoundBridge && (profileScore + pathBonus) >= max(1.2, 1.95 - relaxedBy)
        }
        return (profileScore + pathBonus) >= max(1.05, 1.6 - relaxedBy)
    }

    private func connectedCandidates(
        from candidates: [DiscoverRecommendation],
        profile: [String: Double],
        minimumCount: Int
    ) -> [DiscoverRecommendation] {
        let strict = candidates.filter { isConnectedRecommendation($0, profile: profile, relaxedBy: 0) }
        if strict.count >= minimumCount { return strict }

        let medium = candidates.filter { isConnectedRecommendation($0, profile: profile, relaxedBy: 0.3) }
        if medium.count >= max(8, minimumCount / 2) { return medium }

        let relaxed = candidates.filter { isConnectedRecommendation($0, profile: profile, relaxedBy: 0.55) }
        return relaxed
    }

    private func visibleTypeCounts(in recommendations: [DiscoverRecommendation]) -> [DiscoverTargetType: Int] {
        recommendations.reduce(into: [DiscoverTargetType: Int]()) { partial, item in
            guard !hiddenSuggestionIDs.contains(item.id), !sessionHiddenSuggestionIDs.contains(item.id) else { return }
            partial[item.targetType, default: 0] += 1
        }
    }

    private func bestAnchorTitle(for signal: String, seedItems: [DiscoverSeedItem]) -> String {
        seedItems
            .map { seed -> (String, Double) in
                let haystack = ((seed.themes + seed.genres).joined(separator: " ") + " " + seed.title).lowercased()
                let signalScore = haystack.contains(signal.lowercased()) ? 1.0 : 0.0
                return (seed.title, signalScore + seed.score * 0.01)
            }
            .sorted { $0.1 > $1.1 }
            .first?.0 ?? "Your library"
    }

    private func enforcePerTypeMinimums(
        in ranked: [DiscoverRecommendation],
        minimumPerType: Int,
        existingMovieIDs: Set<Int>,
        existingTVIDs: Set<Int>,
        existingBookTitles: Set<String>,
        existingBookISBNs: Set<String>,
        seedItems: [DiscoverSeedItem],
        profile: [String: Double]
    ) async -> [DiscoverRecommendation] {
        var working = ranked
        var keySet = Set(working.map(canonicalRecommendationDedupKey))
        var counts = visibleTypeCounts(in: working)
        let includeAllTypes = targetFilter == .all
        let signals = profile
            .sorted { $0.value > $1.value }
            .map(\.key)
            .filter { $0.count >= 4 }
            .prefix(8)
        let signalList = Array(signals)

        func accept(_ rec: DiscoverRecommendation) -> Bool {
            if hiddenSuggestionIDs.contains(rec.id) || sessionHiddenSuggestionIDs.contains(rec.id) { return false }
            if !meetsHardQualityFloor(rec) { return false }
            if !isConnectedRecommendation(rec, profile: profile, relaxedBy: 0.35) { return false }
            let key = canonicalRecommendationDedupKey(rec)
            if keySet.contains(key) { return false }
            keySet.insert(key)
            working.append(rec)
            counts[rec.targetType, default: 0] += 1
            return true
        }

        func acceptBookSoft(_ rec: DiscoverRecommendation) -> Bool {
            guard rec.targetType == .book else { return false }
            if hiddenSuggestionIDs.contains(rec.id) || sessionHiddenSuggestionIDs.contains(rec.id) { return false }
            let rating = rec.book?.rating ?? 0
            let count = rec.book?.ratingCount ?? 0
            let softFloor = (rating >= 3.75 && count >= 25) || (rating >= 4.1 && count >= 8)
            if !softFloor { return false }
            if !isConnectedRecommendation(rec, profile: profile, relaxedBy: 0.75) { return false }
            let key = canonicalRecommendationDedupKey(rec)
            if keySet.contains(key) { return false }
            keySet.insert(key)
            working.append(rec)
            counts[rec.targetType, default: 0] += 1
            return true
        }

        if (counts[.book] ?? 0) < minimumPerType {
            for signal in signalList {
                if (counts[.book] ?? 0) >= minimumPerType { break }
                let anchor = bestAnchorTitle(for: signal, seedItems: seedItems)
                let books = await BookRecommendationResolver.shared.topBookMatches(query: signal, limit: 8)
                for book in books {
                    let normalized = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if existingBookTitles.contains(normalized) { continue }
                    if let isbn = book.isbn, existingBookISBNs.contains(isbn) { continue }
                    let rec = buildDiscoverBook(
                        book,
                        filter: .crossMedia,
                        reason: "Strong book signal from \(anchor) via \(signal)",
                        path: [anchor, "Signal: \(signal)", book.title],
                        confidence: 0.67,
                        profile: profile
                    )
                    _ = accept(rec)
                    if (counts[.book] ?? 0) >= minimumPerType { break }
                }
            }
        }

        if includeAllTypes && (counts[.movie] ?? 0) < minimumPerType {
            for signal in signalList {
                if (counts[.movie] ?? 0) >= minimumPerType { break }
                let anchor = bestAnchorTitle(for: signal, seedItems: seedItems)
                let results = ((try? await TMDBService.shared.searchMovies(query: signal, page: 1)) ?? [])
                    + ((try? await TMDBService.shared.searchMovies(query: signal, page: 2)) ?? [])
                for movie in results.prefix(8) where !existingMovieIDs.contains(movie.id) {
                    let rec = buildDiscoverMovie(
                        movie,
                        filter: .crossMedia,
                        reason: "Strong movie signal from \(anchor) via \(signal)",
                        path: [anchor, "Signal: \(signal)", movie.title],
                        confidence: 0.66,
                        profile: profile
                    )
                    _ = accept(rec)
                    if (counts[.movie] ?? 0) >= minimumPerType { break }
                }
            }
        }

        if includeAllTypes && (counts[.tv] ?? 0) < minimumPerType {
            for signal in signalList {
                if (counts[.tv] ?? 0) >= minimumPerType { break }
                let anchor = bestAnchorTitle(for: signal, seedItems: seedItems)
                let results = ((try? await TMDBService.shared.searchTVShows(query: signal, page: 1)) ?? [])
                    + ((try? await TMDBService.shared.searchTVShows(query: signal, page: 2)) ?? [])
                for show in results.prefix(8) where !existingTVIDs.contains(show.id) {
                    let rec = buildDiscoverTV(
                        show,
                        filter: .crossMedia,
                        reason: "Strong show signal from \(anchor) via \(signal)",
                        path: [anchor, "Signal: \(signal)", show.title],
                        confidence: 0.66,
                        profile: profile
                    )
                    _ = accept(rec)
                    if (counts[.tv] ?? 0) >= minimumPerType { break }
                }
            }
        }

        if (counts[.book] ?? 0) < minimumPerType {
            let bookTopUpTerms = Array(
                NSOrderedSet(array: signalList + seedItems.map(\.title) + seedItems.compactMap(\.authorOrCreator))
            ) as? [String] ?? signalList
            for term in bookTopUpTerms {
                if (counts[.book] ?? 0) >= minimumPerType { break }
                let cleaned = term.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                let anchor = bestAnchorTitle(for: cleaned, seedItems: seedItems)
                let books = await BookRecommendationResolver.shared.topBookMatches(query: cleaned, limit: 10)
                for book in books {
                    let normalized = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if existingBookTitles.contains(normalized) { continue }
                    if let isbn = book.isbn, existingBookISBNs.contains(isbn) { continue }
                    let rec = buildDiscoverBook(
                        book,
                        filter: .crossMedia,
                        reason: "Book path from \(anchor) via \(cleaned)",
                        path: [anchor, "Book signal: \(cleaned)", book.title],
                        confidence: 0.62,
                        profile: profile
                    )
                    _ = accept(rec) || acceptBookSoft(rec)
                    if (counts[.book] ?? 0) >= minimumPerType { break }
                }
            }
        }

        return diversifyDiscoverRecommendations(working, limit: 60)
    }

    private func diversifyDiscoverRecommendations(_ candidates: [DiscoverRecommendation], limit: Int) -> [DiscoverRecommendation] {
        let sorted = candidates.sorted { $0.score > $1.score }
        guard !sorted.isEmpty else { return [] }

        var selected: [DiscoverRecommendation] = []
        var backlog: [DiscoverRecommendation] = []
        var typeCounts: [DiscoverTargetType: Int] = [.movie: 0, .tv: 0, .book: 0]
        var pathCounts: [DiscoverPathFilter: Int] = [:]
        let typeCap = max(4, limit / 2)
        let pathCap = max(4, limit / 2)

        for candidate in sorted {
            if selected.count >= limit { break }
            let typeCount = typeCounts[candidate.targetType, default: 0]
            let pathCount = pathCounts[candidate.pathFilter, default: 0]
            let canTake = typeCount < typeCap && pathCount < pathCap
            if canTake || selected.count < 8 {
                selected.append(candidate)
                typeCounts[candidate.targetType, default: 0] += 1
                pathCounts[candidate.pathFilter, default: 0] += 1
            } else {
                backlog.append(candidate)
            }
        }

        if selected.count < limit {
            for candidate in backlog where selected.count < limit {
                selected.append(candidate)
            }
        }
        return selected
    }

    private func buildSeeds() -> [DiscoverSeedItem] {
        let movieSeeds = movies.map { movie in
            DiscoverSeedItem(
                title: movie.title,
                targetType: .movie,
                authorOrCreator: movie.director,
                themes: movie.themes,
                genres: movie.genres,
                score: (movie.rating ?? 0) * 1.8 + (movie.publicRating ?? 0) * 0.8 + (movie.watchedDate != nil ? 1.2 : 0)
            )
        }
        let tvSeeds = tvShows.map { show in
            DiscoverSeedItem(
                title: show.title,
                targetType: .tv,
                authorOrCreator: show.creator,
                themes: show.themes,
                genres: show.genres,
                score: (show.rating ?? 0) * 1.8 + (show.publicRating ?? 0) * 0.8 + (show.watchedDate != nil ? 1.2 : 0)
            )
        }
        let bookSeeds = books.map { book in
            DiscoverSeedItem(
                title: book.title,
                targetType: .book,
                authorOrCreator: book.author,
                themes: book.themes,
                genres: book.genres,
                score: (book.rating ?? 0) * 1.8 + (book.rating ?? 0) * 0.7 + (book.watchedDate != nil ? 1.2 : 0)
            )
        }

        let combined = (movieSeeds + tvSeeds + bookSeeds)
        switch seedScope {
        case .all:
            return combined.sorted { $0.score > $1.score }
        case .recent:
            return Array(combined.prefix(8))
        case .strongest:
            return combined.sorted { $0.score > $1.score }
        }
    }

    private func buildPreferenceProfile() -> [String: Double] {
        var profile: [String: Double] = [:]
        func add(_ terms: [String], weight: Double) {
            for term in terms {
                for token in term
                    .lowercased()
                    .replacingOccurrences(of: "-", with: " ")
                    .split(separator: " ")
                    .map(String.init)
                    .filter({ $0.count > 2 }) {
                        profile[token, default: 0] += weight
                    }
            }
        }

        for movie in movies { add(movie.themes + movie.genres, weight: movie.watchedDate != nil ? 2.0 : 1.0) }
        for show in tvShows { add(show.themes + show.genres, weight: show.watchedDate != nil ? 2.0 : 1.0) }
        for book in books { add(book.themes + book.genres, weight: book.watchedDate != nil ? 2.0 : 1.0) }
        return profile
    }

    private func discoverScore(
        targetType: DiscoverTargetType,
        title: String,
        overview: String?,
        rating: Double?,
        ratingCount: Int?,
        pathFilter: DiscoverPathFilter,
        confidence: Double,
        profile: [String: Double]
    ) -> Double {
        let count = Double(max(ratingCount ?? 1, 1))
        let weightedQuality = bayesianWeightedRating(
            targetType: targetType,
            rating: rating ?? 0,
            ratingCount: ratingCount ?? 0
        )
        let popularity = log10(count) * 2.45
        let socialProof = min(count / 2200.0, 2.2)
        let prestigeBoost = (weightedQuality >= 8.0 && count >= 5000) ? 1.45 : 0
        let text = (title + " " + (overview ?? "")).lowercased()
        let profileBoost = profile
            .filter { text.contains($0.key) }
            .reduce(0.0) { $0 + $1.value * 0.08 }
        let reliability = pathReliabilityBoost(pathFilter)
        let feedback = feedbackAdjustment(targetType: targetType, pathFilter: pathFilter)
        let floorPenalty = count < Double(minimumCountFloor(for: targetType)) ? -2.7 : 0
        return weightedQuality * 1.85 + popularity + socialProof + prestigeBoost + confidence * 2.4 + min(profileBoost, 2.2) + reliability + feedback + floorPenalty
    }

    private func bayesianWeightedRating(targetType: DiscoverTargetType, rating: Double, ratingCount: Int) -> Double {
        let votes = max(ratingCount, 0)
        let v = Double(votes)

        let normalizedRating: Double
        let priorMean: Double
        let minVotes: Double

        switch targetType {
        case .movie, .tv:
            // TMDB-style ratings are on a 10-point scale.
            normalizedRating = min(max(rating, 0), 10)
            priorMean = 6.8
            minVotes = 220
        case .book:
            // Hardcover ratings are on a 5-point scale; normalize to 10.
            normalizedRating = min(max(rating, 0), 5) * 2.0
            priorMean = 7.4
            minVotes = 120
        }

        guard v > 0 else { return priorMean }
        return (v / (v + minVotes)) * normalizedRating + (minVotes / (v + minVotes)) * priorMean
    }

    private func buildDiscoverMovie(
        _ movie: TMDBMovie,
        filter: DiscoverPathFilter,
        reason: String,
        path: [String],
        confidence: Double,
        profile: [String: Double]
    ) -> DiscoverRecommendation {
        DiscoverRecommendation(
            id: "movie-\(movie.id)",
            title: movie.title,
            subtitle: movie.year.map(String.init) ?? "Movie",
            posterURL: movie.posterURL,
            targetType: .movie,
            pathFilter: filter,
            reason: reason,
            path: sanitizedDiscoverPath(path),
            confidence: confidence,
            score: discoverScore(
                targetType: .movie,
                title: movie.title,
                overview: movie.overview,
                rating: movie.voteAverage,
                ratingCount: movie.voteCount,
                pathFilter: filter,
                confidence: confidence,
                profile: profile
            ),
            movie: movie,
            tvShow: nil,
            book: nil
        )
    }

    private func buildDiscoverTV(
        _ show: TMDBTVShow,
        filter: DiscoverPathFilter,
        reason: String,
        path: [String],
        confidence: Double,
        profile: [String: Double]
    ) -> DiscoverRecommendation {
        DiscoverRecommendation(
            id: "tv-\(show.id)",
            title: show.title,
            subtitle: show.year.map(String.init) ?? "TV",
            posterURL: show.posterURL,
            targetType: .tv,
            pathFilter: filter,
            reason: reason,
            path: sanitizedDiscoverPath(path),
            confidence: confidence,
            score: discoverScore(
                targetType: .tv,
                title: show.title,
                overview: show.overview,
                rating: show.voteAverage,
                ratingCount: show.voteCount,
                pathFilter: filter,
                confidence: confidence,
                profile: profile
            ),
            movie: nil,
            tvShow: show,
            book: nil
        )
    }

    private func buildDiscoverBook(
        _ book: HardcoverBooksService.SearchBook,
        filter: DiscoverPathFilter,
        reason: String,
        path: [String],
        confidence: Double,
        profile: [String: Double]
    ) -> DiscoverRecommendation {
        DiscoverRecommendation(
            id: "book-\(book.id)",
            title: book.title,
            subtitle: book.author ?? (book.year.map(String.init) ?? "Book"),
            posterURL: book.coverURL,
            targetType: .book,
            pathFilter: filter,
            reason: reason,
            path: sanitizedDiscoverPath(path),
            confidence: confidence,
            score: discoverScore(
                targetType: .book,
                title: book.title,
                overview: book.description,
                rating: book.rating,
                ratingCount: book.ratingCount,
                pathFilter: filter,
                confidence: confidence,
                profile: profile
            ),
            movie: nil,
            tvShow: nil,
            book: book
        )
    }

    private func parseTasteDiveType(_ raw: String?) -> HomeSuggestionMediaTypeHint {
        guard let raw else { return .unknown }
        let type = raw.lowercased()
        if type.contains("movie") { return .movie }
        if type.contains("show") || type.contains("tv") { return .tv }
        if type.contains("book") { return .book }
        return .unknown
    }

    private func bestMovieMatch(for query: String) async -> TMDBMovie? {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = movieMatchCache[key] { return cached }
        if movieMissCache.contains(key) { return nil }
        let persistentKey = RecommendationCacheStore.makeKey(prefix: "discover.movie.match.v1", raw: key)
        if let persisted: TMDBMovie = RecommendationCacheStore.load(key: persistentKey, maxAge: 60 * 60 * 24 * 5, as: TMDBMovie.self) {
            movieMatchCache[key] = persisted
            return persisted
        }

        let first = (try? await TMDBService.shared.searchMovies(query: query, page: 1)) ?? []
        let rankedFirst = rankMovieCandidates(first, query: query)
        if let confidentFirst = rankedFirst.first,
           isConfidentMovieMatch(confidentFirst, query: query) {
            movieMatchCache[key] = confidentFirst
            RecommendationCacheStore.store(key: persistentKey, payload: confidentFirst)
            return confidentFirst
        }

        let second = (try? await TMDBService.shared.searchMovies(query: query, page: 2)) ?? []
        let ranked = rankMovieCandidates(first + second, query: query)
        if let best = ranked.first {
            movieMatchCache[key] = best
            RecommendationCacheStore.store(key: persistentKey, payload: best)
            return best
        }

        movieMissCache.insert(key)
        return nil
    }

    private func rankMovieCandidates(_ results: [TMDBMovie], query: String) -> [TMDBMovie] {
        let qualityFiltered = results.filter { movie in
            let rating = movie.voteAverage ?? 0
            let votes = movie.voteCount ?? 0
            let highQuality = rating >= 7.0 && votes >= 180
            let mainstreamHit = rating >= 6.4 && votes >= 1500
            let criticalPick = rating >= 8.0 && votes >= 60
            return highQuality || mainstreamHit || criticalPick
        }
        let pool = qualityFiltered.isEmpty ? results : qualityFiltered
        return pool.sorted {
            let l = bayesianWeightedRating(targetType: .movie, rating: $0.voteAverage ?? 0, ratingCount: $0.voteCount ?? 0) + log10(Double(max($0.voteCount ?? 1, 1))) * 0.45 + titleSimilarity($0.title, query) * 2.5
            let r = bayesianWeightedRating(targetType: .movie, rating: $1.voteAverage ?? 0, ratingCount: $1.voteCount ?? 0) + log10(Double(max($1.voteCount ?? 1, 1))) * 0.45 + titleSimilarity($1.title, query) * 2.5
            return l > r
        }
    }

    private func isConfidentMovieMatch(_ movie: TMDBMovie, query: String) -> Bool {
        let similarity = titleSimilarity(movie.title, query)
        let votes = movie.voteCount ?? 0
        return similarity >= 0.92 || (similarity >= 0.84 && votes >= 500)
    }

    private func bestTVMatch(for query: String) async -> TMDBTVShow? {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = tvMatchCache[key] { return cached }
        if tvMissCache.contains(key) { return nil }
        let persistentKey = RecommendationCacheStore.makeKey(prefix: "discover.tv.match.v1", raw: key)
        if let persisted: TMDBTVShow = RecommendationCacheStore.load(key: persistentKey, maxAge: 60 * 60 * 24 * 5, as: TMDBTVShow.self) {
            tvMatchCache[key] = persisted
            return persisted
        }

        let first = (try? await TMDBService.shared.searchTVShows(query: query, page: 1)) ?? []
        let rankedFirst = rankTVCandidates(first, query: query)
        if let confidentFirst = rankedFirst.first,
           isConfidentTVMatch(confidentFirst, query: query) {
            tvMatchCache[key] = confidentFirst
            RecommendationCacheStore.store(key: persistentKey, payload: confidentFirst)
            return confidentFirst
        }

        let second = (try? await TMDBService.shared.searchTVShows(query: query, page: 2)) ?? []
        let ranked = rankTVCandidates(first + second, query: query)
        if let best = ranked.first {
            tvMatchCache[key] = best
            RecommendationCacheStore.store(key: persistentKey, payload: best)
            return best
        }

        tvMissCache.insert(key)
        return nil
    }

    private func rankTVCandidates(_ results: [TMDBTVShow], query: String) -> [TMDBTVShow] {
        let qualityFiltered = results.filter { show in
            let rating = show.voteAverage ?? 0
            let votes = show.voteCount ?? 0
            let highQuality = rating >= 7.1 && votes >= 140
            let mainstreamHit = rating >= 6.5 && votes >= 1200
            let criticalPick = rating >= 8.1 && votes >= 40
            return highQuality || mainstreamHit || criticalPick
        }
        let pool = qualityFiltered.isEmpty ? results : qualityFiltered
        return pool.sorted {
            let l = bayesianWeightedRating(targetType: .tv, rating: $0.voteAverage ?? 0, ratingCount: $0.voteCount ?? 0) + log10(Double(max($0.voteCount ?? 1, 1))) * 0.45 + titleSimilarity($0.title, query) * 2.5
            let r = bayesianWeightedRating(targetType: .tv, rating: $1.voteAverage ?? 0, ratingCount: $1.voteCount ?? 0) + log10(Double(max($1.voteCount ?? 1, 1))) * 0.45 + titleSimilarity($1.title, query) * 2.5
            return l > r
        }
    }

    private func isConfidentTVMatch(_ show: TMDBTVShow, query: String) -> Bool {
        let similarity = titleSimilarity(show.title, query)
        let votes = show.voteCount ?? 0
        return similarity >= 0.92 || (similarity >= 0.84 && votes >= 350)
    }

    private func bestBookMatch(for query: String) async -> HardcoverBooksService.SearchBook? {
        await BookRecommendationResolver.shared.bestBookMatch(query: query)
    }

    private func buildDiscoverFallbackCandidates(
        existingMovieIDs: Set<Int>,
        existingTVIDs: Set<Int>,
        existingBookTitles: Set<String>,
        existingBookISBNs: Set<String>,
        seedItems: [DiscoverSeedItem],
        profile: [String: Double],
        deadline: Date
    ) async -> [DiscoverRecommendation] {
        var fallback: [DiscoverRecommendation] = []
        let terms = profile
            .sorted { $0.value > $1.value }
            .map(\.key)
            .filter { $0.count >= 4 && $0 != "film" && $0 != "book" && $0 != "show" && !broadBridgeTerms.contains($0) }
        let seedDerivedTerms = seedItems
            .flatMap { $0.themes + $0.genres }
            .flatMap(normalizeBridgeToken)
        let allTerms = Array(NSOrderedSet(array: terms + seedDerivedTerms)) as? [String] ?? terms
        let termPairs = Array(zip(allTerms, allTerms.dropFirst())).prefix(4)

        if targetFilter == .all || targetFilter == .movie {
            for (termA, termB) in termPairs {
                if Date() > deadline, !fallback.isEmpty { break }
                let query = "\(termA) \(termB)"
                guard let anchorSeed = bestSeedAnchor(termA: termA, termB: termB, seedItems: seedItems) else { continue }
                let anchor = anchorSeed.title
                let results = ((try? await TMDBService.shared.searchMovies(query: query, page: 1)) ?? [])
                for movie in results.prefix(10) where !existingMovieIDs.contains(movie.id) {
                    guard passesThemeBridgeSemanticGuard(
                        seed: anchorSeed,
                        tokenA: termA,
                        tokenB: termB,
                        candidateTitle: movie.title,
                        candidateOverview: movie.overview
                    ) else { continue }
                    fallback.append(
                        buildDiscoverMovie(
                            movie,
                            filter: .themeBridge,
                            reason: "Bridge from \(anchor): \(termA) + \(termB)",
                            path: [anchor, "Theme bridge: \(termA) + \(termB)", movie.title],
                            confidence: 0.7,
                            profile: profile
                        )
                    )
                }
            }
        }

        if targetFilter == .all || targetFilter == .tv {
            for (termA, termB) in termPairs {
                if Date() > deadline, !fallback.isEmpty { break }
                let query = "\(termA) \(termB)"
                guard let anchorSeed = bestSeedAnchor(termA: termA, termB: termB, seedItems: seedItems) else { continue }
                let anchor = anchorSeed.title
                let results = ((try? await TMDBService.shared.searchTVShows(query: query, page: 1)) ?? [])
                for show in results.prefix(10) where !existingTVIDs.contains(show.id) {
                    guard passesThemeBridgeSemanticGuard(
                        seed: anchorSeed,
                        tokenA: termA,
                        tokenB: termB,
                        candidateTitle: show.title,
                        candidateOverview: show.overview
                    ) else { continue }
                    fallback.append(
                        buildDiscoverTV(
                            show,
                            filter: .themeBridge,
                            reason: "Bridge from \(anchor): \(termA) + \(termB)",
                            path: [anchor, "Theme bridge: \(termA) + \(termB)", show.title],
                            confidence: 0.7,
                            profile: profile
                        )
                    )
                }
            }
        }

        if targetFilter == .all || targetFilter == .book {
            for (termA, termB) in termPairs {
                if Date() > deadline, !fallback.isEmpty { break }
                let query = "\(termA) \(termB)"
                guard let anchorSeed = bestSeedAnchor(termA: termA, termB: termB, seedItems: seedItems) else { continue }
                let anchor = anchorSeed.title
                guard let book = await bestBookMatch(for: query) else { continue }
                let normalized = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if existingBookTitles.contains(normalized) { continue }
                if let isbn = book.isbn, existingBookISBNs.contains(isbn) { continue }
                guard passesThemeBridgeSemanticGuard(
                    seed: anchorSeed,
                    tokenA: termA,
                    tokenB: termB,
                    candidateTitle: book.title,
                    candidateOverview: book.description,
                    candidateExtras: book.subjects + [book.primaryGenre ?? ""]
                ) else { continue }
                fallback.append(
                    buildDiscoverBook(
                        book,
                        filter: .themeBridge,
                        reason: "Bridge from \(anchor): \(termA) + \(termB)",
                        path: [anchor, "Theme bridge: \(termA) + \(termB)", book.title],
                        confidence: 0.66,
                        profile: profile
                    )
                )
            }
        }

        // Secondary fallback: item-anchored recommendation lists to keep results flowing.
        if fallback.count < 20 {
            let movieSeedIDs = movies.prefix(4).compactMap(\.tmdbID)
            for seedID in movieSeedIDs {
                if Date() > deadline, !fallback.isEmpty { break }
                let recs = (try? await TMDBService.shared.getMovieRecommendations(movieID: seedID, page: 1)) ?? []
                for movie in recs.prefix(8) where !existingMovieIDs.contains(movie.id) {
                    fallback.append(
                        buildDiscoverMovie(
                            movie,
                            filter: .crossMedia,
                            reason: "Audience-neighbor from your saved movies",
                            path: ["Saved movie", "Audience-neighbor path", movie.title],
                            confidence: 0.68,
                            profile: profile
                        )
                    )
                }
            }

            let tvSeedIDs = tvShows.prefix(4).compactMap(\.tmdbID)
            for seedID in tvSeedIDs {
                if Date() > deadline, !fallback.isEmpty { break }
                let recs = (try? await TMDBService.shared.getTVRecommendations(tvID: seedID, page: 1)) ?? []
                for show in recs.prefix(8) where !existingTVIDs.contains(show.id) {
                    fallback.append(
                        buildDiscoverTV(
                            show,
                            filter: .crossMedia,
                            reason: "Audience-neighbor from your saved shows",
                            path: ["Saved show", "Audience-neighbor path", show.title],
                            confidence: 0.68,
                            profile: profile
                        )
                    )
                }
            }
        }

        return fallback
    }

    private func openRecommendation(_ recommendation: DiscoverRecommendation) {
        switch recommendation.targetType {
        case .movie:
            if let movie = recommendation.movie {
                selectedMovie = movie
            } else {
                Task {
                    if let movie = await bestMovieMatch(for: recommendation.title) {
                        selectedMovie = movie
                    }
                }
            }
        case .tv:
            if let show = recommendation.tvShow {
                selectedShow = show
            } else {
                Task {
                    if let show = await bestTVMatch(for: recommendation.title) {
                        selectedShow = show
                    }
                }
            }
        case .book:
            if let book = recommendation.book {
                selectedBook = book
            } else {
                Task {
                    if let book = await bestBookMatch(for: recommendation.title) {
                        selectedBook = book
                    }
                }
            }
        }
    }
}

private struct DiscoverFilterBar: View {
    @Binding var targetFilter: DiscoverTargetFilter
    @Binding var pathFilter: DiscoverPathFilter
    @Binding var depth: DiscoverDepth
    @Binding var seedScope: DiscoverSeedScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(DiscoverTargetFilter.allCases) { filter in
                        Button(filter.label) { targetFilter = filter }
                    }
                } label: {
                    filterPill(title: "Type: \(targetFilter.label)")
                }

                Menu {
                    ForEach(DiscoverPathFilter.allCases) { filter in
                        Button(filter.label) { pathFilter = filter }
                    }
                } label: {
                    filterPill(title: "Path: \(pathFilter.label)")
                }

                Menu {
                    ForEach(DiscoverDepth.allCases) { option in
                        Button(option.label) { depth = option }
                    }
                } label: {
                    filterPill(title: "Depth: \(depth.label)")
                }

                Menu {
                    ForEach(DiscoverSeedScope.allCases) { option in
                        Button(option.label) { seedScope = option }
                    }
                } label: {
                    filterPill(title: "From: \(seedScope.label)")
                }
            }
        }
    }

    private func filterPill(title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.12))
        .overlay {
            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8)
        }
        .clipShape(Capsule())
    }
}

private struct DiscoverPathCard: View {
    let recommendation: DiscoverRecommendation
    let openAction: () -> Void
    let onQuickAdd: () -> Void
    let onLike: () -> Void
    let onDislike: () -> Void
    let onHide: () -> Void
    let onDismiss: () -> Void
    @State private var showPath = false
    @State private var showActionsMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: recommendation.posterURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.25))
                }
                .frame(width: 72, height: 106)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(recommendation.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "hand.thumbsdown")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(recommendation.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))

                    HStack(spacing: 8) {
                        tag(text: recommendation.targetType.label)
                        tag(text: recommendation.pathFilter.label)
                        tag(text: confidenceLabel(recommendation.confidence))
                    }
                }
            }

            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.84))

            VStack(alignment: .leading, spacing: 4) {
                Text("Why this is strong")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                ForEach(reasoningLines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                }
                if recommendation.targetType == .book {
                    Text("• \(bookConfidenceBreakdown)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
            }

            if showPath {
                Text(recommendation.path.joined(separator: " -> "))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineSpacing(2)
            }

            HStack(spacing: 10) {
                Button(showPath ? "Hide Path" : "View Path") {
                    withAnimation(.easeInOut(duration: 0.18)) { showPath.toggle() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))

                Spacer()

                Button("More Like This") { onLike() }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green.opacity(0.95))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.16))
                    .clipShape(Capsule())

                Button("Less Like This") { onDislike() }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange.opacity(0.95))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.16))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color(red: 0.08, green: 0.11, blue: 0.22).opacity(0.94))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            openAction()
        }
        .onLongPressGesture(minimumDuration: 0.32) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showActionsMenu = true
        }
        .confirmationDialog("Suggestion Actions", isPresented: $showActionsMenu, titleVisibility: .visible) {
            Button("Quick Add") { onQuickAdd() }
            Button("Hide for Now") { onHide() }
            Button("Don't Suggest Again", role: .destructive) { onDismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func tag(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
    }

    private func confidenceLabel(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        if value >= 0.82 { return "Strong · \(percent)%" }
        if value >= 0.68 { return "Medium · \(percent)%" }
        return "Exploratory · \(percent)%"
    }

    private var reasoningLines: [String] {
        var lines: [String] = []
        if let anchor = recommendation.path.first {
            lines.append("Anchor: \(anchor)")
        }
        if recommendation.path.count >= 3 {
            lines.append("Connection: \(recommendation.path[recommendation.path.count - 2])")
        }
        lines.append("Passed connection + public quality filters")
        return Array(lines.prefix(3))
    }

    private var bookConfidenceBreakdown: String {
        if let book = recommendation.book {
            let rating = book.rating ?? 0
            let count = book.ratingCount ?? 0
            let qualityLabel: String = {
                if rating >= 4.35 { return "quality high" }
                if rating >= 4.0 { return "quality strong" }
                if rating >= 3.8 { return "quality solid" }
                return "quality emerging"
            }()
            let popularityLabel: String = {
                if count >= 5000 { return "popularity very high" }
                if count >= 1000 { return "popularity high" }
                if count >= 200 { return "popularity medium" }
                return "popularity niche"
            }()
            let semanticLabel: String = recommendation.path.contains { $0.lowercased().contains("theme bridge") }
                ? "semantic bridge match"
                : "semantic path match"
            return "\(qualityLabel), \(popularityLabel), \(semanticLabel)"
        }
        let semanticLabel = recommendation.path.contains { $0.lowercased().contains("theme bridge") }
            ? "semantic bridge match"
            : "semantic path match"
        let confidenceBucket: String = {
            if recommendation.confidence >= 0.82 { return "quality high-confidence" }
            if recommendation.confidence >= 0.7 { return "quality confident" }
            return "quality medium-confidence"
        }()
        return "\(confidenceBucket), popularity validated, \(semanticLabel)"
    }
}

private extension DiscoverTargetType {
    var label: String {
        switch self {
        case .movie: return "Movie"
        case .tv: return "TV"
        case .book: return "Book"
        }
    }
}

struct HomeView: View {
    @Query(sort: \Movie.dateAdded, order: .reverse) private var movies: [Movie]
    @Query(sort: \TVShow.dateAdded, order: .reverse) private var tvShows: [TVShow]
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @Query(sort: \PodcastEpisode.dateAdded, order: .reverse) private var podcasts: [PodcastEpisode]
    @Query(sort: \PodcastHighlight.createdAt, order: .reverse) private var podcastHighlights: [PodcastHighlight]
    @Query private var collections: [ItemCollection]

    @State private var activeSheet: AddMediaSheet?
    @State private var homeSuggestions: [HomeSuggestion] = []
    @State private var isLoadingSuggestions = false
    @State private var animateIn = false
    @State private var selectedSuggestedMovie: TMDBMovie?
    @State private var selectedSuggestedShow: TMDBTVShow?
    @State private var selectedSuggestedBook: HardcoverBooksService.SearchBook?
    @State private var selectedContinueEpisode: PodcastEpisode?
    @State private var selectedLibraryMovie: Movie?
    @State private var selectedLibraryShow: TVShow?
    @State private var selectedLibraryBook: Book?
    @AppStorage("home_suggestions_last_refresh_ts_v1") private var lastHomeSuggestionRefreshTimestamp: Double = 0
    @Namespace private var immersiveLaunchTransition

    private var homeRefreshFingerprint: String {
        movies.map(\.id).description
            + tvShows.map(\.id).description
            + books.map(\.id).description
            + podcasts.map(\.id).description
    }

    private var homeCacheKey: String {
        RecommendationCacheStore.makeKey(prefix: "home.suggestions.v2", raw: homeRefreshFingerprint)
    }
    
    var allThemes: [String] {
        let movieThemes = movies.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        let tvThemes = tvShows.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        let bookThemes = books.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        let podcastThemes = podcasts.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        return Array(Set(movieThemes + tvThemes + bookThemes + podcastThemes)).sorted()
    }
    
    var totalItems: Int {
        movies.count + tvShows.count + books.count + podcasts.count
    }

    private var mediaTypeCounts: [(String, Int, Color, String)] {
        [
            ("Movies", movies.count, .blue, "film.fill"),
            ("TV", tvShows.count, .green, "tv.fill"),
            ("Books", books.count, .orange, "book.closed.fill"),
            ("Podcasts", podcasts.count, .pink, "mic.fill")
        ]
    }

    private var themeFrequency: [String: Int] {
        let all = movies.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
            + tvShows.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
            + books.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
            + podcasts.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) }
        return Dictionary(grouping: all, by: { $0 }).mapValues(\.count)
    }

    private var topThemes: [(String, Int)] {
        themeFrequency.sorted {
            if $0.value == $1.value { return $0.key < $1.key }
            return $0.value > $1.value
        }
        .prefix(8)
        .map { ($0.key, $0.value) }
    }

    private var itemsWithThemes: Int {
        movies.filter { !ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }.count
        + tvShows.filter { !ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }.count
        + books.filter { !ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }.count
        + podcasts.filter { !ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }.count
    }

    private var themeCoverageRatio: Double {
        guard totalItems > 0 else { return 0 }
        return Double(itemsWithThemes) / Double(totalItems)
    }

    private var podcastNoteCountByEpisode: [String: Int] {
        Dictionary(grouping: podcastHighlights, by: \.episodeID).mapValues(\.count)
    }

    private var podcastEpisodeWithNotes: Int {
        podcasts.filter { (podcastNoteCountByEpisode[$0.id.uuidString] ?? 0) > 0 }.count
    }

    private var podcastEpisodesWithGeneratedThemes: Int {
        podcasts.filter {
            (podcastNoteCountByEpisode[$0.id.uuidString] ?? 0) > 0
                && !ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty
        }.count
    }

    private var podcastThemesReadyCount: Int {
        podcasts.filter {
            (podcastNoteCountByEpisode[$0.id.uuidString] ?? 0) > 0
                && ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty
        }.count
    }

private var missionBrief: String {
    let dominantTheme = topThemes.first?.0.replacingOccurrences(of: "-", with: " ").capitalized ?? "Untyped"
    let dominantCount = topThemes.first?.1 ?? 0
    let readyThemes = podcasts.filter {
        (podcastNoteCountByEpisode[$0.id.uuidString] ?? 0) > 0
            && ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty
    }.count
    if totalItems == 0 {
        return "Start by adding your first media item to begin building a connected knowledge graph."
    }
    return "Your strongest signal is \(dominantTheme) (\(dominantCount)). \(readyThemes) podcast episodes are ready for note-based theme generation."
}

private var crossMediaThemeCount: Int {
    guard totalItems > 0 else { return 0 }
    let movieSet = Set(movies.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) })
    let tvSet = Set(tvShows.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) })
    let bookSet = Set(books.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) })
    let podcastSet = Set(podcasts.flatMap { ThemeExtractor.shared.normalizeThemes($0.themes) })
    let all = movieSet.union(tvSet).union(bookSet).union(podcastSet)
    return all.filter { theme in
        var hits = 0
        if movieSet.contains(theme) { hits += 1 }
        if tvSet.contains(theme) { hits += 1 }
        if bookSet.contains(theme) { hits += 1 }
        if podcastSet.contains(theme) { hits += 1 }
        return hits >= 2
    }.count
}

private var completedItemCount: Int {
    movies.filter { $0.watchedDate != nil }.count
        + tvShows.filter { $0.watchedDate != nil }.count
        + books.filter { $0.watchedDate != nil }.count
        + podcasts.filter { $0.completedAt != nil }.count
}

private var inProgressItemCount: Int {
    inProgressEpisodes.count
}

private var plannedItemCount: Int {
    max(totalItems - completedItemCount - inProgressItemCount, 0)
}

private var completionRate: Double {
    guard totalItems > 0 else { return 0 }
    return Double(completedItemCount) / Double(totalItems)
}

private var homeSignalEntries: [HomeSignalEntry] {
    let movieEntries = movies.map { item in
        HomeSignalEntry(
            title: item.title,
            mediaLabel: "Movie",
            themes: ThemeExtractor.shared.normalizeThemes(item.themes)
        )
    }
    let tvEntries = tvShows.map { item in
        HomeSignalEntry(
            title: item.title,
            mediaLabel: "TV",
            themes: ThemeExtractor.shared.normalizeThemes(item.themes)
        )
    }
    let bookEntries = books.map { item in
        HomeSignalEntry(
            title: item.title,
            mediaLabel: "Book",
            themes: ThemeExtractor.shared.normalizeThemes(item.themes)
        )
    }
    let podcastEntries = podcasts.map { item in
        HomeSignalEntry(
            title: item.title,
            mediaLabel: "Podcast",
            themes: ThemeExtractor.shared.normalizeThemes(item.themes)
        )
    }
    return movieEntries + tvEntries + bookEntries + podcastEntries
}

private var primaryCrossMediaInsight: HomeCrossMediaInsight? {
    let nonEmpty = homeSignalEntries.filter { !$0.themes.isEmpty }
    guard !nonEmpty.isEmpty else { return nil }

    var grouped: [String: [HomeSignalEntry]] = [:]
    for entry in nonEmpty {
        for theme in entry.themes {
            grouped[theme, default: []].append(entry)
        }
    }

    let candidates = grouped.compactMap { theme, entries -> HomeCrossMediaInsight? in
        let mediaKinds = Set(entries.map(\.mediaLabel))
        guard mediaKinds.count >= 2 else { return nil }
        return HomeCrossMediaInsight(theme: theme, entries: entries)
    }

    return candidates.sorted { lhs, rhs in
        if lhs.entries.count == rhs.entries.count {
            return lhs.theme < rhs.theme
        }
        return lhs.entries.count > rhs.entries.count
    }.first
}

private var valueNarrative: String {
    if let insight = primaryCrossMediaInsight {
        let names = insight.entries.map(\.title).prefix(3).joined(separator: ", ")
        let cleanedTheme = insight.theme.replacingOccurrences(of: "-", with: " ").capitalized
        return "\(cleanedTheme) connects \(names). This is your strongest discovery lane right now."
    }
    if totalItems == 0 {
        return "Add media from at least two types to unlock your first meaningful cross-media connection."
    }
    return "Keep adding items and themes; once two media types overlap, discovery quality rises quickly."
}

private var strongestThemeLabel: String {
    topThemes.first?.0.replacingOccurrences(of: "-", with: " ").capitalized ?? "No dominant theme yet"
}

private var momentumItems: [HomeMomentumItem] {
    let movieItems = movies.prefix(5).map {
        HomeMomentumItem(id: $0.id.uuidString, title: $0.title, subtitle: "Movie", date: $0.dateAdded, symbol: "film.fill", color: .blue)
    }
    let tvItems = tvShows.prefix(5).map {
        HomeMomentumItem(id: $0.id.uuidString, title: $0.title, subtitle: "TV Show", date: $0.dateAdded, symbol: "tv.fill", color: .green)
    }
    let bookItems = books.prefix(5).map {
        HomeMomentumItem(id: $0.id.uuidString, title: $0.title, subtitle: "Book", date: $0.dateAdded, symbol: "book.closed.fill", color: .orange)
    }
    let podcastItems = podcasts.prefix(5).map {
        HomeMomentumItem(id: $0.id.uuidString, title: $0.title, subtitle: "Podcast", date: $0.dateAdded, symbol: "mic.fill", color: .pink)
    }

    return (movieItems + tvItems + bookItems + podcastItems)
        .sorted { $0.date > $1.date }
        .prefix(10)
        .map { $0 }
}

private var topHomeSuggestions: [HomeSuggestion] {
    Array(homeSuggestions.prefix(3))
}

private var inProgressEpisodes: [PodcastEpisode] {
    podcasts
        .filter {
            ($0.durationSeconds ?? 0) > 0
                && $0.completedAt == nil
                && $0.currentPositionSeconds > 20
        }
        .sorted { lhs, rhs in
            lhs.currentPositionSeconds > rhs.currentPositionSeconds
        }
}

private var itemsMissingThemesCount: Int {
    movies.filter { ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }.count
        + tvShows.filter { ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }.count
        + books.filter { ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }.count
        + podcasts.filter { ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }.count
}

private var personalTopRating: (String, Double)? {
    var scored: [(String, Double)] = []
    scored.append(contentsOf: movies.compactMap { movie in
        guard let rating = movie.rating else { return nil }
        return (movie.title, rating)
    })
    scored.append(contentsOf: tvShows.compactMap { show in
        guard let rating = show.rating else { return nil }
        return (show.title, rating)
    })
    return scored.sorted { $0.1 > $1.1 }.first
}

private var personalTasteLine: String? {
    guard let top = personalTopRating else { return nil }
    return "Your top personal rating: \(top.0) ★\(String(format: "%.1f", top.1))"
}

private var firstEpisodeReadyForThemes: PodcastEpisode? {
    podcasts.first {
        (podcastNoteCountByEpisode[$0.id.uuidString] ?? 0) > 0
            && ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty
    }
}

private var continueActions: [HomeContinueAction] {
    var actions: [HomeContinueAction] = []
    if let episode = inProgressEpisodes.first {
        actions.append(
            HomeContinueAction(
                title: "Resume listening",
                detail: "\(inProgressEpisodes.count) episode\(inProgressEpisodes.count == 1 ? "" : "s") in progress",
                symbol: "play.circle.fill",
                tint: .blue,
                kind: .resumeEpisode,
                targetEpisodeID: episode.id.uuidString
            )
        )
    }

    if let episode = firstEpisodeReadyForThemes {
        actions.append(
            HomeContinueAction(
                title: "Generate podcast themes",
                detail: "\(podcastThemesReadyCount) episode\(podcastThemesReadyCount == 1 ? "" : "s") ready from notes",
                symbol: "sparkles",
                tint: .purple,
                kind: .generatePodcastThemes,
                targetEpisodeID: episode.id.uuidString
            )
        )
    }

    if itemsMissingThemesCount > 0 {
        actions.append(
            HomeContinueAction(
                title: "Review missing themes",
                detail: "\(itemsMissingThemesCount) items need theme coverage",
                symbol: "arrow.triangle.2.circlepath",
                tint: .orange,
                kind: .reviewMissingThemes,
                targetEpisodeID: nil
            )
        )
    }

    return Array(actions.prefix(3))
}


private var knowledgePulseItems: [HomePulseMetric] {
    [
        HomePulseMetric(
            title: "Coverage",
            value: "\(Int((themeCoverageRatio * 100).rounded()))%",
            detail: "items with extracted themes",
            symbol: "waveform.path.ecg",
            tint: .cyan
        ),
        HomePulseMetric(
            title: "Cross-Media",
            value: "\(crossMediaThemeCount)",
            detail: "themes connecting 2+ media types",
            symbol: "point.3.connected.trianglepath.dotted",
            tint: .green
        ),
        HomePulseMetric(
            title: "Completion",
            value: "\(Int((completionRate * 100).rounded()))%",
            detail: "\(completedItemCount) done · \(plannedItemCount) planned",
            symbol: "checkmark.seal.fill",
            tint: .mint
        ),
        HomePulseMetric(
            title: "In Progress",
            value: "\(inProgressItemCount)",
            detail: "active listening sessions right now",
            symbol: "play.circle.fill",
            tint: .blue
        )
    ]
}

var body: some View {
    NavigationStack {
        ScrollView {
            VStack(spacing: 18) {
                HomeMissionHeader(
                    totalItems: totalItems,
                    themeCount: allThemes.count,
                    collectionCount: collections.count,
                    missionBrief: missionBrief,
                    onAddMovie: { activeSheet = .movie },
                    onAddTV: { activeSheet = .tvShow },
                    onAddBook: { activeSheet = .book },
                    onAddPodcast: { activeSheet = .podcast }
                )
                .homeEntrance(step: 0, active: animateIn)

                if totalItems == 0 {
                    HomeEmptyState(
                        onAddMovie: { activeSheet = .movie },
                        onAddTV: { activeSheet = .tvShow },
                        onAddBook: { activeSheet = .book },
                        onAddPodcast: { activeSheet = .podcast }
                    )
                    .homeEntrance(step: 1, active: animateIn)
                } else {
                    HomeKnowledgePulseCard(metrics: knowledgePulseItems)
                        .homeEntrance(step: 1, active: animateIn)
                        .padding(.horizontal, 16)

                    HomeValueNarrativeCard(
                        narrative: valueNarrative,
                        insight: primaryCrossMediaInsight
                    )
                    .homeEntrance(step: 2, active: animateIn)
                    .padding(.horizontal, 16)

                    HomeContinueLoopCard(actions: continueActions, onTap: openContinueAction)
                        .homeEntrance(step: 2, active: animateIn)
                        .padding(.horizontal, 16)

                    Text("Explore Your Constellation")
                        .font(ConstellationTypeScale.sectionTitle)
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 16)
                        .homeEntrance(step: 3, active: animateIn)

                    NavigationLink {
                        ConstellationGraphView(
                            movies: movies,
                            tvShows: tvShows,
                            books: books,
                            collections: collections,
                            autoLaunchImmersive: true
                        )
                        .navigationTransition(
                            .zoom(sourceID: "immersive-launch", in: immersiveLaunchTransition)
                        )
                    } label: {
                        HomeImmersiveLaunchCard(
                            itemCount: totalItems,
                            themeCount: allThemes.count
                        )
                    }
                    .matchedTransitionSource(id: "immersive-launch", in: immersiveLaunchTransition)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .homeEntrance(step: 4, active: animateIn)

                    if let personalTasteLine {
                        Text(personalTasteLine)
                            .font(ConstellationTypeScale.caption)
                            .foregroundStyle(ConstellationPalette.accentSoft)
                            .padding(.horizontal, 16)
                            .homeEntrance(step: 5, active: animateIn)
                    }

                    Text("Top Explainable Picks")
                        .font(ConstellationTypeScale.sectionTitle)
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 16)
                        .homeEntrance(step: 5, active: animateIn)

                    if isLoadingSuggestions {
                        VStack(spacing: 10) {
                            HomeSuggestionSkeletonCard()
                            HomeSuggestionSkeletonCard()
                        }
                        .padding(.horizontal, 16)
                        .homeEntrance(step: 6, active: animateIn)
                    } else if topHomeSuggestions.isEmpty {
                        Text("Add more media and we'll surface high-confidence cross-media paths here.")
                            .font(ConstellationTypeScale.caption)
                            .foregroundStyle(.white.opacity(0.74))
                            .padding(.horizontal, 16)
                            .homeEntrance(step: 6, active: animateIn)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(topHomeSuggestions) { suggestion in
                                Button {
                                    openSuggestion(suggestion)
                                } label: {
                                    HomeExplainablePickRow(suggestion: suggestion)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .homeEntrance(step: 6, active: animateIn)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(
            HomeStarfieldBackground()
                .ignoresSafeArea()
        )
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        activeSheet = .movie
                    } label: {
                        Label("Add Movie", systemImage: "film.fill")
                    }

                    Button {
                        activeSheet = .tvShow
                    } label: {
                        Label("Add TV Show", systemImage: "tv.fill")
                    }

                    Button {
                        activeSheet = .book
                    } label: {
                        Label("Add Book", systemImage: "book.closed.fill")
                    }

                    Button {
                        activeSheet = .podcast
                    } label: {
                        Label("Add Podcast", systemImage: "mic.fill")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .movie:
                MovieSearchView()
            case .tvShow:
                TVShowSearchView()
            case .book:
                BookSearchView()
            case .podcast:
                PodcastSearchView()
            }
        }
        .sheet(item: $selectedSuggestedMovie) { movie in
            MovieDetailSheet(movie: movie)
        }
        .sheet(item: $selectedSuggestedShow) { show in
            TVShowDetailSheet(show: show)
        }
        .sheet(item: $selectedSuggestedBook) { book in
            BookDetailSheet(book: book)
        }
        .sheet(item: $selectedContinueEpisode) { episode in
            NavigationStack {
                PodcastEpisodeDetailView(episode: episode)
            }
        }
        .sheet(item: $selectedLibraryMovie) { movie in
            NavigationStack {
                MovieDetailView(movie: movie)
            }
        }
        .sheet(item: $selectedLibraryShow) { show in
            NavigationStack {
                TVShowDetailView(show: show)
            }
        }
        .sheet(item: $selectedLibraryBook) { book in
            NavigationStack {
                BookDetailView(book: book)
            }
        }
        .task(
            id: homeRefreshFingerprint
        ) {
            await loadHomeSuggestions()
        }
        .onAppear {
            animateIn = true
        }
    }
}

private func openContinueAction(_ action: HomeContinueAction) {
    switch action.kind {
    case .resumeEpisode, .generatePodcastThemes:
        if let id = action.targetEpisodeID,
           let match = podcasts.first(where: { $0.id.uuidString == id }) {
            selectedContinueEpisode = match
        } else if let fallback = inProgressEpisodes.first ?? firstEpisodeReadyForThemes {
            selectedContinueEpisode = fallback
        }
    case .reviewMissingThemes:
        if let movie = movies.first(where: { ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }) {
            selectedLibraryMovie = movie
            return
        }
        if let show = tvShows.first(where: { ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }) {
            selectedLibraryShow = show
            return
        }
        if let book = books.first(where: { ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }) {
            selectedLibraryBook = book
            return
        }
        if let episode = podcasts.first(where: { ThemeExtractor.shared.normalizeThemes($0.themes).isEmpty }) {
            selectedContinueEpisode = episode
        }
    }
}

private func loadHomeSuggestions() async {

        guard !movies.isEmpty || !tvShows.isEmpty || !books.isEmpty || !podcasts.isEmpty else {
            homeSuggestions = []
            return
        }
if let cached: [HomeSuggestionCacheItem] = RecommendationCacheStore.load(
    key: homeCacheKey,
    maxAge: 60 * 60 * 8,
    as: [HomeSuggestionCacheItem].self
) {
    homeSuggestions = cached.map { item in
        HomeSuggestion(
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            posterURL: normalizedRemoteURL(from: item.posterURL),
            reason: item.reason,
            mediaType: item.mediaType,
            score: item.score
        )
    }

    let now = Date().timeIntervalSince1970
    if now - lastHomeSuggestionRefreshTimestamp < (60 * 20) {
        return
    }
}

let hasVisibleSuggestions = !homeSuggestions.isEmpty
isLoadingSuggestions = !hasVisibleSuggestions
        defer { isLoadingSuggestions = false }

        let existingMovieIDs = Set(movies.compactMap(\.tmdbID))
        let existingTVIDs = Set(tvShows.compactMap(\.tmdbID))
        let existingBookNormalizedTitles = Set(
            books.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let existingBookISBNs = Set(books.compactMap(\.isbn))
        let preferenceProfile = buildPreferenceProfile()
        let maxCandidatePool = 48
        let tastePerSeedLimit = 3

        var candidates: [HomeSuggestion] = []
        var movieMatchCache: [String: TMDBMovie] = [:]
        var tvMatchCache: [String: TMDBTVShow] = [:]
        var bookMatchCache: [String: HardcoverBooksService.SearchBook] = [:]
        var movieMisses: Set<String> = []
        var tvMisses: Set<String> = []
        var bookMisses: Set<String> = []

        func normalizedLookupKey(_ raw: String) -> String {
            raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        func cachedBestMovieMatch(_ query: String) async -> TMDBMovie? {
            let key = normalizedLookupKey(query)
            if let cached = movieMatchCache[key] { return cached }
            if movieMisses.contains(key) { return nil }
            let matched = await bestMovieMatch(for: query)
            if let matched {
                movieMatchCache[key] = matched
            } else {
                movieMisses.insert(key)
            }
            return matched
        }

        func cachedBestTVMatch(_ query: String) async -> TMDBTVShow? {
            let key = normalizedLookupKey(query)
            if let cached = tvMatchCache[key] { return cached }
            if tvMisses.contains(key) { return nil }
            let matched = await bestTVMatch(for: query)
            if let matched {
                tvMatchCache[key] = matched
            } else {
                tvMisses.insert(key)
            }
            return matched
        }

        func cachedBestBookMatch(_ query: String) async -> HardcoverBooksService.SearchBook? {
            let key = normalizedLookupKey(query)
            if let cached = bookMatchCache[key] { return cached }
            if bookMisses.contains(key) { return nil }
            let matched = await bestBookMatch(for: query)
            if let matched {
                bookMatchCache[key] = matched
            } else {
                bookMisses.insert(key)
            }
            return matched
        }

        let movieSeeds = movies
            .filter { $0.watchedDate != nil }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .prefix(2)
            .compactMap(\.tmdbID)
var movieRecommendationsBySeed: [Int: [TMDBMovie]] = [:]
await withTaskGroup(of: (Int, [TMDBMovie]).self) { group in
    for seed in movieSeeds {
        group.addTask {
            let similar = (try? await TMDBService.shared.getMovieRecommendations(movieID: seed, page: 1)) ?? []
            return (seed, similar)
        }
    }
    for await (seed, similar) in group {
        movieRecommendationsBySeed[seed] = similar
    }
}

for seed in movieSeeds {
    if candidates.count >= maxCandidatePool { break }
    let similar = movieRecommendationsBySeed[seed] ?? []
    for item in similar where !existingMovieIDs.contains(item.id) {
        candidates.append(
            HomeSuggestion(
                id: "movie-\(item.id)",
                title: item.title,
                subtitle: item.year.map(String.init) ?? "Movie",
                posterURL: item.posterURL,
                reason: "Matched by similar audience taste",
                mediaType: .movie,
                score: blendedScore(
                    title: item.title,
                    overview: item.overview,
                    voteAverage: item.voteAverage,
                    voteCount: item.voteCount,
                    sourceBoost: 1.0,
                    preferenceProfile: preferenceProfile
                ),
                movie: item
            )
        )
    }
}

let showSeeds =
 tvShows
            .filter { $0.watchedDate != nil }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .prefix(2)
            .compactMap(\.tmdbID)
var tvRecommendationsBySeed: [Int: [TMDBTVShow]] = [:]
await withTaskGroup(of: (Int, [TMDBTVShow]).self) { group in
    for seed in showSeeds {
        group.addTask {
            let similar = (try? await TMDBService.shared.getTVRecommendations(tvID: seed, page: 1)) ?? []
            return (seed, similar)
        }
    }
    for await (seed, similar) in group {
        tvRecommendationsBySeed[seed] = similar
    }
}

for seed in showSeeds {
    if candidates.count >= maxCandidatePool { break }
    let similar = tvRecommendationsBySeed[seed] ?? []
    for item in similar where !existingTVIDs.contains(item.id) {
        candidates.append(
            HomeSuggestion(
                id: "tv-\(item.id)",
                title: item.title,
                subtitle: item.year.map(String.init) ?? "TV Show",
                posterURL: item.posterURL,
                reason: "Matched by similar audience taste",
                mediaType: .tv,
                score: blendedScore(
                    title: item.title,
                    overview: item.overview,
                    voteAverage: item.voteAverage,
                    voteCount: item.voteCount,
                    sourceBoost: 1.0,
                    preferenceProfile: preferenceProfile
                ),
                tvShow: item
            )
        )
    }
}

let movieSeedTitles =
 movies
            .filter { $0.watchedDate != nil || ($0.rating ?? 0) >= 4.0 }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .prefix(2)
            .map(\.title)
        let tvSeedTitles = tvShows
            .filter { $0.watchedDate != nil || ($0.rating ?? 0) >= 4.0 }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .prefix(2)
            .map(\.title)
        let seedTitles = Array(NSOrderedSet(array: movieSeedTitles + tvSeedTitles)) as? [String] ?? []
var tasteResultsBySeedTitle: [String: [TasteDiveResult]] = [:]
await withTaskGroup(of: (String, [TasteDiveResult]).self) { group in
    for seedTitle in seedTitles {
        group.addTask {
            let movieResults = (try? await TasteDiveService.shared.similar(query: seedTitle, type: .movie, limit: 6)) ?? []
            let showResults = (try? await TasteDiveService.shared.similar(query: seedTitle, type: .show, limit: 6)) ?? []
            return (seedTitle, Array((movieResults + showResults).prefix(tastePerSeedLimit)))
        }
    }
    for await (seedTitle, results) in group {
        tasteResultsBySeedTitle[seedTitle] = results
    }
}

for seedTitle in seedTitles {
    if candidates.count >= maxCandidatePool { break }
    let tasteResults = tasteResultsBySeedTitle[seedTitle] ?? []
    for tasteResult in tasteResults {
        if candidates.count >= maxCandidatePool { break }
        let mediaHint = parseTasteDiveMediaType(tasteResult.type)
        switch mediaHint {
        case .movie:
            if let movie = await cachedBestMovieMatch(tasteResult.name),
               !existingMovieIDs.contains(movie.id) {
                candidates.append(
                    HomeSuggestion(
                        id: "movie-\(movie.id)",
                        title: movie.title,
                        subtitle: movie.year.map(String.init) ?? "Movie",
                        posterURL: movie.posterURL,
                        reason: "Taste graph match from \(seedTitle)",
                        mediaType: .movie,
                        score: blendedScore(
                            title: movie.title,
                            overview: movie.overview,
                            voteAverage: movie.voteAverage,
                            voteCount: movie.voteCount,
                            sourceBoost: 1.3,
                            preferenceProfile: preferenceProfile
                        ),
                        movie: movie
                    )
                )
            }
        case .tv:
            if let show = await cachedBestTVMatch(tasteResult.name),
               !existingTVIDs.contains(show.id) {
                candidates.append(
                    HomeSuggestion(
                        id: "tv-\(show.id)",
                        title: show.title,
                        subtitle: show.year.map(String.init) ?? "TV Show",
                        posterURL: show.posterURL,
                        reason: "Taste graph match from \(seedTitle)",
                        mediaType: .tv,
                        score: blendedScore(
                            title: show.title,
                            overview: show.overview,
                            voteAverage: show.voteAverage,
                            voteCount: show.voteCount,
                            sourceBoost: 1.3,
                            preferenceProfile: preferenceProfile
                        ),
                        tvShow: show
                    )
                )
            }
        case .book:
            if let book = await cachedBestBookMatch(tasteResult.name) {
                let normalizedTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if existingBookNormalizedTitles.contains(normalizedTitle) { continue }
                if let isbn = book.isbn, existingBookISBNs.contains(isbn) { continue }

                candidates.append(
                    HomeSuggestion(
                        id: "book-\(book.id)",
                        title: book.title,
                        subtitle: book.author ?? (book.year.map(String.init) ?? "Book"),
                        posterURL: book.coverURL,
                        reason: "Cross-media book pick from \(seedTitle)",
                        mediaType: .book,
                        score: blendedScore(
                            title: book.title,
                            overview: book.description,
                            voteAverage: book.rating,
                            voteCount: book.ratingCount,
                            sourceBoost: 1.2,
                            preferenceProfile: preferenceProfile
                        ),
                        book: book
                    )
                )
            }
        case .unknown:
            if let movie = await cachedBestMovieMatch(tasteResult.name),
               !existingMovieIDs.contains(movie.id) {
                candidates.append(
                    HomeSuggestion(
                        id: "movie-\(movie.id)",
                        title: movie.title,
                        subtitle: movie.year.map(String.init) ?? "Movie",
                        posterURL: movie.posterURL,
                        reason: "Taste graph match from \(seedTitle)",
                        mediaType: .movie,
                        score: blendedScore(
                            title: movie.title,
                            overview: movie.overview,
                            voteAverage: movie.voteAverage,
                            voteCount: movie.voteCount,
                            sourceBoost: 1.25,
                            preferenceProfile: preferenceProfile
                        ),
                        movie: movie
                    )
                )
            } else if let show = await cachedBestTVMatch(tasteResult.name),
                      !existingTVIDs.contains(show.id) {
                candidates.append(
                    HomeSuggestion(
                        id: "tv-\(show.id)",
                        title: show.title,
                        subtitle: show.year.map(String.init) ?? "TV Show",
                        posterURL: show.posterURL,
                        reason: "Taste graph match from \(seedTitle)",
                        mediaType: .tv,
                        score: blendedScore(
                            title: show.title,
                            overview: show.overview,
                            voteAverage: show.voteAverage,
                            voteCount: show.voteCount,
                            sourceBoost: 1.25,
                            preferenceProfile: preferenceProfile
                        ),
                        tvShow: show
                    )
                )
            }
        }
    }
}

let bookSeedTitles =
 books
            .filter { $0.watchedDate != nil || ($0.rating ?? 0) >= 4.0 }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
            .prefix(2)
            .map(\.title)
        let allSeedTitles = Array(NSOrderedSet(array: seedTitles + bookSeedTitles)) as? [String] ?? seedTitles
var bookTasteResultsBySeedTitle: [String: [TasteDiveResult]] = [:]
await withTaskGroup(of: (String, [TasteDiveResult]).self) { group in
    for seedTitle in allSeedTitles {
        group.addTask {
            let results = (try? await TasteDiveService.shared.similar(query: seedTitle, type: .book, limit: 6)) ?? []
            return (seedTitle, Array(results.prefix(tastePerSeedLimit)))
        }
    }
    for await (seedTitle, results) in group {
        bookTasteResultsBySeedTitle[seedTitle] = results
    }
}

for seedTitle in allSeedTitles {
    if candidates.count >= maxCandidatePool { break }
    let bookTasteResults = bookTasteResultsBySeedTitle[seedTitle] ?? []
    for tasteResult in bookTasteResults {
        if candidates.count >= maxCandidatePool { break }
        guard let book = await cachedBestBookMatch(tasteResult.name) else { continue }
        let normalizedTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if existingBookNormalizedTitles.contains(normalizedTitle) { continue }
        if let isbn = book.isbn, existingBookISBNs.contains(isbn) { continue }

        candidates.append(
            HomeSuggestion(
                id: "book-\(book.id)",
                title: book.title,
                subtitle: book.author ?? (book.year.map(String.init) ?? "Book"),
                posterURL: book.coverURL,
                reason: "Cross-media book pick from \(seedTitle)",
                mediaType: .book,
                score: blendedScore(
                    title: book.title,
                    overview: book.description,
                    voteAverage: book.rating,
                    voteCount: book.ratingCount,
                    sourceBoost: 1.2,
                    preferenceProfile: preferenceProfile
                ),
                book: book
            )
        )
    }
}

if candidates.count < 6 {

            let trending = (try? await TMDBService.shared.getTrendingAll(timeWindow: .week, page: 1)) ?? []
            var fallback: [HomeSuggestion] = []

            for item in trending.prefix(20) {
                if item.mediaType == "movie", existingMovieIDs.contains(item.id) { continue }
                if item.mediaType == "tv", existingTVIDs.contains(item.id) { continue }
                if item.mediaType != "movie" && item.mediaType != "tv" { continue }

                let trendText = (item.resolvedTitle + " " + (item.overview ?? "")).lowercased()
                let trendMatchWeight = preferenceMatchWeight(in: trendText, profile: preferenceProfile)

                let suggestion = HomeSuggestion(
                    id: "\(item.mediaType)-\(item.id)",
                    title: item.resolvedTitle,
                    subtitle: item.year.map(String.init) ?? item.mediaType.uppercased(),
                    posterURL: item.posterURL,
                    reason: trendMatchWeight > 0 ? "Trending and aligned to your library" : "Trending this week",
                    mediaType: item.mediaType == "movie" ? .movie : .tv,
                    score: blendedScore(
                        title: item.resolvedTitle,
                        overview: item.overview,
                        voteAverage: item.voteAverage,
                        voteCount: item.voteCount,
                        sourceBoost: trendMatchWeight > 0 ? 0.9 : 0.7,
                        preferenceProfile: preferenceProfile
                    ),
                    movie: item.mediaType == "movie"
                        ? TMDBMovie(
                            id: item.id,
                            title: item.resolvedTitle,
                            overview: item.overview,
                            posterPath: item.posterPath,
                            releaseDate: item.releaseDate,
                            voteAverage: item.voteAverage,
                            voteCount: item.voteCount,
                            genreIDs: nil
                        )
                        : nil,
                    tvShow: item.mediaType == "tv"
                        ? TMDBTVShow(
                            id: item.id,
                            name: item.resolvedTitle,
                            overview: item.overview,
                            posterPath: item.posterPath,
                            firstAirDate: item.firstAirDate,
                            voteAverage: item.voteAverage,
                            voteCount: item.voteCount,
                            genreIDs: nil
                        )
                        : nil
                )

                if trendMatchWeight > 0.65 || preferenceProfile.isEmpty {
                    fallback.append(suggestion)
                }
            }

            candidates.append(contentsOf: fallback)

            // Intentionally avoid broad unrelated fallback to keep suggestions connected.
        }

        var seen = Set<String>()
        let deduped = candidates.filter { seen.insert($0.id).inserted }
        let connected = deduped.filter { isConnectedHomeSuggestion($0, profile: preferenceProfile) }
        let ranked = connected
            .filter { meetsHomeQualityBaseline($0) }
            .sorted { $0.score > $1.score }
        let finalCandidates = ranked.count >= 8 ? ranked : connected.sorted { $0.score > $1.score }
        let finalSuggestions = diversifyHomeSuggestions(finalCandidates, limit: 15)
            .map { enrichSuggestionReason($0, preferenceProfile: preferenceProfile) }
        homeSuggestions = finalSuggestions
        let cachePayload = finalSuggestions.map { item in
            HomeSuggestionCacheItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                posterURL: item.posterURL?.absoluteString,
                reason: item.reason,
                mediaType: item.mediaType,
                score: item.score
            )
        }
        RecommendationCacheStore.store(key: homeCacheKey, payload: cachePayload)
        lastHomeSuggestionRefreshTimestamp = Date().timeIntervalSince1970
    }

    private func buildPreferenceProfile() -> [String: Double] {
        var profile: [String: Double] = [:]

        func addTerms(_ terms: [String], weight: Double) {
            for token in terms.flatMap(normalizeTerm) {
                profile[token, default: 0] += weight
            }
        }

        for movie in movies {
            let boost = (movie.watchedDate != nil || (movie.rating ?? 0) >= 4.0) ? 2.2 : 1.0
            addTerms(movie.themes + movie.genres, weight: boost)
        }
        for show in tvShows {
            let boost = (show.watchedDate != nil || (show.rating ?? 0) >= 4.0) ? 2.2 : 1.0
            addTerms(show.themes + show.genres, weight: boost)
        }
        for book in books {
            let boost = (book.watchedDate != nil || (book.rating ?? 0) >= 4.0) ? 2.0 : 0.95
            addTerms(book.themes + book.genres, weight: boost)
        }
        for podcast in podcasts {
            let noteBoost = (podcastNoteCountByEpisode[podcast.id.uuidString] ?? 0) > 0 ? 2.0 : 1.0
            addTerms(podcast.themes + podcast.genres, weight: noteBoost)
        }

        return profile
    }

    private func normalizeTerm(_ raw: String) -> [String] {
        raw.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }
    }

    private func blendedScore(
        title: String,
        overview: String?,
        voteAverage: Double?,
        voteCount: Int?,
        sourceBoost: Double,
        preferenceProfile: [String: Double]
    ) -> Double {
        let weightedQuality = homeBayesianWeightedRating(rating: voteAverage ?? 0, ratingCount: voteCount ?? 0)
        let popularity = log10(Double(max(voteCount ?? 1, 1))) * 2.2
        let text = (title + " " + (overview ?? "")).lowercased()
        let matchWeight = preferenceMatchWeight(in: text, profile: preferenceProfile)
        let personal = min(matchWeight * 0.32, 3.2)
        let socialProof = min(Double(max(voteCount ?? 0, 0)) / 3500.0, 2.0)
        let voteFloorPenalty = (voteCount ?? 0) < 30 ? -2.2 : 0
        return weightedQuality * 1.75 + popularity + personal + socialProof + sourceBoost + voteFloorPenalty
    }

    private func homeBayesianWeightedRating(rating: Double, ratingCount: Int) -> Double {
        let v = Double(max(ratingCount, 0))
        let normalized = min(max(rating, 0), 10)
        let priorMean = 6.9
        let minVotes = 180.0
        guard v > 0 else { return priorMean }
        return (v / (v + minVotes)) * normalized + (minVotes / (v + minVotes)) * priorMean
    }

    private func canonicalTitleTokens(_ value: String) -> Set<String> {
        let cleaned = value
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
        let parts = cleaned.split(separator: " ")
        var tokens: Set<String> = []
        tokens.reserveCapacity(parts.count)
        for part in parts {
            let token = String(part)
            guard token.count > 2 else { continue }
            guard token != "the", token != "and", token != "for" else { continue }
            tokens.insert(token)
        }
        return tokens
    }

    private func titleMatchConfidence(query: String, candidate: String) -> Double {
        let lhs = canonicalTitleTokens(query)
        let rhs = canonicalTitleTokens(candidate)
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private func meetsHomeQualityBaseline(_ suggestion: HomeSuggestion) -> Bool {
        switch suggestion.mediaType {
        case .movie:
            let rating = suggestion.movie?.voteAverage ?? 0
            let count = suggestion.movie?.voteCount ?? 0
            return (rating >= 7.0 && count >= 120) || (rating >= 6.6 && count >= 1200) || (rating >= 8.0 && count >= 50)
        case .tv:
            let rating = suggestion.tvShow?.voteAverage ?? 0
            let count = suggestion.tvShow?.voteCount ?? 0
            return (rating >= 7.0 && count >= 110) || (rating >= 6.6 && count >= 1100) || (rating >= 8.0 && count >= 45)
        case .book:
            let rating = suggestion.book?.rating ?? 0
            let count = suggestion.book?.ratingCount ?? 0
            return (rating >= 3.9 && count >= 100) || (rating >= 3.8 && count >= 600) || (rating >= 4.3 && count >= 35)
        }
    }

    private func homeSuggestionText(_ suggestion: HomeSuggestion) -> String {
        let overview: String
        switch suggestion.mediaType {
        case .movie:
            overview = suggestion.movie?.overview ?? ""
        case .tv:
            overview = suggestion.tvShow?.overview ?? ""
        case .book:
            overview = suggestion.book?.description ?? ""
        }
        return (suggestion.title + " " + suggestion.subtitle + " " + suggestion.reason + " " + overview).lowercased()
    }

    private func isConnectedHomeSuggestion(_ suggestion: HomeSuggestion, profile: [String: Double]) -> Bool {
        if profile.isEmpty { return true }
        let text = homeSuggestionText(suggestion)
        let topSignals = profile
            .sorted { $0.value > $1.value }
            .prefix(24)
        let score = topSignals.reduce(0.0) { partial, pair in
            text.contains(pair.key) ? partial + min(pair.value, 3.0) : partial
        }
        return score >= 1.1
    }

    private func diversifyHomeSuggestions(_ suggestions: [HomeSuggestion], limit: Int) -> [HomeSuggestion] {
        let sorted = suggestions.sorted { $0.score > $1.score }
        guard !sorted.isEmpty else { return [] }

        var picked: [HomeSuggestion] = []
        var backlog: [HomeSuggestion] = []
        var typeCount: [HomeSuggestionMediaType: Int] = [:]
        let typeCap = max(4, limit / 2)

        for item in sorted {
            if picked.count >= limit { break }
            if typeCount[item.mediaType, default: 0] < typeCap || picked.count < 6 {
                picked.append(item)
                typeCount[item.mediaType, default: 0] += 1
            } else {
                backlog.append(item)
            }
        }

        if picked.count < limit {
            for item in backlog where picked.count < limit {
                picked.append(item)
            }
        }
        return picked
    }

    private func preferenceMatchWeight(in text: String, profile: [String: Double]) -> Double {
        profile.reduce(into: 0) { acc, pair in
            if text.contains(pair.key) {
                acc += pair.value
            }
        }
    }

    private func enrichSuggestionReason(_ suggestion: HomeSuggestion, preferenceProfile: [String: Double]) -> HomeSuggestion {
        let text = suggestion.title.lowercased()
        let matched = preferenceProfile
            .filter { text.contains($0.key) }
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { $0.key.replacingOccurrences(of: "-", with: " ").capitalized }

        let personalizedReason: String
        if matched.isEmpty {
            personalizedReason = suggestion.reason
        } else {
            personalizedReason = "Matched to your library: \(matched.joined(separator: " + "))"
        }

        return HomeSuggestion(
            id: suggestion.id,
            title: suggestion.title,
            subtitle: suggestion.subtitle,
            posterURL: suggestion.posterURL,
            reason: personalizedReason,
            mediaType: suggestion.mediaType,
            score: suggestion.score,
            movie: suggestion.movie,
            tvShow: suggestion.tvShow,
            book: suggestion.book
        )
    }

    private func bestMovieMatch(for query: String) async -> TMDBMovie? {
        let first = (try? await TMDBService.shared.searchMovies(query: query, page: 1)) ?? []
        let second = (try? await TMDBService.shared.searchMovies(query: query, page: 2)) ?? []
        let results = first + second
        return results
            .filter { ($0.voteCount ?? 0) >= 80 || ($0.voteAverage ?? 0) >= 7.0 }
            .sorted { lhs, rhs in
                let l = homeBayesianWeightedRating(rating: lhs.voteAverage ?? 0, ratingCount: lhs.voteCount ?? 0)
                    + log10(Double(max(lhs.voteCount ?? 1, 1))) * 0.45
                    + titleMatchConfidence(query: query, candidate: lhs.title) * 2.2
                let r = homeBayesianWeightedRating(rating: rhs.voteAverage ?? 0, ratingCount: rhs.voteCount ?? 0)
                    + log10(Double(max(rhs.voteCount ?? 1, 1))) * 0.45
                    + titleMatchConfidence(query: query, candidate: rhs.title) * 2.2
                return l > r
            }
            .first
    }

    private func bestTVMatch(for query: String) async -> TMDBTVShow? {
        let first = (try? await TMDBService.shared.searchTVShows(query: query, page: 1)) ?? []
        let second = (try? await TMDBService.shared.searchTVShows(query: query, page: 2)) ?? []
        let results = first + second
        return results
            .filter { ($0.voteCount ?? 0) >= 80 || ($0.voteAverage ?? 0) >= 7.0 }
            .sorted { lhs, rhs in
                let l = homeBayesianWeightedRating(rating: lhs.voteAverage ?? 0, ratingCount: lhs.voteCount ?? 0)
                    + log10(Double(max(lhs.voteCount ?? 1, 1))) * 0.45
                    + titleMatchConfidence(query: query, candidate: lhs.title) * 2.2
                let r = homeBayesianWeightedRating(rating: rhs.voteAverage ?? 0, ratingCount: rhs.voteCount ?? 0)
                    + log10(Double(max(rhs.voteCount ?? 1, 1))) * 0.45
                    + titleMatchConfidence(query: query, candidate: rhs.title) * 2.2
                return l > r
            }
            .first
    }

    private func bestBookMatch(for query: String) async -> HardcoverBooksService.SearchBook? {
        await BookRecommendationResolver.shared.bestBookMatch(query: query)
    }

    private func parseTasteDiveMediaType(_ type: String?) -> HomeSuggestionMediaTypeHint {
        guard let type = type?.lowercased() else { return .unknown }
        if type.contains("movie") { return .movie }
        if type.contains("show") || type.contains("tv") { return .tv }
        if type.contains("book") { return .book }
        return .unknown
    }

    private func openSuggestion(_ suggestion: HomeSuggestion) {
        switch suggestion.mediaType {
        case .movie:
            if let movie = suggestion.movie {
                selectedSuggestedMovie = movie
            } else {
                Task {
                    if let movie = await bestMovieMatch(for: suggestion.title) {
                        selectedSuggestedMovie = movie
                    }
                }
            }
        case .tv:
            if let show = suggestion.tvShow {
                selectedSuggestedShow = show
            } else {
                Task {
                    if let show = await bestTVMatch(for: suggestion.title) {
                        selectedSuggestedShow = show
                    }
                }
            }
        case .book:
            if let book = suggestion.book {
                selectedSuggestedBook = book
            } else {
                Task {
                    if let book = await bestBookMatch(for: suggestion.title) {
                        selectedSuggestedBook = book
                    }
                }
            }
        }
    }
}

private struct HomeMomentumItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let date: Date
    let symbol: String
    let color: Color
}

private struct HomeMissionHeader: View {
    let totalItems: Int
    let themeCount: Int
    let collectionCount: Int
    let missionBrief: String
    let onAddMovie: () -> Void
    let onAddTV: () -> Void
    let onAddBook: () -> Void
    let onAddPodcast: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Mission Control")
                    .font(ConstellationTypeScale.heroTitle)
                    .foregroundStyle(.white)
                Text(missionBrief)
                    .font(ConstellationTypeScale.supporting)
                    .foregroundStyle(.white.opacity(0.84))
                    .lineSpacing(2)
            }

            HStack(spacing: 10) {
                heroStat(value: "\(totalItems)", label: "Items")
                heroStat(value: "\(themeCount)", label: "Themes")
                heroStat(value: "\(collectionCount)", label: "Collections")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HomeQuickAddPill(label: "Movie", symbol: "film.fill", action: onAddMovie)
                    HomeQuickAddPill(label: "TV", symbol: "tv.fill", action: onAddTV)
                    HomeQuickAddPill(label: "Book", symbol: "book.closed.fill", action: onAddBook)
                    HomeQuickAddPill(label: "Podcast", symbol: "mic.fill", action: onAddPodcast)
                }
            }
        }
        .padding(18)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.07, blue: 0.20),
                        Color(red: 0.10, green: 0.11, blue: 0.33),
                        Color(red: 0.15, green: 0.11, blue: 0.34)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Canvas { context, size in
                    for index in 0..<56 {
                        let fx = CGFloat((index * 73 + 23) % 100) / 100
                        let fy = CGFloat((index * 51 + 5) % 100) / 100
                        let x = fx * size.width
                        let y = fy * size.height
                        let radius = CGFloat(1.1 + Double(index % 3) * 0.45)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                            with: .color(.white.opacity(0.08 + Double(index % 5) * 0.05))
                        )
                    }
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .padding(.horizontal, 16)
        .homeParallax(intensity: 18)
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(ConstellationTypeScale.sectionTitle)
                .foregroundStyle(.white)
            Text(label)
                .font(ConstellationTypeScale.caption)
                .foregroundStyle(.white.opacity(0.76))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HomeQuickAddPill: View {
    let label: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(label)
            }
            .font(ConstellationTypeScale.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.16))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct HomeSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ConstellationTypeScale.sectionTitle)
                .foregroundStyle(ConstellationPalette.deepIndigo)
            Text(subtitle)
                .font(ConstellationTypeScale.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }
}

private struct HomeFocusPanel: View {
    let coverage: Double
    let crossMediaThemeCount: Int
    let podcastThemesReadyCount: Int
    let strongestThemeLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current Focus")
                .font(ConstellationTypeScale.sectionTitle)
                .foregroundStyle(.white.opacity(0.95))

            Text("Strongest theme: \(strongestThemeLabel)")
                .font(ConstellationTypeScale.supporting)
                .foregroundStyle(.white.opacity(0.82))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Coverage")
                    Spacer()
                    Text("\(Int(coverage * 100))%")
                }
                .font(ConstellationTypeScale.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
                ProgressView(value: coverage)
                    .tint(ConstellationPalette.accentSoft)
            }

            HStack(spacing: 14) {
                detailMetric("\(crossMediaThemeCount)", label: "Cross-media links")
                detailMetric("\(podcastThemesReadyCount)", label: "Podcast episodes ready")
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.10))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .homeParallax(intensity: 6)
    }

    private func detailMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ConstellationTypeScale.supporting.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeInsightMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ConstellationTypeScale.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(ConstellationTypeScale.cardTitle)
                .foregroundStyle(ConstellationPalette.deepIndigo)
            Text(subtitle)
                .font(ConstellationTypeScale.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 192, height: 126, alignment: .topLeading)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.38), lineWidth: 1.0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .homeParallax(intensity: 8)
    }
}

private struct HomeMediaMixCard: View {
    let counts: [(String, Int, Color, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Media Mix")
                .font(ConstellationTypeScale.caption)
                .foregroundStyle(.secondary)
            ForEach(counts, id: \.0) { type, count, color, symbol in
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Text(type)
                        .font(ConstellationTypeScale.caption)
                    Spacer()
                    Text("\(count)")
                        .font(ConstellationTypeScale.caption.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 192, height: 126, alignment: .topLeading)
        .background(Color.white.opacity(0.92))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ConstellationPalette.border.opacity(0.35), lineWidth: 0.9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .homeParallax(intensity: 8)
    }
}

private struct HomeImmersiveLaunchCard: View {
    let itemCount: Int
    let themeCount: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                RotatingConstellationPreview(time: t)
                    .mask(RoundedRectangle(cornerRadius: 22, style: .continuous))

                LinearGradient(
                    colors: [Color.black.opacity(0.35), Color.black.opacity(0.12), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Enter Immersive Graph")
                                .font(ConstellationTypeScale.sectionTitle)
                                .foregroundStyle(.white)
                            Text("\(itemCount) nodes · \(themeCount) themes")
                                .font(ConstellationTypeScale.caption)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                }
                .padding(16)
            }
        }
        .frame(height: 190)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
        }
        .homeParallax(intensity: 12)
    }
}

private struct RotatingConstellationPreview: View {
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.56, y: size.height * 0.55)
            let r1 = min(size.width, size.height) * 0.26
            let r2 = min(size.width, size.height) * 0.36
            let a1 = CGFloat(time * 0.55)
            let a2 = CGFloat(time * -0.37)

            let ring1 = points(center: center, radius: r1, count: 7, rotation: a1)
            let ring2 = points(center: center, radius: r2, count: 9, rotation: a2)
            let all = ring1 + ring2

            for idx in 0..<all.count {
                let from = all[idx]
                let to = all[(idx + 3) % all.count]
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(Color.white.opacity(0.12)), lineWidth: 0.8)
            }

            for (idx, p) in all.enumerated() {
                let radius = CGFloat(2.2 + Double(idx % 3) * 0.8)
                let color = idx % 4 == 0 ? ConstellationPalette.accentSoft : Color.white
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(color.opacity(0.88))
                )
            }
        }
    }

    private func points(center: CGPoint, radius: CGFloat, count: Int, rotation: CGFloat) -> [CGPoint] {
        (0..<count).map { i in
            let theta = (CGFloat(i) / CGFloat(count)) * 2 * .pi + rotation
            return CGPoint(
                x: center.x + cos(theta) * radius,
                y: center.y + sin(theta) * radius
            )
        }
    }
}

private struct HomeMomentumRow: View {
    let item: HomeMomentumItem

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(item.color.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: item.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.color)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(ConstellationTypeScale.supporting.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(ConstellationTypeScale.caption)
                    .foregroundStyle(.white.opacity(0.66))
            }

            Spacer()

            Text(item.date, style: .date)
                .font(ConstellationTypeScale.caption)
                .foregroundStyle(.white.opacity(0.66))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .foregroundStyle(.white.opacity(0.92))
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.12))
        }
        .homeParallax(intensity: 3)
    }
}

private struct HomePulseMetric {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
}

private enum HomeContinueActionKind {
    case resumeEpisode
    case generatePodcastThemes
    case reviewMissingThemes
}

private struct HomeContinueAction: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let kind: HomeContinueActionKind
    let targetEpisodeID: String?
}

private struct HomeValueNarrativeCard: View {
    let narrative: String
    let insight: HomeCrossMediaInsight?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ConstellationPalette.accentSoft)
                Text("Why This Matters")
                    .font(ConstellationTypeScale.sectionTitle)
                    .foregroundStyle(.white.opacity(0.95))
            }

            Text(narrative)
                .font(ConstellationTypeScale.supporting)
                .foregroundStyle(.white.opacity(0.84))
                .lineSpacing(2)

            if let insight {
                HStack(spacing: 8) {
                    HomeNarrativeTag(text: insight.theme.replacingOccurrences(of: "-", with: " ").capitalized, tint: .purple)
                    HomeNarrativeTag(text: "\(Set(insight.entries.map(\.mediaLabel)).count) media types", tint: .cyan)
                    HomeNarrativeTag(text: "\(insight.entries.count) linked items", tint: .green)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.09))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HomeNarrativeTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.24))
            .clipShape(Capsule())
    }
}

private struct HomeKnowledgePulseCard: View {
    let metrics: [HomePulseMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Knowledge Pulse")
                .font(ConstellationTypeScale.sectionTitle)
                .foregroundStyle(.white.opacity(0.95))

            ForEach(metrics, id: \.title) { metric in
                HStack(spacing: 10) {
                    Image(systemName: metric.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(metric.tint)
                        .frame(width: 24, height: 24)
                        .background(metric.tint.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.title)
                            .font(ConstellationTypeScale.caption)
                            .foregroundStyle(.white.opacity(0.72))
                        Text(metric.value)
                            .font(ConstellationTypeScale.supporting.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(2)
                        Text(metric.detail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.09))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HomeContinueLoopCard: View {
    let actions: [HomeContinueAction]
    let onTap: (HomeContinueAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Loop")
                .font(ConstellationTypeScale.sectionTitle)
                .foregroundStyle(.white.opacity(0.95))

            if actions.isEmpty {
                Text("You're caught up. Add more media to generate fresh loops.")
                    .font(ConstellationTypeScale.caption)
                    .foregroundStyle(.white.opacity(0.74))
            } else {
                ForEach(actions) { action in
                    Button {
                        onTap(action)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(action.tint)
                                .frame(width: 24, height: 24)
                                .background(action.tint.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(ConstellationTypeScale.supporting.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.94))
                                Text(action.detail)
                                    .font(ConstellationTypeScale.caption)
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.09))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HomeExplainablePickRow: View {
    let suggestion: HomeSuggestion

    var body: some View {
        HStack(spacing: 12) {
            RemotePosterImageView(imageURL: suggestion.posterURL?.absoluteString, contentMode: .fill) {
                Rectangle().fill(Color.gray.opacity(0.24))
            }
            .frame(width: 62, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(suggestion.title)
                    .font(ConstellationTypeScale.supporting.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(2)

                Text(suggestion.subtitle)
                    .font(ConstellationTypeScale.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Text(suggestion.reason)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)

                Text(mediaLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(mediaColor.opacity(0.22))
                    .clipShape(Capsule())
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(12)
        .background(Color.white.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var mediaLabel: String {
        switch suggestion.mediaType {
        case .movie: return "Movie"
        case .tv: return "TV"
        case .book: return "Book"
        }
    }

    private var mediaColor: Color {
        switch suggestion.mediaType {
        case .movie: return .blue
        case .tv: return .green
        case .book: return .orange
        }
    }
}

private struct HomeEmptyState: View {
    let onAddMovie: () -> Void
    let onAddTV: () -> Void
    let onAddBook: () -> Void
    let onAddPodcast: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(ConstellationPalette.accentSoft)
            Text("Your constellation starts here")
                .font(ConstellationTypeScale.cardTitle)
                .foregroundStyle(.white)
            Text("Add a few items across media types and the app will start surfacing meaningful cross-media connections.")
                .font(ConstellationTypeScale.supporting)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)

            HStack(spacing: 8) {
                HomeQuickActionButton(label: "Movie", symbol: "film.fill", color: .blue, action: onAddMovie)
                HomeQuickActionButton(label: "TV", symbol: "tv.fill", color: .green, action: onAddTV)
            }
            HStack(spacing: 8) {
                HomeQuickActionButton(label: "Book", symbol: "book.closed.fill", color: .orange, action: onAddBook)
                HomeQuickActionButton(label: "Podcast", symbol: "mic.fill", color: .pink, action: onAddPodcast)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.10))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

private struct HomeQuickActionButton: View {
    let label: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(label)
            }
            .font(ConstellationTypeScale.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct HomeSuggestionSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.16))
                .frame(width: 120, height: 180)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.gray.opacity(0.16))
                .frame(width: 110, height: 14)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.gray.opacity(0.12))
                .frame(width: 72, height: 11)
        }
        .frame(width: 120, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .redacted(reason: .placeholder)
        .homeParallax(intensity: 6)
    }
}

struct StatCard: View {
    let title: String
    let count: Int
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.title)
            
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MovieRow: View {
    let movie: Movie
    
    var body: some View {
        HStack(spacing: 12) {
            if let posterURL = movie.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Text("🎬")
                                .font(.largeTitle)
                        }
                }
                .frame(width: 60, height: 90)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
                    .overlay {
                        Text("🎬")
                            .font(.largeTitle)
                    }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let year = movie.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let rating = movie.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                        }
                        .foregroundStyle(.yellow)
                    }
                }
                
                if !movie.themes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(movie.themes.prefix(3), id: \.self) { theme in
                                Text(theme)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(12)
                            }
                            
                            if movie.themes.count > 3 {
                                Text("+\(movie.themes.count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Extracting themes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct TVShowRow: View {
    let show: TVShow
    
    var body: some View {
        HStack(spacing: 12) {
            if let posterURL = show.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay {
                            Text("📺")
                                .font(.largeTitle)
                        }
                }
                .frame(width: 60, height: 90)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
                    .overlay {
                        Text("📺")
                            .font(.largeTitle)
                    }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(show.title)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    if let year = show.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let rating = show.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                        }
                        .foregroundStyle(.yellow)
                    }
                }
                
                if !show.themes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(show.themes.prefix(3), id: \.self) { theme in
                                Text(theme)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .cornerRadius(12)
                            }
                            
                            if show.themes.count > 3 {
                                Text("+\(show.themes.count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Extracting themes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            if let coverURL = book.coverURL, let url = URL(string: coverURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay { Text("📚").font(.largeTitle) }
                }
                .frame(width: 60, height: 90)
                .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 90)
                    .cornerRadius(8)
                    .overlay { Text("📚").font(.largeTitle) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let year = book.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let author = book.author {
                        Text(author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let rating = book.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                            Text(String(format: "%.1f", rating))
                                .font(.caption)
                        }
                        .foregroundStyle(.yellow)
                    }
                }

                if !book.themes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(book.themes.prefix(3), id: \.self) { theme in
                                Text(theme)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .cornerRadius(12)
                            }

                            if book.themes.count > 3 {
                                Text("+\(book.themes.count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Extracting themes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

private enum HomeSuggestionMediaType: String, Codable {
    case movie
    case tv
    case book
}

private enum HomeSuggestionMediaTypeHint {
    case movie
    case tv
    case book
    case unknown
}

private struct HomeSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let posterURL: URL?
    let reason: String
    let mediaType: HomeSuggestionMediaType
    let score: Double
    let movie: TMDBMovie?
    let tvShow: TMDBTVShow?
    let book: HardcoverBooksService.SearchBook?

    init(
        id: String,
        title: String,
        subtitle: String,
        posterURL: URL?,
        reason: String,
        mediaType: HomeSuggestionMediaType,
        score: Double,
        movie: TMDBMovie? = nil,
        tvShow: TMDBTVShow? = nil,
        book: HardcoverBooksService.SearchBook? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.reason = reason
        self.mediaType = mediaType
        self.score = score
        self.movie = movie
        self.tvShow = tvShow
        self.book = book
    }
}

private struct HomeSuggestionCard: View {
    let suggestion: HomeSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemotePosterImageView(imageURL: suggestion.posterURL?.absoluteString, contentMode: .fill) {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(suggestion.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)

            Text(suggestion.subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))

            Text(suggestion.reason)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)

            Text(
                suggestion.mediaType == .movie
                    ? "Movie"
                    : suggestion.mediaType == .tv
                        ? "TV"
                        : "Book"
            )
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (
                        suggestion.mediaType == .movie
                            ? Color.blue
                            : suggestion.mediaType == .tv
                                ? Color.green
                                : Color.orange
                    ).opacity(0.24)
                )
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .frame(width: 120, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white.opacity(0.94))
        .homeParallax(intensity: 7)
    }
}

private struct HomeStarfieldBackground: View {
    private let stars: [CGPoint] = (0..<180).map { index in
        let x = CGFloat((index * 67 + 17) % 100) / 100
        let y = CGFloat((index * 43 + 29) % 100) / 100
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.14),
                    Color(red: 0.05, green: 0.08, blue: 0.24),
                    Color(red: 0.08, green: 0.09, blue: 0.27)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                for (index, star) in stars.enumerated() {
                    let x = star.x * size.width
                    let y = star.y * size.height
                    let radius = CGFloat(0.8 + Double(index % 4) * 0.45)
                    let alpha = 0.16 + Double(index % 6) * 0.06
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(Color.white.opacity(alpha))
                    )
                }
            }

            LinearGradient(
                colors: [Color.black.opacity(0.18), .clear, Color.black.opacity(0.26)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private extension View {
    func homeEntrance(step: Int, active: Bool) -> some View {
        self
            .opacity(active ? 1 : 0)
            .offset(y: active ? 0 : 18)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.86)
                    .delay(Double(step) * 0.025),
                value: active
            )
    }

    func homeParallax(intensity: CGFloat) -> some View {
        modifier(HomeParallaxModifier(intensity: intensity))
    }
}

private struct HomeParallaxModifier: ViewModifier {
    let intensity: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.visualEffect { base, proxy in
                let minY = proxy.frame(in: .global).minY
                let normalized = (minY - 120) / 620
                let clamped = max(-1, min(1, normalized))
                return base.offset(y: -clamped * intensity)
            }
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                Movie.self,
                TVShow.self,
                Book.self,
                PodcastEpisode.self,
                PodcastHighlight.self,
                Theme.self,
                ItemCollection.self
            ],
            inMemory: true
        )
}
