//
//  ConstellationGraphView.swift
//  Constellation
//
//  Created by Codex on 2/27/26.
//

import SwiftUI
import UIKit
import os

private enum GraphMotion {
    static let quick = Animation.easeInOut(duration: 0.22)
    static let standard = Animation.easeInOut(duration: 0.28)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.88)
}

/// Main composition view for the Constellation graph experience.
/// Home shows an independent 3D preview, while immersive mode exposes full filtering.
struct ConstellationGraphView: View {
    @Environment(\.dismiss) private var dismiss

    let movies: [Movie]
    let tvShows: [TVShow]
    let books: [Book]
    let collections: [ItemCollection]
    let autoLaunchImmersive: Bool
    
    @State private var selectedNodeID: String?
    @State private var filter: ConstellationGraphFilter = .all
    @State private var showImmersiveMode = false
    @State private var selectedThemeFilter: String = ConstellationGraphFilterToken.all
    @State private var selectedCollectionFilter: String = ConstellationGraphFilterToken.all
    @State private var showGenres = true
    @State private var densityMode: ConstellationGraphDensityMode = .simple
    @State private var labelDensity: ConstellationGraphLabelDensity = .medium
    @State private var homeResetToken: Int = 0
    @State private var hasHomeGraphInteraction = false
    @State private var genreToastMessage: String?
    @State private var genreToastWorkItem: DispatchWorkItem?
    
    @State private var selectedMovie: Movie?
    @State private var selectedTVShow: TVShow?
    @State private var selectedBook: Book?
    @State private var selectedTheme: ConstellationThemeSelection?
    @State private var selectedGenre: ConstellationGenreSelection?

    init(
        movies: [Movie],
        tvShows: [TVShow],
        books: [Book],
        collections: [ItemCollection],
        autoLaunchImmersive: Bool = false
    ) {
        self.movies = movies
        self.tvShows = tvShows
        self.books = books
        self.collections = collections
        self.autoLaunchImmersive = autoLaunchImmersive
    }
    
    // MARK: - Body
    var body: some View {
        let themeOptions = Array(Set(movies.flatMap(normalizedThemes(for:)) + tvShows.flatMap(normalizedThemes(for:)) + books.flatMap(normalizedThemes(for:)))).sorted()
        let collectionOptions = collections.sorted { $0.name < $1.name }
        
        let homeGraph = buildGraph(themeFilter: nil, collectionFilter: nil, densityMode: .detailed, includeGenres: showGenres)
        let homeGraphFiltered = applyConstellationGraphFilter(nodes: homeGraph.nodes, edges: homeGraph.edges, filter: .all)
        let homeNodes = homeGraphFiltered.nodes
        let homeEdges = homeGraphFiltered.edges
        
        let selectedTheme = selectedThemeFilter == ConstellationGraphFilterToken.all ? nil : selectedThemeFilter
        let selectedCollection = selectedCollectionFilter == ConstellationGraphFilterToken.all ? nil : selectedCollectionFilter
        let immersiveGraph = buildGraph(themeFilter: selectedTheme, collectionFilter: selectedCollection, densityMode: densityMode, includeGenres: showGenres)
        
        Group {
            if autoLaunchImmersive {
                Color.clear
                    .frame(height: 1)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Constellation Graph")
                                .font(.headline)
                            Text("Tap the brain to open immersive mode with filters and deep exploration")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        BrainPortalButton {
                            showImmersiveMode = true
                        }
                    }

                    GeometryReader { proxy in
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemGray6))

                            Constellation3DPreviewWebView(
                                nodes: homeNodes,
                                edges: homeEdges,
                                selectedNodeID: $selectedNodeID,
                                resetToken: homeResetToken,
                                onInteraction: {
                                    hasHomeGraphInteraction = true
                                },
                                onOpenNode: { nodeID in
                                    guard let node = homeNodes.first(where: { $0.id == nodeID }) else { return }
                                    openNode(node)
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            if hasHomeGraphInteraction {
                                VStack {
                                    HStack {
                                        Button {
                                            resetViewport()
                                        } label: {
                                            Label("Reset", systemImage: "scope")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.black.opacity(0.35))
                                                .foregroundStyle(.white)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)

                                        Spacer()
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                            }

                            if homeNodes.isEmpty {
                                ContentUnavailableView(
                                    "No Graph Nodes",
                                    systemImage: "network",
                                    description: Text("Add more items to render meaningful graph connections")
                                )
                            }

                            VStack {
                                HStack {
                                    Spacer()
                                    genresTogglePill
                                }
                                Spacer()
                            }
                            .padding(12)

                            if let genreToastMessage {
                                VStack {
                                    Spacer()
                                    Text(genreToastMessage)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.black.opacity(0.65))
                                        .clipShape(Capsule())
                                        .padding(.bottom, 10)
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .frame(height: 440)
                    .animation(.spring(response: 0.46, dampingFraction: 0.84), value: selectedThemeFilter)
                    .animation(.spring(response: 0.46, dampingFraction: 0.84), value: selectedCollectionFilter)
                    .animation(.spring(response: 0.46, dampingFraction: 0.84), value: filter)
                    .animation(.spring(response: 0.46, dampingFraction: 0.84), value: densityMode)

                    if let selected = homeNodes.first(where: { $0.id == selectedNodeID }) {
                        selectedNodePanel(selected)
                    }
                }
            }
        }
        .sheet(item: $selectedMovie) { movie in
            NavigationStack { MovieDetailView(movie: movie) }
        }
        .sheet(item: $selectedTVShow) { show in
            NavigationStack { TVShowDetailView(show: show) }
        }
        .sheet(item: $selectedBook) { book in
            NavigationStack { BookDetailView(book: book) }
        }
        .sheet(item: $selectedTheme) { theme in
            NavigationStack { ThemeDetailView(themeName: theme.id) }
        }
        .sheet(item: $selectedGenre) { genre in
            NavigationStack { GenreDetailView(genreName: genre.id) }
        }
        .fullScreenCover(isPresented: $showImmersiveMode) {
            ImmersiveConstellationView(
                graph: immersiveGraph,
                movies: movies,
                tvShows: tvShows,
                books: books,
                filter: $filter,
                labelDensity: $labelDensity,
                densityMode: $densityMode,
                showGenres: $showGenres,
                selectedThemeFilter: $selectedThemeFilter,
                selectedCollectionFilter: $selectedCollectionFilter,
                themeOptions: themeOptions,
                collectionOptions: collectionOptions,
                onClose: {
                    showImmersiveMode = false
                    if autoLaunchImmersive { dismiss() }
                }
            )
        }
        .onChange(of: selectedThemeFilter) { _, _ in resetViewport() }
        .onChange(of: selectedCollectionFilter) { _, _ in resetViewport() }
        .onChange(of: filter) { _, _ in resetViewport() }
        .onChange(of: showGenres) { _, _ in resetViewport() }
        .onChange(of: showGenres) { _, newValue in
            showGenreToast(enabled: newValue)
        }
        .onChange(of: densityMode) { _, _ in resetViewport() }
        .onChange(of: labelDensity) { _, _ in
            selectedNodeID = nil
        }
        .onAppear {
            if autoLaunchImmersive, !showImmersiveMode {
                DispatchQueue.main.async {
                    showImmersiveMode = true
                }
            }
        }
    }
    
    // MARK: - UI Helpers
    @ViewBuilder
    private func selectedNodePanel(_ node: ConstellationGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(node.kind.icon)
                Text(node.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                Text(node.kind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                openNode(node)
            } label: {
                Label("Open Detail", systemImage: "arrow.up.right.square")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var genresTogglePill: some View {
        HStack(spacing: 8) {
            Text("Genres")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Toggle("Genres", isOn: $showGenres)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.orange)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.42))
        .clipShape(Capsule())
    }
    
    // MARK: - Actions
    private func openNode(_ node: ConstellationGraphNode) {
        switch node.kind {
        case .movie:
            if let idString = node.reference, let id = UUID(uuidString: idString) {
                selectedMovie = movies.first(where: { $0.id == id })
            }
        case .tvShow:
            if let idString = node.reference, let id = UUID(uuidString: idString) {
                selectedTVShow = tvShows.first(where: { $0.id == id })
            }
        case .book:
            if let idString = node.reference, let id = UUID(uuidString: idString) {
                selectedBook = books.first(where: { $0.id == id })
            }
        case .theme:
            if let theme = node.reference {
                selectedTheme = ConstellationThemeSelection(id: theme)
            }
        case .genre:
            if let genre = node.reference {
                selectedGenre = ConstellationGenreSelection(id: genre)
            }
        }
    }

    private func showGenreToast(enabled: Bool) {
        genreToastWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            genreToastMessage = enabled ? "Genres On" : "Genres Off"
        }
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                genreToastMessage = nil
            }
        }
        genreToastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
    
