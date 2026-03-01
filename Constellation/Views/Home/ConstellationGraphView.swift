//
//  ConstellationGraphView.swift
//  Constellation
//
//  Created by Codex on 2/27/26.
//

import SwiftUI

/// Main composition view for the Constellation graph experience.
/// Home shows an independent 3D preview, while immersive mode exposes full filtering.
struct ConstellationGraphView: View {
    let movies: [Movie]
    let tvShows: [TVShow]
    let collections: [ItemCollection]
    
    @State private var selectedNodeID: String?
    @State private var filter: ConstellationGraphFilter = .all
    @State private var showImmersiveMode = false
    @State private var selectedThemeFilter: String = ConstellationGraphFilterToken.all
    @State private var selectedCollectionFilter: String = ConstellationGraphFilterToken.all
    @State private var densityMode: ConstellationGraphDensityMode = .simple
    @State private var labelDensity: ConstellationGraphLabelDensity = .medium
    @State private var homeResetToken: Int = 0
    @State private var hasHomeGraphInteraction = false
    
    @State private var selectedMovie: Movie?
    @State private var selectedTVShow: TVShow?
    @State private var selectedTheme: ConstellationThemeSelection?
    
    // MARK: - Body
    var body: some View {
        let themeOptions = Array(Set(movies.flatMap(\.themes) + tvShows.flatMap(\.themes))).sorted()
        let collectionOptions = collections.sorted { $0.name < $1.name }
        
        let homeGraph = buildGraph(themeFilter: nil, collectionFilter: nil, densityMode: .detailed)
        let homeGraphFiltered = applyConstellationGraphFilter(nodes: homeGraph.nodes, edges: homeGraph.edges, filter: .all)
        let homeNodes = homeGraphFiltered.nodes
        let homeEdges = homeGraphFiltered.edges
        
        let selectedTheme = selectedThemeFilter == ConstellationGraphFilterToken.all ? nil : selectedThemeFilter
        let selectedCollection = selectedCollectionFilter == ConstellationGraphFilterToken.all ? nil : selectedCollectionFilter
        let immersiveGraph = buildGraph(themeFilter: selectedTheme, collectionFilter: selectedCollection, densityMode: densityMode)
        
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
                }
            }
            .frame(height: 440)
            .animation(.spring(response: 0.46, dampingFraction: 0.84), value: selectedThemeFilter)
            .animation(.spring(response: 0.46, dampingFraction: 0.84), value: selectedCollectionFilter)
            .animation(.spring(response: 0.46, dampingFraction: 0.84), value: filter)
            .animation(.spring(response: 0.46, dampingFraction: 0.84), value: densityMode)
            
            VisibleNodeLegend(nodes: homeNodes, selectedNodeID: $selectedNodeID)
            
            if let selected = homeNodes.first(where: { $0.id == selectedNodeID }) {
                selectedNodePanel(selected)
            }
        }
        .sheet(item: $selectedMovie) { movie in
            NavigationStack { MovieDetailView(movie: movie) }
        }
        .sheet(item: $selectedTVShow) { show in
            NavigationStack { TVShowDetailView(show: show) }
        }
        .sheet(item: $selectedTheme) { theme in
            NavigationStack { ThemeDetailView(themeName: theme.id) }
        }
        .fullScreenCover(isPresented: $showImmersiveMode) {
            ImmersiveConstellationView(
                graph: immersiveGraph,
                filter: $filter,
                labelDensity: $labelDensity,
                densityMode: $densityMode,
                selectedThemeFilter: $selectedThemeFilter,
                selectedCollectionFilter: $selectedCollectionFilter,
                themeOptions: themeOptions,
                collectionOptions: collectionOptions,
                onClose: { showImmersiveMode = false },
                onOpenNode: { node in
                    showImmersiveMode = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        openNode(node)
                    }
                }
            )
        }
        .onChange(of: selectedThemeFilter) { _, _ in resetViewport() }
        .onChange(of: selectedCollectionFilter) { _, _ in resetViewport() }
        .onChange(of: filter) { _, _ in resetViewport() }
        .onChange(of: densityMode) { _, _ in resetViewport() }
        .onChange(of: labelDensity) { _, _ in
            selectedNodeID = nil
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
        case .theme:
            if let theme = node.reference {
                selectedTheme = ConstellationThemeSelection(id: theme)
            }
        }
    }
    
    // MARK: - Graph Construction
    private func buildGraph(themeFilter: String?, collectionFilter: String?, densityMode: ConstellationGraphDensityMode) -> ConstellationGraphData {
        let recentMovieIDs = Set(movies.prefix(14).map { $0.id.uuidString })
        let recentShowIDs = Set(tvShows.prefix(14).map { $0.id.uuidString })
        let collectionMovieIDs = Set(collections.flatMap(\.movieIDs))
        let collectionShowIDs = Set(collections.flatMap(\.showIDs))
        let movieCap = densityMode == .simple ? 10 : 18
        let showCap = densityMode == .simple ? 10 : 18
        let themeCap = densityMode == .simple ? 6 : 12
        
        var selectedMovies = Array(
            movies.filter { recentMovieIDs.contains($0.id.uuidString) || collectionMovieIDs.contains($0.id.uuidString) }
                .prefix(movieCap)
        )
        var selectedShows = Array(
            tvShows.filter { recentShowIDs.contains($0.id.uuidString) || collectionShowIDs.contains($0.id.uuidString) }
                .prefix(showCap)
        )
        
        if let collectionFilter,
           let collection = collections.first(where: { $0.id.uuidString == collectionFilter }) {
            let movieSet = Set(collection.movieIDs)
            let showSet = Set(collection.showIDs)
            selectedMovies = selectedMovies.filter { movieSet.contains($0.id.uuidString) }
            selectedShows = selectedShows.filter { showSet.contains($0.id.uuidString) }
        }
        
        if let themeFilter {
            selectedMovies = selectedMovies.filter { $0.themes.contains(themeFilter) }
            selectedShows = selectedShows.filter { $0.themes.contains(themeFilter) }
        }
        
        let themeCounts = Dictionary(grouping: (selectedMovies.flatMap(\.themes) + selectedShows.flatMap(\.themes)), by: { $0 })
            .mapValues(\.count)
        
        let topThemes: [String]
        if let themeFilter {
            topThemes = themeCounts.keys.contains(themeFilter) ? [themeFilter] : []
        } else {
            topThemes = themeCounts
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(themeCap)
                .map(\.key)
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
        
        for theme in topThemes {
            let node = ConstellationGraphNode(id: "theme::\(theme)", title: theme, kind: .theme, reference: theme)
            nodes.append(node)
        }
        
        let topThemeSet = Set(topThemes)
        
        for movie in selectedMovies {
            let fromID = "movie::\(movie.id.uuidString)"
            for theme in movie.themes where topThemeSet.contains(theme) {
                incrementEdge(fromID: fromID, toID: "theme::\(theme)", source: .theme, in: &edgeMeta)
            }
        }
        
        for show in selectedShows {
            let fromID = "show::\(show.id.uuidString)"
            for theme in show.themes where topThemeSet.contains(theme) {
                incrementEdge(fromID: fromID, toID: "theme::\(theme)", source: .theme, in: &edgeMeta)
            }
        }
        
        let movieIDs = Set(selectedMovies.map { $0.id.uuidString })
        let showIDs = Set(selectedShows.map { $0.id.uuidString })
        
        for collection in collections {
            let members = (collection.movieIDs.filter { movieIDs.contains($0) }.map { "movie::\($0)" }
                + collection.showIDs.filter { showIDs.contains($0) }.map { "show::\($0)" })
            
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
                    return $0.weight > $1.weight
                }
                return $0.source.priority > $1.source.priority
            }
            .prefix(130)
        
        let finalEdges = Array(prioritizedEdges)
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
    
    private func computeDynamicPositions(
        nodes: [ConstellationGraphNode],
        edges: [ConstellationGraphEdge],
        themeFilter: String?,
        collectionFilter: String?
    ) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        
        let themes = nodes.filter { $0.kind == .theme }.sorted { $0.id < $1.id }
        let media = nodes.filter { $0.kind != .theme }.sorted { $0.id < $1.id }
        let adjacency = buildAdjacency(edges: edges)
        
        // Focused mode: one chosen theme in center, connected media around it.
        if let themeFilter {
            let focusedThemeID = "theme::\(themeFilter)"
            if themes.contains(where: { $0.id == focusedThemeID }) {
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
        
        // Collection-focused mode: keep theme core, but tighten members.
        if collectionFilter != nil {
            for (index, theme) in themes.enumerated() {
                positions[theme.id] = ringPosition(index: index, total: max(themes.count, 1), radius: 0.36, phase: .pi / 11)
            }
            
            let themedMedia = media.filter { !adjacency[$0.id, default: []].isDisjoint(with: Set(themes.map(\.id))) }
            let themedIDs = Set(themedMedia.map(\.id))
            let plainMedia = media.filter { !themedIDs.contains($0.id) }
            
            for (index, item) in themedMedia.enumerated() {
                let anchor = nearestThemeID(for: item.id, themes: themes, adjacency: adjacency) ?? themes.first?.id
                let center = anchor.flatMap { positions[$0] } ?? .zero
                let local = ringPosition(index: index, total: max(themedMedia.count, 1), radius: 0.2, phase: deterministicPhase(for: item.id))
                positions[item.id] = CGPoint(x: center.x + local.x, y: center.y + local.y)
            }
            
            for (index, item) in plainMedia.enumerated() {
                positions[item.id] = ringPosition(index: index, total: max(plainMedia.count, 1), radius: 0.92, phase: .pi / 5)
            }
            
            return resolveNodeOverlaps(positions: positions, nodes: nodes)
        }
        
        // General mode: themes in core, media clustered around their strongest theme.
        for (index, theme) in themes.enumerated() {
            positions[theme.id] = ringPosition(index: index, total: max(themes.count, 1), radius: 0.37, phase: .pi / 12)
        }
        
        if themes.isEmpty {
            let movies = media.filter { $0.kind == .movie }
            let shows = media.filter { $0.kind == .tvShow }
            for (index, item) in movies.enumerated() {
                positions[item.id] = ringPosition(index: index, total: max(movies.count, 1), radius: 0.74, phase: 0)
            }
            for (index, item) in shows.enumerated() {
                positions[item.id] = ringPosition(index: index, total: max(shows.count, 1), radius: 0.9, phase: .pi / 8)
            }
            return resolveNodeOverlaps(positions: positions, nodes: nodes)
        }
        
        var byAnchor: [String: [ConstellationGraphNode]] = [:]
        for item in media {
            let anchor = nearestThemeID(for: item.id, themes: themes, adjacency: adjacency) ?? "unassigned"
            byAnchor[anchor, default: []].append(item)
        }
        
        let anchors = byAnchor.keys.sorted()
        for anchor in anchors {
            guard let items = byAnchor[anchor] else { continue }
            let clusterCenter: CGPoint
            
            if anchor == "unassigned" {
                clusterCenter = CGPoint(x: 0, y: 0)
            } else {
                let themeCenter = positions[anchor] ?? .zero
                clusterCenter = CGPoint(x: themeCenter.x * 1.28, y: themeCenter.y * 1.28)
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
    
    private func nearestThemeID(for mediaID: String, themes: [ConstellationGraphNode], adjacency: [String: Set<String>]) -> String? {
        let neighborThemes = adjacency[mediaID, default: []]
            .filter { $0.hasPrefix("theme::") }
            .sorted()
        if let direct = neighborThemes.first {
            return direct
        }
        return themes.first?.id
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
                    
                    let isCrossType = kindByID[aID] == .theme || kindByID[bID] == .theme
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
    @Binding var filter: ConstellationGraphFilter
    @Binding var labelDensity: ConstellationGraphLabelDensity
    @Binding var densityMode: ConstellationGraphDensityMode
    @Binding var selectedThemeFilter: String
    @Binding var selectedCollectionFilter: String
    let themeOptions: [String]
    let collectionOptions: [ItemCollection]
    let onClose: () -> Void
    let onOpenNode: (ConstellationGraphNode) -> Void
    
    @State private var selectedNodeID: String?
    @State private var webResetToken: Int = 0
    
    private var filteredGraph: (nodes: [ConstellationGraphNode], edges: [ConstellationGraphEdge]) {
        applyConstellationGraphFilter(nodes: graph.nodes, edges: graph.edges, filter: filter)
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
                    
                    if let selected = filteredGraph.nodes.first(where: { $0.id == selectedNodeID }) {
                        Button("Open") {
                            onOpenNode(selected)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.cyan.opacity(0.24))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    } else {
                        Color.clear.frame(width: 52, height: 1)
                    }
                    
                    Button {
                        resetViewport()
                    } label: {
                        Label("Reset", systemImage: "scope")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ConstellationGraphFilter.allCases, id: \.self) { option in
                            Button(option.title) {
                                filter = option
                                selectedNodeID = nil
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(filter == option ? Color.cyan.opacity(0.25) : Color.white.opacity(0.14))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                
                Picker("Density", selection: $densityMode) {
                    ForEach(ConstellationGraphDensityMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Picker("Labels", selection: $labelDensity) {
                    ForEach(ConstellationGraphLabelDensity.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                HStack(spacing: 8) {
                    Menu {
                        Picker("Theme", selection: $selectedThemeFilter) {
                            Text("All Themes").tag(ConstellationGraphFilterToken.all)
                            ForEach(themeOptions, id: \.self) { theme in
                                Text(theme.replacingOccurrences(of: "-", with: " ").capitalized).tag(theme)
                            }
                        }
                    } label: {
                        Label(
                            selectedTheme == nil ? "Theme: All" : "Theme: \(selectedTheme!.replacingOccurrences(of: "-", with: " ").capitalized)",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    
                    Menu {
                        Picker("Collection", selection: $selectedCollectionFilter) {
                            Text("All Collections").tag(ConstellationGraphFilterToken.all)
                            ForEach(collectionOptions, id: \.id) { collection in
                                Text(collection.name).tag(collection.id.uuidString)
                            }
                        }
                    } label: {
                        Label(
                            selectedCollection == nil ? "Collection: All" : "Collection: 1 selected",
                            systemImage: "square.stack.3d.up"
                        )
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.14))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                GeometryReader { _ in
                    ConstellationD3WebView(
                        nodes: filteredGraph.nodes,
                        edges: filteredGraph.edges,
                        selectedNodeID: $selectedNodeID,
                        resetToken: webResetToken,
                        labelDensity: labelDensity,
                        onOpenNode: { nodeID in
                            guard let node = filteredGraph.nodes.first(where: { $0.id == nodeID }) else { return }
                            onOpenNode(node)
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .foregroundStyle(.white)
    }
    
    // MARK: - Actions
    private func resetViewport() {
        selectedNodeID = nil
        webResetToken += 1
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
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                
                for (index, star) in stars.enumerated() {
                    let phase = sin(t * 1.5 + Double(index) * 0.38)
                    let alpha = 0.2 + (phase + 1.0) * 0.25
                    let radius = 0.8 + CGFloat((phase + 1.0) * 0.65)
                    let center = CGPoint(x: star.x * size.width, y: star.y * size.height)
                    
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(Color.white.opacity(alpha))
                    )
                }
            }
        }
    }
}

private struct VisibleNodeLegend: View {
    let nodes: [ConstellationGraphNode]
    @Binding var selectedNodeID: String?
    
    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visible Nodes")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(nodes.prefix(30)) { node in
                        Button {
                            selectedNodeID = node.id
                        } label: {
                            HStack(spacing: 6) {
                                Text(node.kind.icon)
                                Text(node.title)
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(selectedNodeID == node.id ? node.kind.color.opacity(0.25) : Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