    // MARK: - Graph Construction
    private func buildGraph(themeFilter: String?, collectionFilter: String?, densityMode: ConstellationGraphDensityMode, includeGenres: Bool) -> ConstellationGraphData {
        let recentMovieIDs = Set(movies.prefix(14).map { $0.id.uuidString })
        let recentShowIDs = Set(tvShows.prefix(14).map { $0.id.uuidString })
        let recentBookIDs = Set(books.prefix(14).map { $0.id.uuidString })
        let collectionMovieIDs = Set(collections.flatMap(\.movieIDs))
        let collectionShowIDs = Set(collections.flatMap(\.showIDs))
        let collectionBookIDs = Set(collections.flatMap(\.bookIDs))
        let movieCap = densityMode == .simple ? 10 : 18
        let showCap = densityMode == .simple ? 10 : 18
        let bookCap = densityMode == .simple ? 10 : 18
        let themeCap = densityMode == .simple ? 12 : 24
        let genreCap = densityMode == .simple ? 5 : 10
        
        var selectedMovies = Array(
            movies.filter { recentMovieIDs.contains($0.id.uuidString) || collectionMovieIDs.contains($0.id.uuidString) }
                .prefix(movieCap)
        )
        var selectedShows = Array(
            tvShows.filter { recentShowIDs.contains($0.id.uuidString) || collectionShowIDs.contains($0.id.uuidString) }
                .prefix(showCap)
        )
        var selectedBooks = Array(
            books.filter { recentBookIDs.contains($0.id.uuidString) || collectionBookIDs.contains($0.id.uuidString) }
                .prefix(bookCap)
        )
        
        if let collectionFilter,
           let collection = collections.first(where: { $0.id.uuidString == collectionFilter }) {
            let movieSet = Set(collection.movieIDs)
            let showSet = Set(collection.showIDs)
            let bookSet = Set(collection.bookIDs)
            selectedMovies = selectedMovies.filter { movieSet.contains($0.id.uuidString) }
            selectedShows = selectedShows.filter { showSet.contains($0.id.uuidString) }
            selectedBooks = selectedBooks.filter { bookSet.contains($0.id.uuidString) }
        }
        
        if let themeFilter {
            selectedMovies = selectedMovies.filter { normalizedThemes(for: $0).contains(themeFilter) }
            selectedShows = selectedShows.filter { normalizedThemes(for: $0).contains(themeFilter) }
            selectedBooks = selectedBooks.filter { normalizedThemes(for: $0).contains(themeFilter) }
        }

        let themeCounts = Dictionary(grouping: (selectedMovies.flatMap(normalizedThemes(for:)) + selectedShows.flatMap(normalizedThemes(for:)) + selectedBooks.flatMap(normalizedThemes(for:))), by: { $0 })
            .mapValues(\.count)
        let genreCounts = Dictionary(grouping: (selectedMovies.flatMap(normalizedGenres(for:)) + selectedShows.flatMap(normalizedGenres(for:)) + selectedBooks.flatMap(normalizedGenres(for:))), by: { $0 })
            .mapValues(\.count)
        
        let topThemes: [String]
        if let themeFilter {
            topThemes = themeCounts.keys.contains(themeFilter) ? [themeFilter] : []
        } else {
            let rankedThemes = themeCounts
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .map(\.key)
            // Keep a broad enough theme surface so nodes with valid themes do not appear "orphaned".
            topThemes = Array(rankedThemes.prefix(themeCap))
        }

        let topGenres: [String]
        if includeGenres {
            topGenres = genreCounts
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(genreCap)
                .map(\.key)
        } else {
            topGenres = []
        }
        
        var nodes: [ConstellationGraphNode] = []
        var edgeMeta: [String: ConstellationGraphEdgeAggregate] = [:]
        
        for movie in selectedMovies {
            let node = ConstellationGraphNode(id: "movie::\(movie.id.uuidString)", title: movie.title, kind: .movie, reference: movie.id.uuidString)
            nodes.append(node)
        }
        
        for show in selectedShows {
            let node = ConstellationGraphNode(id: "show::\(show.id.uuidString)", title: show.title, kind: .tvShow, reference: show.id.uuidString)
            nodes.append(node)
        }

        for book in selectedBooks {
            let node = ConstellationGraphNode(id: "book::\(book.id.uuidString)", title: book.title, kind: .book, reference: book.id.uuidString)
            nodes.append(node)
        }
        
        for theme in topThemes {
            let node = ConstellationGraphNode(id: "theme::\(theme)", title: theme, kind: .theme, reference: theme)
            nodes.append(node)
        }

        for genre in topGenres {
            let node = ConstellationGraphNode(id: "genre::\(genre)", title: genre, kind: .genre, reference: genre)
            nodes.append(node)
        }

        let topThemeSet = Set(topThemes)
        let topGenreSet = Set(topGenres)
        
        for movie in selectedMovies {
            let fromID = "movie::\(movie.id.uuidString)"
            for theme in normalizedThemes(for: movie) where topThemeSet.contains(theme) {
                incrementEdge(fromID: fromID, toID: "theme::\(theme)", source: .theme, in: &edgeMeta)
            }
        }

        for show in selectedShows {
            let fromID = "show::\(show.id.uuidString)"
            for theme in normalizedThemes(for: show) where topThemeSet.contains(theme) {
                incrementEdge(fromID: fromID, toID: "theme::\(theme)", source: .theme, in: &edgeMeta)
            }
        }

        for book in selectedBooks {
            let fromID = "book::\(book.id.uuidString)"
            for theme in normalizedThemes(for: book) where topThemeSet.contains(theme) {
                incrementEdge(fromID: fromID, toID: "theme::\(theme)", source: .theme, in: &edgeMeta)
            }
        }

        for movie in selectedMovies {
            let fromID = "movie::\(movie.id.uuidString)"
            for genre in normalizedGenres(for: movie) where topGenreSet.contains(genre) {
                incrementEdge(fromID: fromID, toID: "genre::\(genre)", source: .genre, in: &edgeMeta)
            }
        }

        for show in selectedShows {
            let fromID = "show::\(show.id.uuidString)"
            for genre in normalizedGenres(for: show) where topGenreSet.contains(genre) {
                incrementEdge(fromID: fromID, toID: "genre::\(genre)", source: .genre, in: &edgeMeta)
            }
        }

        for book in selectedBooks {
            let fromID = "book::\(book.id.uuidString)"
            for genre in normalizedGenres(for: book) where topGenreSet.contains(genre) {
                incrementEdge(fromID: fromID, toID: "genre::\(genre)", source: .genre, in: &edgeMeta)
            }
        }

        if includeGenres {
            for movie in selectedMovies {
                let movieThemes = normalizedThemes(for: movie).filter { topThemeSet.contains($0) }
                let movieGenres = normalizedGenres(for: movie).filter { topGenreSet.contains($0) }
                for theme in movieThemes {
                    for genre in movieGenres {
                        incrementEdge(fromID: "theme::\(theme)", toID: "genre::\(genre)", source: .genre, in: &edgeMeta)
                    }
                }
            }

            for show in selectedShows {
                let showThemes = normalizedThemes(for: show).filter { topThemeSet.contains($0) }
                let showGenres = normalizedGenres(for: show).filter { topGenreSet.contains($0) }
                for theme in showThemes {
                    for genre in showGenres {
                        incrementEdge(fromID: "theme::\(theme)", toID: "genre::\(genre)", source: .genre, in: &edgeMeta)
                    }
                }
            }

            for book in selectedBooks {
                let bookThemes = normalizedThemes(for: book).filter { topThemeSet.contains($0) }
                let bookGenres = normalizedGenres(for: book).filter { topGenreSet.contains($0) }
                for theme in bookThemes {
                    for genre in bookGenres {
                        incrementEdge(fromID: "theme::\(theme)", toID: "genre::\(genre)", source: .genre, in: &edgeMeta)
                    }
                }
            }
        }
        
        let movieIDs = Set(selectedMovies.map { $0.id.uuidString })
        let showIDs = Set(selectedShows.map { $0.id.uuidString })
        let bookIDs = Set(selectedBooks.map { $0.id.uuidString })
        
        for collection in collections {
            let members = (collection.movieIDs.filter { movieIDs.contains($0) }.map { "movie::\($0)" }
                + collection.showIDs.filter { showIDs.contains($0) }.map { "show::\($0)" }
                + collection.bookIDs.filter { bookIDs.contains($0) }.map { "book::\($0)" })
            
            guard members.count >= 2 else { continue }
            
            for i in 0..<(members.count - 1) {
                for j in (i + 1)..<members.count {
                    incrementEdge(fromID: members[i], toID: members[j], source: .collection, in: &edgeMeta)
                }
            }
        }
        
        let edges = edgeMeta.map { key, value -> ConstellationGraphEdge in
            let ids = key.split(separator: "|").map(String.init)
            return ConstellationGraphEdge(
                id: key,
                fromID: ids[0],
                toID: ids[1],
                weight: value.weight,
                source: value.source
            )
        }
        let prioritizedEdges = edges
            .sorted {
                if $0.source.priority == $1.source.priority {
                    if $0.weight == $1.weight {
                        return $0.id < $1.id
                    }
                    return $0.weight > $1.weight
                }
                return $0.source.priority > $1.source.priority
            }
        let maxEdgeCount = min(320, max(180, nodes.count * 5))
        let cappedEdges = prioritizedEdges.prefix(maxEdgeCount)

        let finalEdges = Array(cappedEdges)
        let positions = computeDynamicPositions(
            nodes: nodes,
            edges: finalEdges,
            themeFilter: themeFilter,
            collectionFilter: collectionFilter
        )
        
        return ConstellationGraphData(nodes: nodes, edges: finalEdges, positions: positions)
    }
    
    // MARK: - Graph Math
    private func resetViewport() {
        selectedNodeID = nil
        homeResetToken += 1
        hasHomeGraphInteraction = false
    }
    
    private func ringPosition(index: Int, total: Int, radius: CGFloat, phase: CGFloat) -> CGPoint {
        guard total > 0 else { return .zero }
        let angle = (CGFloat(index) / CGFloat(total)) * (.pi * 2) + phase
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }
    
    private func incrementEdge(fromID: String, toID: String, source: ConstellationGraphEdgeSource, in storage: inout [String: ConstellationGraphEdgeAggregate]) {
        let key = fromID < toID ? "\(fromID)|\(toID)" : "\(toID)|\(fromID)"
        var current = storage[key] ?? ConstellationGraphEdgeAggregate(weight: 0, source: source)
        current.weight += 1
        current.source = current.source.merged(with: source)
        storage[key] = current
    }

    private func normalizedThemes(for movie: Movie) -> [String] {
        ThemeExtractor.shared.normalizeThemes(movie.themes)
    }

    private func normalizedThemes(for show: TVShow) -> [String] {
        ThemeExtractor.shared.normalizeThemes(show.themes)
    }

    private func normalizedThemes(for book: Book) -> [String] {
        ThemeExtractor.shared.normalizeThemes(book.themes)
    }

    private func normalizedGenres(for movie: Movie) -> [String] {
        normalizeGenres(movie.genres)
    }

    private func normalizedGenres(for show: TVShow) -> [String] {
        normalizeGenres(show.genres)
    }

    private func normalizedGenres(for book: Book) -> [String] {
        normalizeGenres(book.genres)
    }

    private func normalizeGenres(_ rawGenres: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for genre in rawGenres {
            let normalized = genre
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&", with: " and ")
                .replacingOccurrences(of: #"[^\p{L}\p{N}\s-]"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
                .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            guard normalized.count >= 3 else { continue }
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }
    
    private func computeDynamicPositions(
        nodes: [ConstellationGraphNode],
        edges: [ConstellationGraphEdge],
        themeFilter: String?,
        collectionFilter: String?
    ) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        
        let coreNodes = nodes.filter { $0.kind == .theme || $0.kind == .genre }.sorted { $0.id < $1.id }
        let media = nodes.filter { $0.kind == .movie || $0.kind == .tvShow || $0.kind == .book }.sorted { $0.id < $1.id }
        let adjacency = buildAdjacency(edges: edges)
        
        // Focused mode: one chosen theme in center, connected media around it.
        if let themeFilter {
            let focusedThemeID = "theme::\(themeFilter)"
            if coreNodes.contains(where: { $0.id == focusedThemeID }) {
                positions[focusedThemeID] = .zero
                
                let connectedMedia = media.filter { adjacency[$0.id, default: []].contains(focusedThemeID) }
                for (index, item) in connectedMedia.enumerated() {
                    positions[item.id] = ringPosition(index: index, total: max(connectedMedia.count, 1), radius: 0.56, phase: deterministicPhase(for: item.id))
                }
                
                let nonConnected = media.filter { positions[$0.id] == nil }
                for (index, item) in nonConnected.enumerated() {
                    positions[item.id] = ringPosition(index: index, total: max(nonConnected.count, 1), radius: 0.88, phase: .pi / 7)
                }
                
                return resolveNodeOverlaps(positions: positions, nodes: nodes)
            }
        }
        
        // Collection-focused mode: keep core (themes + genres), but tighten members.
        if collectionFilter != nil {
            for (index, coreNode) in coreNodes.enumerated() {
                positions[coreNode.id] = ringPosition(index: index, total: max(coreNodes.count, 1), radius: 0.36, phase: .pi / 11)
            }
            
            let themedMedia = media.filter { !adjacency[$0.id, default: []].isDisjoint(with: Set(coreNodes.map(\.id))) }
            let themedIDs = Set(themedMedia.map(\.id))
            let plainMedia = media.filter { !themedIDs.contains($0.id) }
            
            for (index, item) in themedMedia.enumerated() {
                let anchor = nearestCoreNodeID(for: item.id, coreNodes: coreNodes, adjacency: adjacency) ?? coreNodes.first?.id
                let center = anchor.flatMap { positions[$0] } ?? .zero
                let local = ringPosition(index: index, total: max(themedMedia.count, 1), radius: 0.2, phase: deterministicPhase(for: item.id))
                positions[item.id] = CGPoint(x: center.x + local.x, y: center.y + local.y)
            }
            
            for (index, item) in plainMedia.enumerated() {
                positions[item.id] = ringPosition(index: index, total: max(plainMedia.count, 1), radius: 0.92, phase: .pi / 5)
            }
            
            return resolveNodeOverlaps(positions: positions, nodes: nodes)
        }
        
        // General mode: core nodes in center, media clustered around nearest core node.
        for (index, coreNode) in coreNodes.enumerated() {
            positions[coreNode.id] = ringPosition(index: index, total: max(coreNodes.count, 1), radius: 0.37, phase: .pi / 12)
        }
        
        if coreNodes.isEmpty {
            let movies = media.filter { $0.kind == .movie }
            let shows = media.filter { $0.kind == .tvShow }
            let books = media.filter { $0.kind == .book }
            for (index, item) in movies.enumerated() {
                positions[item.id] = ringPosition(index: index, total: max(movies.count, 1), radius: 0.74, phase: 0)
            }
            for (index, item) in shows.enumerated() {
                positions[item.id] = ringPosition(index: index, total: max(shows.count, 1), radius: 0.9, phase: .pi / 8)
            }
            for (index, item) in books.enumerated() {
                positions[item.id] = ringPosition(index: index, total: max(books.count, 1), radius: 0.82, phase: .pi / 5)
            }
            return resolveNodeOverlaps(positions: positions, nodes: nodes)
        }
        
        var byAnchor: [String: [ConstellationGraphNode]] = [:]
        for item in media {
            let anchor = nearestCoreNodeID(for: item.id, coreNodes: coreNodes, adjacency: adjacency) ?? "unassigned"
            byAnchor[anchor, default: []].append(item)
        }
        
        let anchors = byAnchor.keys.sorted()
        for anchor in anchors {
            guard let items = byAnchor[anchor] else { continue }
            let clusterCenter: CGPoint
            
            if anchor == "unassigned" {
                clusterCenter = CGPoint(x: 0, y: 0)
            } else {
                let coreCenter = positions[anchor] ?? .zero
                clusterCenter = CGPoint(x: coreCenter.x * 1.28, y: coreCenter.y * 1.28)
            }
            
            for (index, item) in items.enumerated() {
                let local = ringPosition(
                    index: index,
                    total: max(items.count, 1),
                    radius: items.count <= 3 ? 0.14 : 0.2,
                    phase: deterministicPhase(for: item.id)
                )
                positions[item.id] = CGPoint(x: clusterCenter.x + local.x, y: clusterCenter.y + local.y)
            }
        }
        
        return resolveNodeOverlaps(positions: positions, nodes: nodes)
    }
    
    private func buildAdjacency(edges: [ConstellationGraphEdge]) -> [String: Set<String>] {
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.fromID, default: []].insert(edge.toID)
            adjacency[edge.toID, default: []].insert(edge.fromID)
        }
        return adjacency
    }
    
    private func nearestCoreNodeID(for mediaID: String, coreNodes: [ConstellationGraphNode], adjacency: [String: Set<String>]) -> String? {
        let neighborCoreNodes = adjacency[mediaID, default: []]
            .filter { $0.hasPrefix("theme::") || $0.hasPrefix("genre::") }
            .sorted()
        if let direct = neighborCoreNodes.first {
            return direct
        }
        return coreNodes.first?.id
    }
    
    private func deterministicPhase(for id: String) -> CGFloat {
        let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let fraction = CGFloat(sum % 628) / 100.0
        return fraction
    }

    private func resolveNodeOverlaps(positions: [String: CGPoint], nodes: [ConstellationGraphNode]) -> [String: CGPoint] {
        var result = positions
        let kindByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.kind) })
        let ids = result.keys.sorted()
        guard ids.count > 1 else { return result }
        
        for _ in 0..<22 {
            var delta: [String: CGPoint] = [:]
            
            for i in 0..<(ids.count - 1) {
                for j in (i + 1)..<ids.count {
                    let aID = ids[i]
                    let bID = ids[j]
                    guard let a = result[aID], let b = result[bID] else { continue }
                    
                    var dx = b.x - a.x
                    var dy = b.y - a.y
                    var distance = sqrt(dx * dx + dy * dy)
                    
                    if distance < 0.0001 {
                        let angle = deterministicPhase(for: "\(aID)|\(bID)")
                        dx = cos(angle)
                        dy = sin(angle)
                        distance = 1
                    }
                    
                    let isCrossType = kindByID[aID] == .theme || kindByID[bID] == .theme || kindByID[aID] == .genre || kindByID[bID] == .genre
                    let minDistance: CGFloat = isCrossType ? 0.18 : 0.13
                    guard distance < minDistance else { continue }
                    
                    let push = (minDistance - distance) * 0.5
                    let ux = dx / distance
                    let uy = dy / distance
                    
                    let aShift = CGPoint(x: -ux * push, y: -uy * push)
                    let bShift = CGPoint(x: ux * push, y: uy * push)
                    
                    delta[aID] = CGPoint(
                        x: (delta[aID]?.x ?? 0) + aShift.x,
                        y: (delta[aID]?.y ?? 0) + aShift.y
                    )
                    delta[bID] = CGPoint(
                        x: (delta[bID]?.x ?? 0) + bShift.x,
                        y: (delta[bID]?.y ?? 0) + bShift.y
                    )
                }
            }
            
            var moved = false
            for id in ids {
                guard let p = result[id], let d = delta[id] else { continue }
                let next = CGPoint(
                    x: min(0.96, max(-0.96, p.x + d.x * 0.92)),
                    y: min(0.96, max(-0.96, p.y + d.y * 0.92))
                )
                if abs(next.x - p.x) + abs(next.y - p.y) > 0.0007 {
                    moved = true
                }
                result[id] = next
            }
            
            if !moved { break }
        }
        
        return result
    }
}

private struct BrainPortalButton: View {
    let action: () -> Void
    @State private var pulse = false
    
    // MARK: - Body
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.55), Color.indigo.opacity(0.1)],
                            center: .center,
                            startRadius: 4,
                            endRadius: 36
                        )
                    )
                    .frame(width: pulse ? 54 : 44, height: pulse ? 54 : 44)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .cyan.opacity(0.7), radius: 5)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct ImmersiveConstellationView: View {
    let graph: ConstellationGraphData
    let movies: [Movie]
    let tvShows: [TVShow]
    let books: [Book]
    @Binding var filter: ConstellationGraphFilter
    @Binding var labelDensity: ConstellationGraphLabelDensity
    @Binding var densityMode: ConstellationGraphDensityMode
    @Binding var showGenres: Bool
    @Binding var selectedThemeFilter: String
    @Binding var selectedCollectionFilter: String
    let themeOptions: [String]
    let collectionOptions: [ItemCollection]
    let onClose: () -> Void
    
    @State private var selectedNodeID: String?
    @State private var focusTargetNodeID: String?
    @State private var webResetToken: Int = 0
    @State private var fitToContentToken: Int = 0
    @State private var graphRevision: Int = 0
    @State private var viewportSnapshot: ConstellationGraphViewportSnapshot = .empty
    @State private var lastViewportUpdateAt: Date = .distantPast
    @State private var visibleKinds: Set<ConstellationGraphNodeKind> = [.movie, .tvShow, .book, .theme, .genre]
    @State private var hasAppliedPersistedState = false
    @State private var showCoachmark = false
    @State private var showingControlsSheet = false
    @State private var showingSearchSheet = false
    @State private var searchQuery = ""
    @State private var isInteractingWithGraph = false
    @State private var interactionStartedAt: Date?
    @State private var selectedMovie: Movie?
    @State private var selectedTVShow: TVShow?
    @State private var selectedBook: Book?
    @State private var selectedTheme: ConstellationThemeSelection?
    @State private var selectedGenre: ConstellationGenreSelection?

    @AppStorage("immersive_graph_filter") private var persistedFilterRaw = "all"
    @AppStorage("immersive_graph_density") private var persistedDensityRaw = "detailed"
    @AppStorage("immersive_graph_labels") private var persistedLabelsRaw = "medium"
    @AppStorage("immersive_graph_show_genres") private var persistedShowGenres = true
    @AppStorage("immersive_graph_theme") private var persistedThemeFilter = ConstellationGraphFilterToken.all
    @AppStorage("immersive_graph_collection") private var persistedCollectionFilter = ConstellationGraphFilterToken.all
    @AppStorage("immersive_graph_visible_kinds") private var persistedVisibleKindsRaw = "movie,tvShow,book,theme,genre"
    @AppStorage("immersive_graph_zoom_scale") private var persistedZoomScale = 1.0
    @AppStorage("immersive_graph_translate_x") private var persistedTranslateX = 0.0
    @AppStorage("immersive_graph_translate_y") private var persistedTranslateY = 0.0
    @AppStorage("did_show_neural_graph_coachmark") private var didShowCoachmark = false
    private let logger = Logger(subsystem: "com.VivekSen.Constellation", category: "ImmersiveGraph")
    
    private var filteredGraph: (nodes: [ConstellationGraphNode], edges: [ConstellationGraphEdge]) {
        let base = applyConstellationGraphFilter(nodes: graph.nodes, edges: graph.edges, filter: filter)
        let allowedIDs = Set(base.nodes.filter { visibleKinds.contains($0.kind) }.map(\.id))
        return (
            nodes: base.nodes.filter { allowedIDs.contains($0.id) },
            edges: base.edges.filter { allowedIDs.contains($0.fromID) && allowedIDs.contains($0.toID) }
        )
    }

    private var persistedTransform: ConstellationGraphTransform {
        ConstellationGraphTransform(
            zoomScale: persistedZoomScale,
            translateX: persistedTranslateX,
            translateY: persistedTranslateY
        )
    }

    private var searchableNodes: [ConstellationGraphNode] {
        let base = filteredGraph.nodes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return base }
        let q = searchQuery.lowercased()
        return base.filter {
            $0.title.lowercased().contains(q) || $0.kind.label.lowercased().contains(q)
        }
    }

    private var offscreenNodeCount: Int {
        guard !viewportSnapshot.points.isEmpty else { return 0 }
        let minX = viewportSnapshot.viewportMinX
        let maxX = viewportSnapshot.viewportMaxX
        let minY = viewportSnapshot.viewportMinY
        let maxY = viewportSnapshot.viewportMaxY
        return viewportSnapshot.points.reduce(into: 0) { count, point in
            let isOut = point.x < minX || point.x > maxX || point.y < minY || point.y > maxY
            if isOut { count += 1 }
        }
    }
    
    // MARK: - Body
    var body: some View {
        let selectedTheme = selectedThemeFilter == ConstellationGraphFilterToken.all ? nil : selectedThemeFilter
        let selectedCollection = selectedCollectionFilter == ConstellationGraphFilterToken.all ? nil : selectedCollectionFilter
        
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.05, blue: 0.12), Color(red: 0.04, green: 0.01, blue: 0.18), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            StarfieldBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    Text("Neural Constellation")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            withAnimation(GraphMotion.quick) {
                                showingSearchSheet = true
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                                .foregroundStyle(.white)
                        }

                        Button {
                            withAnimation(GraphMotion.quick) {
                                resetViewport()
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Text(summaryLine(selectedTheme: selectedTheme, selectedCollection: selectedCollection))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                
                GeometryReader { proxy in
                    let compactMiniMap = proxy.size.width < 390
                    ZStack(alignment: compactMiniMap ? .topTrailing : .bottomTrailing) {
                        ConstellationD3WebView(
                            nodes: filteredGraph.nodes,
                            edges: filteredGraph.edges,
                            selectedNodeID: $selectedNodeID,
                            focusNodeID: focusTargetNodeID,
                            resetToken: webResetToken,
                            fitToContentToken: fitToContentToken,
                            graphRevision: graphRevision,
                            initialTransform: persistedTransform,
                            labelDensity: labelDensity,
                            onOpenNode: { nodeID in
                                guard let node = filteredGraph.nodes.first(where: { $0.id == nodeID }) else { return }
                                triggerOpenHaptic()
                                openNode(node)
                            },
                            onViewportChange: { snapshot in
                                applyViewportSnapshot(snapshot)
                            },
                            onInteractionChanged: { isActive in
                                isInteractingWithGraph = isActive
                                if isActive {
                                    interactionStartedAt = Date()
                                    logger.debug("graph_interaction_started")
                                } else {
                                    let elapsed = Date().timeIntervalSince(interactionStartedAt ?? Date())
                                    logger.debug("graph_interaction_ended duration=\(elapsed, privacy: .public)")
                                    interactionStartedAt = nil
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)

                        GraphEdgeVignette(snapshot: viewportSnapshot)
                            .padding(.horizontal, 16)
                            .allowsHitTesting(false)

                        VStack {
                            HStack {
                                Spacer()
                                VStack(alignment: .trailing, spacing: 8) {
                                    GraphNavigatorMiniMap(
                                        snapshot: viewportSnapshot,
                                        isCompact: compactMiniMap,
                                        hideLabels: true
                                    )

                                    if offscreenNodeCount > 0 {
                                        Button {
                                            fitGraphToContent()
                                        } label: {
                                            Label("\(offscreenNodeCount) off-screen", systemImage: "scope")
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 8)
                                                .background(Color.black.opacity(0.55))
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.white)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 22)

                        if filteredGraph.nodes.isEmpty {
                            VStack(spacing: 10) {
                                Text("No nodes match current controls")
                                    .font(.subheadline.weight(.semibold))
                                Button("Clear Filters & Show All") {
                                    clearAllControls()
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.cyan.opacity(0.24))
                                .clipShape(Capsule())
                            }
                            .foregroundStyle(.white)
                            .padding(14)
                            .background(Color.black.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if showCoachmark {
                            GraphCoachmarkCard {
                                dismissCoachmark()
                            }
                            .padding(.horizontal, 28)
                            .padding(.top, 18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }

                        VStack(spacing: 10) {
                            Spacer()

                            if let selected = filteredGraph.nodes.first(where: { $0.id == selectedNodeID }) {
                                GraphSelectionInsightCard(
                                    node: selected,
                                    connections: connectionInsights(for: selected, in: filteredGraph)
                                ) {
                                    triggerOpenHaptic()
                                    openNode(selected)
                                } onFocus: {
                                    focusSelectedNode()
                                } onPrevious: {
                                    selectAdjacentNode(in: filteredGraph.nodes, direction: -1)
                                } onNext: {
                                    selectAdjacentNode(in: filteredGraph.nodes, direction: 1)
                                } onHide: {
                                    withAnimation(GraphMotion.quick) {
                                        selectedNodeID = nil
                                    }
                                }
                                .padding(.horizontal, 22)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            HStack {
                                Button {
                                    withAnimation(GraphMotion.quick) {
                                        showingControlsSheet = true
                                    }
                                } label: {
                                    Label("Graph Controls", systemImage: "slider.horizontal.3")
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.black.opacity(0.52))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)

                                Spacer()
                            }
                            .padding(.horizontal, 22)
                            .padding(.bottom, 16)
                        }
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
        }
        .foregroundStyle(.white)
        .animation(GraphMotion.spring, value: selectedNodeID)
        .animation(GraphMotion.standard, value: showCoachmark)
        .animation(GraphMotion.standard, value: isInteractingWithGraph)
        .onAppear {
            applyPersistedStateIfNeeded()
        }
        .onChange(of: selectedNodeID) { _, newValue in
            guard newValue != nil else { return }
            triggerSelectionHaptic()
            logger.debug("graph_node_selected")
        }
        .onChange(of: filter) { _, value in
            persistedFilterRaw = rawValue(for: value)
            graphRevision += 1
        }
        .onChange(of: densityMode) { _, value in
            persistedDensityRaw = rawValue(for: value)
            graphRevision += 1
        }
        .onChange(of: labelDensity) { _, value in
            persistedLabelsRaw = rawValue(for: value)
            graphRevision += 1
        }
        .onChange(of: showGenres) { _, value in
            persistedShowGenres = value
            graphRevision += 1
        }
        .onChange(of: selectedThemeFilter) { _, value in
            persistedThemeFilter = value
            graphRevision += 1
        }
        .onChange(of: selectedCollectionFilter) { _, value in
            persistedCollectionFilter = value
            graphRevision += 1
        }
        .onChange(of: visibleKinds) { _, value in
            persistedVisibleKindsRaw = value.map { $0.d3Kind }.sorted().joined(separator: ",")
            graphRevision += 1
        }
        .sheet(isPresented: $showingControlsSheet) {
            NavigationStack {
                GraphControlsSheetView(
                    filter: $filter,
                    selectedThemeFilter: $selectedThemeFilter,
                    selectedCollectionFilter: $selectedCollectionFilter,
                    densityMode: $densityMode,
                    labelDensity: $labelDensity,
                    showGenres: $showGenres,
                    visibleKinds: $visibleKinds,
                    themeOptions: themeOptions,
                    collectionOptions: collectionOptions,
                    onReset: {
                        clearAllControls()
                    }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSearchSheet) {
            NavigationStack {
                GraphNodeSearchView(
                    query: $searchQuery,
                    nodes: searchableNodes
                ) { node in
                    selectedNodeID = node.id
                    focusTargetNodeID = node.id
                    showingSearchSheet = false
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedMovie) { movie in
            NavigationStack { MovieDetailView(movie: movie) }
        }
        .sheet(item: $selectedTVShow) { show in
            NavigationStack { TVShowDetailView(show: show) }
        }
        .sheet(item: $selectedBook) { book in
            NavigationStack { BookDetailView(book: book) }
        }
        .sheet(item: $selectedTheme) { theme in
            NavigationStack { ThemeDetailView(themeName: theme.id) }
        }
        .sheet(item: $selectedGenre) { genre in
            NavigationStack { GenreDetailView(genreName: genre.id) }
        }
    }
    
    // MARK: - Actions
    private func resetViewport() {
        selectedNodeID = nil
        focusTargetNodeID = nil
        webResetToken += 1
    }

    private func fitGraphToContent() {
        selectedNodeID = nil
        focusTargetNodeID = nil
        fitToContentToken += 1
    }

    private func applyViewportSnapshot(_ snapshot: ConstellationGraphViewportSnapshot) {
        let now = Date()
        guard now.timeIntervalSince(lastViewportUpdateAt) > 0.22 else { return }
        lastViewportUpdateAt = now
        viewportSnapshot = snapshot
        persistedZoomScale = snapshot.zoomScale
        persistedTranslateX = snapshot.translateX
        persistedTranslateY = snapshot.translateY
    }

    private func summaryLine(selectedTheme: String?, selectedCollection: String?) -> String {
        let themeText = selectedTheme == nil ? "All Themes" : selectedTheme!.replacingOccurrences(of: "-", with: " ").capitalized
        let collectionText = selectedCollection == nil ? "All Collections" : "1 Collection"
        return "\(filter.title) · \(themeText) · \(collectionText)"
    }

    private func focusSelectedNode() {
        guard let selectedNodeID else { return }
        focusTargetNodeID = selectedNodeID
    }

    private func selectAdjacentNode(in nodes: [ConstellationGraphNode], direction: Int) {
        guard !nodes.isEmpty else { return }
        let ordered = nodes.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        if let currentSelectedNodeID = selectedNodeID,
           let currentIndex = ordered.firstIndex(where: { $0.id == currentSelectedNodeID }) {
            let nextIndex = (currentIndex + direction + ordered.count) % ordered.count
            withAnimation(GraphMotion.quick) {
                selectedNodeID = ordered[nextIndex].id
            }
        } else {
            withAnimation(GraphMotion.quick) {
                selectedNodeID = ordered[0].id
            }
        }
    }

    private func toggle(kind: ConstellationGraphNodeKind) {
        if visibleKinds.contains(kind) {
            if visibleKinds.count > 1 {
                visibleKinds.remove(kind)
            }
        } else {
            visibleKinds.insert(kind)
        }
    }

    private func clearAllControls() {
        filter = .all
        densityMode = .detailed
        labelDensity = .medium
        showGenres = true
        selectedThemeFilter = ConstellationGraphFilterToken.all
        selectedCollectionFilter = ConstellationGraphFilterToken.all
        visibleKinds = [.movie, .tvShow, .book, .theme, .genre]
        resetViewport()
    }

    private func openNode(_ node: ConstellationGraphNode) {
        logger.debug("graph_open_node kind=\(node.kind.label, privacy: .public)")
        switch node.kind {
        case .movie:
            if let idString = node.reference, let id = UUID(uuidString: idString) {
                selectedMovie = movies.first(where: { $0.id == id })
            }
        case .tvShow:
            if let idString = node.reference, let id = UUID(uuidString: idString) {
                selectedTVShow = tvShows.first(where: { $0.id == id })
            }
        case .book:
            if let idString = node.reference, let id = UUID(uuidString: idString) {
                selectedBook = books.first(where: { $0.id == id })
            }
        case .theme:
            if let theme = node.reference {
                selectedTheme = ConstellationThemeSelection(id: theme)
            }
        case .genre:
            if let genre = node.reference {
                selectedGenre = ConstellationGenreSelection(id: genre)
            }
        }
    }

    private func connectionInsights(for node: ConstellationGraphNode, in graphData: (nodes: [ConstellationGraphNode], edges: [ConstellationGraphEdge])) -> [GraphConnectionInsight] {
        let nodeByID = Dictionary(uniqueKeysWithValues: graphData.nodes.map { ($0.id, $0) })
        return graphData.edges
            .compactMap { edge -> GraphConnectionInsight? in
                guard edge.fromID == node.id || edge.toID == node.id else { return nil }
                let otherID = edge.fromID == node.id ? edge.toID : edge.fromID
                guard let other = nodeByID[otherID] else { return nil }
                let reason: String
                switch edge.source {
                case .theme:
                    reason = "Shared thematic structure"
                case .genre:
                    reason = "Shared genre characteristics"
                case .collection:
                    reason = "Co-located in one of your collections"
                case .hybrid:
                    reason = "Multiple overlap signals (theme/genre/collection)"
                }
                return GraphConnectionInsight(title: other.title, kindLabel: other.kind.label, weight: edge.weight, reason: reason)
            }
            .sorted {
                if $0.weight == $1.weight { return $0.title < $1.title }
                return $0.weight > $1.weight
            }
            .prefix(3)
            .map { $0 }
    }

    private func dismissCoachmark() {
        didShowCoachmark = true
        withAnimation(GraphMotion.quick) {
            showCoachmark = false
        }
    }

    private func applyPersistedStateIfNeeded() {
        guard !hasAppliedPersistedState else { return }
        hasAppliedPersistedState = true

        if let restoredFilter = filter(from: persistedFilterRaw) {
            filter = restoredFilter
        }
        if let restoredDensity = density(from: persistedDensityRaw) {
            densityMode = restoredDensity
        }
        if let restoredLabels = labelDensity(from: persistedLabelsRaw) {
            labelDensity = restoredLabels
        }
        showGenres = persistedShowGenres

        let validTheme = persistedThemeFilter == ConstellationGraphFilterToken.all || themeOptions.contains(persistedThemeFilter)
        selectedThemeFilter = validTheme ? persistedThemeFilter : ConstellationGraphFilterToken.all

        let validCollection = persistedCollectionFilter == ConstellationGraphFilterToken.all || collectionOptions.contains(where: { $0.id.uuidString == persistedCollectionFilter })
        selectedCollectionFilter = validCollection ? persistedCollectionFilter : ConstellationGraphFilterToken.all

        let restoredKinds = Set(
            persistedVisibleKindsRaw
                .split(separator: ",")
                .compactMap { ConstellationGraphNodeKind.fromD3Kind(String($0)) }
        )
        if !restoredKinds.isEmpty {
            visibleKinds = restoredKinds
        }

        showCoachmark = !didShowCoachmark
    }

    private func rawValue(for value: ConstellationGraphFilter) -> String {
        switch value {
        case .all: return "all"
        case .movies: return "movies"
        case .tvShows: return "tvShows"
        case .books: return "books"
        case .themes: return "themes"
        case .genres: return "genres"
        }
    }

    private func filter(from raw: String) -> ConstellationGraphFilter? {
        switch raw {
        case "all": return .all
        case "movies": return .movies
        case "tvShows": return .tvShows
        case "books": return .books
        case "themes": return .themes
        case "genres": return .genres
        default: return nil
        }
    }

    private func rawValue(for value: ConstellationGraphDensityMode) -> String {
        switch value {
        case .simple: return "simple"
        case .detailed: return "detailed"
        }
    }

    private func density(from raw: String) -> ConstellationGraphDensityMode? {
        switch raw {
        case "simple": return .simple
        case "detailed": return .detailed
        default: return nil
        }
    }

    private func rawValue(for value: ConstellationGraphLabelDensity) -> String {
        switch value {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    private func labelDensity(from raw: String) -> ConstellationGraphLabelDensity? {
        switch raw {
        case "low": return .low
        case "medium": return .medium
        case "high": return .high
        default: return nil
        }
    }

    private func triggerSelectionHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    private func triggerOpenHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

private extension ConstellationGraphNodeKind {
    static func fromD3Kind(_ raw: String) -> ConstellationGraphNodeKind? {
        switch raw {
        case "movie": return .movie
        case "tvShow": return .tvShow
        case "book": return .book
        case "theme": return .theme
        case "genre": return .genre
        default: return nil
        }
    }
}

private struct GraphCoachmarkCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Tips")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.95))

            Text("Pinch to zoom, drag to pan, tap a node to select, double-tap to open.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.86))

            Button("Got it") {
                onDismiss()
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.cyan.opacity(0.26))
            .clipShape(Capsule())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.48))
        )
    }
}

private struct GraphConnectionInsight: Identifiable {
    let id = UUID()
    let title: String
    let kindLabel: String
    let weight: Int
    let reason: String
}

private struct GraphSelectionInsightCard: View {
    let node: ConstellationGraphNode
    let connections: [GraphConnectionInsight]
    let onOpen: () -> Void
    let onFocus: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 10) {
                Text(node.kind.icon)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(node.kind.label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }

            if connections.isEmpty {
                Text("No strong adjacent links in current filter scope.")
                    .font(.caption)
                    .lineSpacing(2)
                    .foregroundStyle(.white.opacity(0.78))
            } else {
                ForEach(connections) { connection in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(connection.title) (\(connection.kindLabel))")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(connection.reason) · strength \(connection.weight)")
                            .font(.caption2)
                            .lineSpacing(2)
                            .foregroundStyle(.white.opacity(0.74))
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    onPrevious()
                } label: {
                    Label("Prev", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onNext()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Open", action: onOpen)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Focus", action: onFocus)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Hide", action: onHide)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.caption.weight(.semibold))
            .tint(.cyan)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.54))
        )
        .gesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    let absHorizontal = abs(horizontal)
                    let absVertical = abs(vertical)

                    if vertical > 56, absVertical > absHorizontal {
                        onHide()
                        return
                    }

                    guard absHorizontal > 44, absHorizontal > absVertical else { return }
                    if horizontal < 0 {
                        onNext()
                    } else {
                        onPrevious()
                    }
                }
        )
    }
}

private struct GraphNodeSearchView: View {
    @Binding var query: String
    let nodes: [ConstellationGraphNode]
    let onSelect: (ConstellationGraphNode) -> Void

    var body: some View {
        List(nodes) { node in
            Button {
                onSelect(node)
            } label: {
                HStack(spacing: 10) {
                    Text(node.kind.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.title)
                            .font(.subheadline)
                        Text(node.kind.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Find Node")
        .searchable(text: $query, prompt: "Search nodes")
    }
}

private struct GraphControlsSheetView: View {
    @Binding var filter: ConstellationGraphFilter
    @Binding var selectedThemeFilter: String
    @Binding var selectedCollectionFilter: String
    @Binding var densityMode: ConstellationGraphDensityMode
    @Binding var labelDensity: ConstellationGraphLabelDensity
    @Binding var showGenres: Bool
    @Binding var visibleKinds: Set<ConstellationGraphNodeKind>
    let themeOptions: [String]
    let collectionOptions: [ItemCollection]
    let onReset: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $filter) {
                    ForEach(ConstellationGraphFilter.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            } header: {
                sectionHeader("Type Filter")
            }

            Section {
                Picker("Theme", selection: $selectedThemeFilter) {
                    Text("All Themes").tag(ConstellationGraphFilterToken.all)
                    ForEach(themeOptions, id: \.self) { theme in
                        Text(theme.replacingOccurrences(of: "-", with: " ").capitalized).tag(theme)
                    }
                }
                Picker("Collection", selection: $selectedCollectionFilter) {
                    Text("All Collections").tag(ConstellationGraphFilterToken.all)
                    ForEach(collectionOptions, id: \.id) { collection in
                        Text(collection.name).tag(collection.id.uuidString)
                    }
                }
            } header: {
                sectionHeader("Theme & Collection")
            }

            Section {
                Picker("Density", selection: $densityMode) {
                    ForEach(ConstellationGraphDensityMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Labels", selection: $labelDensity) {
                    ForEach(ConstellationGraphLabelDensity.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Show Genres", isOn: $showGenres)
            } header: {
                sectionHeader("Graph")
            }

            Section {
                ForEach([ConstellationGraphNodeKind.movie, .tvShow, .book, .theme, .genre], id: \.self) { kind in
                    Toggle(kind.label, isOn: Binding(
                        get: { visibleKinds.contains(kind) },
                        set: { isEnabled in
                            if isEnabled {
                                visibleKinds.insert(kind)
                            } else if visibleKinds.count > 1 {
                                visibleKinds.remove(kind)
                            }
                        }
                    ))
                }
            } header: {
                sectionHeader("Visible Node Types")
            }

            Section {
                ForEach([ConstellationGraphNodeKind.movie, .tvShow, .book, .theme, .genre], id: \.self) { kind in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(kind.color)
                            .frame(width: 10, height: 10)
                        Text(kind.label)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(kind.icon)
                            .font(.subheadline)
                    }
                }

                ForEach(ConstellationGraphEdgeSource.allCases, id: \.self) { source in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(edgeLegendColor(for: source))
                            .frame(width: 16, height: 4)
                            .padding(.top, 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.legendTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(source.legendDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                sectionHeader("Legend")
            }

            Section {
                Button("Reset All Controls") {
                    onReset()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Graph Controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .tracking(0.2)
    }

    private func edgeLegendColor(for source: ConstellationGraphEdgeSource) -> Color {
        switch source {
        case .theme:
            return Color.gray
        case .genre:
            return Color.orange
        case .collection:
            return Color.cyan
        case .hybrid:
            return Color.mint
        }
    }
}

private struct GraphEdgeVignette: View {
    let snapshot: ConstellationGraphViewportSnapshot

    private var showLeft: Bool { snapshot.viewportMinX > snapshot.contentMinX + 2 }
    private var showRight: Bool { snapshot.viewportMaxX < snapshot.contentMaxX - 2 }
    private var showTop: Bool { snapshot.viewportMinY > snapshot.contentMinY + 2 }
    private var showBottom: Bool { snapshot.viewportMaxY < snapshot.contentMaxY - 2 }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                if showLeft {
                    LinearGradient(colors: [Color.black.opacity(0.32), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: min(24, w * 0.12), height: h)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                if showRight {
                    LinearGradient(colors: [.clear, Color.black.opacity(0.32)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: min(24, w * 0.12), height: h)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
                if showTop {
                    LinearGradient(colors: [Color.black.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(width: w, height: min(20, h * 0.1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                if showBottom {
                    LinearGradient(colors: [.clear, Color.black.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                        .frame(width: w, height: min(20, h * 0.1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }
}

private struct GraphNavigatorMiniMap: View {
    let snapshot: ConstellationGraphViewportSnapshot
    var isCompact: Bool = false
    var hideLabels: Bool = false

    private var worldWidth: Double {
        max(0.001, snapshot.contentMaxX - snapshot.contentMinX)
    }

    private var worldHeight: Double {
        max(0.001, snapshot.contentMaxY - snapshot.contentMinY)
    }

    private var viewportWidth: Double {
        max(0.001, snapshot.viewportMaxX - snapshot.viewportMinX)
    }

    private var viewportHeight: Double {
        max(0.001, snapshot.viewportMaxY - snapshot.viewportMinY)
    }

    private var hasOffscreenNodes: Bool {
        (viewportWidth < worldWidth * 0.97) || (viewportHeight < worldHeight * 0.97)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let viewX = ((snapshot.viewportMinX - snapshot.contentMinX) / worldWidth) * width
                let viewY = ((snapshot.viewportMinY - snapshot.contentMinY) / worldHeight) * height
                let viewW = (viewportWidth / worldWidth) * width
                let viewH = (viewportHeight / worldHeight) * height

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)

                    ForEach(snapshot.points, id: \.id) { point in
                        Circle()
                            .fill(point.isSelected ? Color.cyan.opacity(0.95) : Color.white.opacity(0.72))
                            .frame(width: point.isSelected ? 4.5 : 2.4, height: point.isSelected ? 4.5 : 2.4)
                            .offset(
                                x: min(max(0, ((point.x - snapshot.contentMinX) / worldWidth) * width), width - (point.isSelected ? 4.5 : 2.4)),
                                y: min(max(0, ((point.y - snapshot.contentMinY) / worldHeight) * height), height - (point.isSelected ? 4.5 : 2.4))
                            )
                    }

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.cyan.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.cyan.opacity(0.85), lineWidth: 1.2)
                        )
                        .frame(
                            width: max(10, min(width, viewW)),
                            height: max(10, min(height, viewH))
                        )
                        .offset(
                            x: max(0, min(width - max(10, min(width, viewW)), viewX)),
                            y: max(0, min(height - max(10, min(height, viewH)), viewY))
                        )
                }
            }
            .frame(width: isCompact ? 90 : 110, height: isCompact ? 64 : 78)

            if hasOffscreenNodes && !isCompact && !hideLabels {
                Text("Pan to explore more nodes")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .padding(isCompact ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.38))
        )
    }
}

private struct StarfieldBackground: View {
    private let stars: [CGPoint] = (0..<110).map { index in
        let x = CGFloat((index * 73) % 100) / 100.0
        let y = CGFloat((index * 41) % 100) / 100.0
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Body
    var body: some View {
        Canvas { context, size in
            for (index, star) in stars.enumerated() {
                let alpha = 0.2 + Double((index % 7)) * 0.06
                let radius = 0.8 + CGFloat(index % 3) * 0.6
                let center = CGPoint(x: star.x * size.width, y: star.y * size.height)

                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(Color.white.opacity(alpha))
                )
            }
        }
    }
}
