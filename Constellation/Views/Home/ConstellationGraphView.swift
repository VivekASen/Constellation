//
//  ConstellationGraphView.swift
//  Constellation
//
//  Created by Codex on 2/27/26.
//

import SwiftUI
import WebKit

struct ConstellationGraphView: View {
    let movies: [Movie]
    let tvShows: [TVShow]
    let collections: [ItemCollection]
    
    @State private var selectedNodeID: String?
    @State private var filter: GraphFilter = .all
    @State private var showImmersiveMode = false
    @State private var selectedThemeFilter: String = GraphFilterToken.all
    @State private var selectedCollectionFilter: String = GraphFilterToken.all
    @State private var densityMode: GraphDensityMode = .simple
    @State private var labelDensity: GraphLabelDensity = .medium
    @State private var homeResetToken: Int = 0
    
    @State private var selectedMovie: Movie?
    @State private var selectedTVShow: TVShow?
    @State private var selectedTheme: ThemeSelection?
    
    var body: some View {
        let themeOptions = Array(Set(movies.flatMap(\.themes) + tvShows.flatMap(\.themes))).sorted()
        let collectionOptions = collections.sorted { $0.name < $1.name }
        
        let homeGraph = buildGraph(themeFilter: nil, collectionFilter: nil, densityMode: .detailed)
        let homeGraphFiltered = applyGraphFilter(nodes: homeGraph.nodes, edges: homeGraph.edges, filter: .all)
        let homeNodes = homeGraphFiltered.nodes
        let homeEdges = homeGraphFiltered.edges
        
        let selectedTheme = selectedThemeFilter == GraphFilterToken.all ? nil : selectedThemeFilter
        let selectedCollection = selectedCollectionFilter == GraphFilterToken.all ? nil : selectedCollectionFilter
        let immersiveGraph = buildGraph(themeFilter: selectedTheme, collectionFilter: selectedCollection, densityMode: densityMode)
        
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Constellation Graph")
                        .font(.headline)
                    Text("Tap the brain to dive into immersive mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    resetViewport()
                } label: {
                    Label("Reset", systemImage: "scope")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.14))
                        .clipShape(Capsule())
                }
                
                BrainPortalButton {
                    showImmersiveMode = true
                }
            }
            
            HStack {
                Text("Use immersive mode for filters and deep exploration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Full Constellation") {
                    showImmersiveMode = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
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
                        onOpenNode: { nodeID in
                            guard let node = homeNodes.first(where: { $0.id == nodeID }) else { return }
                            openNode(node)
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
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
    
    @ViewBuilder
    private func selectedNodePanel(_ node: GraphNode) -> some View {
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
    
    private func openNode(_ node: GraphNode) {
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
                selectedTheme = ThemeSelection(id: theme)
            }
        }
    }
    
    private func buildGraph(themeFilter: String?, collectionFilter: String?, densityMode: GraphDensityMode) -> GraphData {
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
        
        var nodes: [GraphNode] = []
        var edgeMeta: [String: EdgeAggregate] = [:]
        
        for movie in selectedMovies {
            let node = GraphNode(id: "movie::\(movie.id.uuidString)", title: movie.title, kind: .movie, reference: movie.id.uuidString)
            nodes.append(node)
        }
        
        for show in selectedShows {
            let node = GraphNode(id: "show::\(show.id.uuidString)", title: show.title, kind: .tvShow, reference: show.id.uuidString)
            nodes.append(node)
        }
        
        for theme in topThemes {
            let node = GraphNode(id: "theme::\(theme)", title: theme, kind: .theme, reference: theme)
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
        
        let edges = edgeMeta.map { key, value -> GraphEdge in
            let ids = key.split(separator: "|").map(String.init)
            return GraphEdge(
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
        
        return GraphData(nodes: nodes, edges: finalEdges, positions: positions)
    }
    
    private func resetViewport() {
        selectedNodeID = nil
        homeResetToken += 1
    }
    
    private func ringPosition(index: Int, total: Int, radius: CGFloat, phase: CGFloat) -> CGPoint {
        guard total > 0 else { return .zero }
        let angle = (CGFloat(index) / CGFloat(total)) * (.pi * 2) + phase
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }
    
    private func incrementEdge(fromID: String, toID: String, source: GraphEdgeSource, in storage: inout [String: EdgeAggregate]) {
        let key = fromID < toID ? "\(fromID)|\(toID)" : "\(toID)|\(fromID)"
        var current = storage[key] ?? EdgeAggregate(weight: 0, source: source)
        current.weight += 1
        current.source = current.source.merged(with: source)
        storage[key] = current
    }
    
    private func computeDynamicPositions(
        nodes: [GraphNode],
        edges: [GraphEdge],
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
        
        var byAnchor: [String: [GraphNode]] = [:]
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
    
    private func buildAdjacency(edges: [GraphEdge]) -> [String: Set<String>] {
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.fromID, default: []].insert(edge.toID)
            adjacency[edge.toID, default: []].insert(edge.fromID)
        }
        return adjacency
    }
    
    private func nearestThemeID(for mediaID: String, themes: [GraphNode], adjacency: [String: Set<String>]) -> String? {
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

    private func resolveNodeOverlaps(positions: [String: CGPoint], nodes: [GraphNode]) -> [String: CGPoint] {
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
    let graph: GraphData
    @Binding var filter: GraphFilter
    @Binding var labelDensity: GraphLabelDensity
    @Binding var densityMode: GraphDensityMode
    @Binding var selectedThemeFilter: String
    @Binding var selectedCollectionFilter: String
    let themeOptions: [String]
    let collectionOptions: [ItemCollection]
    let onClose: () -> Void
    let onOpenNode: (GraphNode) -> Void
    
    @State private var selectedNodeID: String?
    @State private var webResetToken: Int = 0
    
    private var visibleNodes: [GraphNode] {
        applyGraphFilter(nodes: graph.nodes, edges: graph.edges, filter: filter).nodes
    }
    
    private var visibleEdges: [GraphEdge] {
        applyGraphFilter(nodes: graph.nodes, edges: graph.edges, filter: filter).edges
    }
    
    var body: some View {
        let selectedTheme = selectedThemeFilter == GraphFilterToken.all ? nil : selectedThemeFilter
        let selectedCollection = selectedCollectionFilter == GraphFilterToken.all ? nil : selectedCollectionFilter
        
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
                    
                    if let selected = visibleNodes.first(where: { $0.id == selectedNodeID }) {
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
                        ForEach(GraphFilter.allCases, id: \.self) { option in
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
                    ForEach(GraphDensityMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Picker("Labels", selection: $labelDensity) {
                    ForEach(GraphLabelDensity.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                HStack(spacing: 8) {
                    Menu {
                        Picker("Theme", selection: $selectedThemeFilter) {
                            Text("All Themes").tag(GraphFilterToken.all)
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
                            Text("All Collections").tag(GraphFilterToken.all)
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
                        nodes: visibleNodes,
                        edges: visibleEdges,
                        selectedNodeID: $selectedNodeID,
                        resetToken: webResetToken,
                        labelDensity: labelDensity,
                        onOpenNode: { nodeID in
                            guard let node = visibleNodes.first(where: { $0.id == nodeID }) else { return }
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

private struct GraphEdgesLayer: View {
    let edges: [GraphEdge]
    let size: CGSize
    let positions: [String: CGPoint]
    let animated: Bool
    let focusNodeIDs: Set<String>?
    
    @Environment(\.graphAnimationTime) private var animationTime
    
    var body: some View {
        ZStack {
            ForEach(edges) { edge in
                if let from = positions[edge.fromID], let to = positions[edge.toID] {
                    let fromPoint = point(for: from, in: size)
                    let toPoint = point(for: to, in: size)
                    let line = Path { path in
                        path.move(to: fromPoint)
                        path.addLine(to: toPoint)
                    }
                    
                    let isFocused = focusNodeIDs?.contains(edge.fromID) == true && focusNodeIDs?.contains(edge.toID) == true
                    let baseOpacity: Double = focusNodeIDs == nil ? edge.opacity : (isFocused ? min(0.95, edge.opacity + 0.35) : 0.05)
                    let lineWidth: CGFloat = focusNodeIDs == nil ? edge.width : (isFocused ? edge.width + 0.8 : 0.6)
                    line
                        .stroke(edge.baseColor.opacity(baseOpacity), lineWidth: lineWidth)
                    
                    if animated && edge.source.containsCollection {
                        let dashPhase = animationTime.remainder(dividingBy: 4) * 22
                        line
                            .stroke(
                                edge.highlightColor.opacity(0.95),
                                style: StrokeStyle(lineWidth: edge.width + 0.8, lineCap: .round, dash: [4, 10], dashPhase: dashPhase)
                            )
                    }
                }
            }
        }
    }
    
    private func point(for normalized: CGPoint, in size: CGSize) -> CGPoint {
        let minSide = min(size.width, size.height)
        return CGPoint(
            x: size.width / 2 + normalized.x * minSide * 0.46,
            y: size.height / 2 + normalized.y * minSide * 0.46
        )
    }
}

private struct GraphNodesLayer: View {
    let nodes: [GraphNode]
    let size: CGSize
    let positions: [String: CGPoint]
    @Binding var selectedNodeID: String?
    let showDenseLabels: Bool
    let focusNodeIDs: Set<String>?
    let labelDensity: GraphLabelDensity
    
    var body: some View {
        let avoidPoints = selectedPlacementContext()
        let inlineLabels = buildInlineLabels(avoiding: avoidPoints)
        
        ZStack {
            ForEach(nodes) { node in
                if let position = positions[node.id] {
                    GraphNodeBubble(node: node, isSelected: selectedNodeID == node.id)
                        .opacity(nodeOpacity(node.id))
                        .position(point(for: position, in: size))
                        .onTapGesture {
                            selectedNodeID = node.id
                        }
                }
            }
            
            ForEach(inlineLabels, id: \.id) { label in
                InlineNodeLabel(text: label.text, tint: label.tint)
                    .position(label.position)
                    .allowsHitTesting(false)
            }
            
            if let selectedNodeID,
               let selectedNode = nodes.first(where: { $0.id == selectedNodeID }),
               let selectedPosition = positions[selectedNodeID] {
                let selectedLabelPoint = preferredSelectedLabelPoint(for: selectedPosition)
                SelectedNodeLabel(node: selectedNode)
                    .position(selectedLabelPoint)
            }
        }
    }
    
    private func point(for normalized: CGPoint, in size: CGSize) -> CGPoint {
        let minSide = min(size.width, size.height)
        return CGPoint(
            x: size.width / 2 + normalized.x * minSide * 0.46,
            y: size.height / 2 + normalized.y * minSide * 0.46
        )
    }
    
    private func labelPoint(for normalized: CGPoint) -> CGPoint {
        let base = point(for: normalized, in: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = base.x - center.x
        let dy = base.y - center.y
        let length = max(0.001, sqrt(dx * dx + dy * dy))
        
        let outward = CGFloat(26)
        return CGPoint(
            x: base.x + (dx / length) * outward,
            y: base.y + (dy / length) * outward
        )
    }
    
    private func buildInlineLabels(avoiding avoidPoints: [CGPoint]) -> [InlineLabelPlacement] {
        let candidates = nodes
            .filter { node in
                if selectedNodeID == node.id { return false }
                if let focusNodeIDs, !focusNodeIDs.contains(node.id) { return false }
                if node.kind == .theme { return true }
                return showDenseLabels
            }
            .sorted { lhs, rhs in
                if lhs.kind.labelPriority == rhs.kind.labelPriority {
                    return lhs.id < rhs.id
                }
                return lhs.kind.labelPriority > rhs.kind.labelPriority
            }
        
        let maxLabels = maxLabelCount(showDenseLabels: showDenseLabels)
        let nodeBlockRadius: CGFloat = 18
        var result: [InlineLabelPlacement] = []
        var occupiedRects: [CGRect] = []
        let blockedRects = avoidPoints.map {
            CGRect(x: $0.x - 44, y: $0.y - 20, width: 88, height: 40)
        }
        let nodeCenters: [CGPoint] = nodes.compactMap { node in
            guard let p = positions[node.id] else { return nil }
            return point(for: p, in: size)
        }
        
        for node in candidates {
            guard let p = positions[node.id] else { continue }
            let placements = candidateLabelPoints(for: p)
            guard let chosen = placements.first(where: { candidate in
                let rect = labelRect(for: node.title, centeredAt: candidate)
                
                let overlapsPlacedLabels = occupiedRects.contains { $0.intersects(rect.insetBy(dx: -3, dy: -3)) }
                if overlapsPlacedLabels { return false }
                
                let overlapsSelectionZone = blockedRects.contains { $0.intersects(rect.insetBy(dx: -2, dy: -2)) }
                if overlapsSelectionZone { return false }
                
                let intersectsNodeBubble = nodeCenters.contains {
                    distance($0, candidate) < nodeBlockRadius
                }
                if intersectsNodeBubble { return false }
                
                let insideCanvas = rect.minX >= 6 && rect.maxX <= size.width - 6 && rect.minY >= 6 && rect.maxY <= size.height - 6
                return insideCanvas
            }) else {
                continue
            }
            
            let finalRect = labelRect(for: node.title, centeredAt: chosen)
            result.append(
                InlineLabelPlacement(
                    id: node.id,
                    text: node.title,
                    tint: node.kind.color,
                    position: chosen
                )
            )
            occupiedRects.append(finalRect)
            
            if result.count >= maxLabels { break }
        }
        
        return result
    }
    
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func nodeOpacity(_ nodeID: String) -> Double {
        guard let focusNodeIDs else { return 1.0 }
        return focusNodeIDs.contains(nodeID) ? 1.0 : 0.22
    }

    private func preferredSelectedLabelPoint(for normalized: CGPoint) -> CGPoint {
        let base = point(for: normalized, in: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = base.x - center.x
        let dy = base.y - center.y
        let length = max(0.001, sqrt(dx * dx + dy * dy))
        let outward: CGFloat = 52
        return CGPoint(
            x: base.x + (dx / length) * outward,
            y: base.y + (dy / length) * outward
        )
    }

    private func selectedPlacementContext() -> [CGPoint] {
        guard let selectedNodeID, let selectedNormalized = positions[selectedNodeID] else {
            return []
        }
        let bubblePoint = point(for: selectedNormalized, in: size)
        let labelPoint = preferredSelectedLabelPoint(for: selectedNormalized)
        return [bubblePoint, labelPoint]
    }
    
    private func candidateLabelPoints(for normalized: CGPoint) -> [CGPoint] {
        let base = point(for: normalized, in: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = base.x - center.x
        let dy = base.y - center.y
        let length = max(0.001, sqrt(dx * dx + dy * dy))
        let ux = dx / length
        let uy = dy / length
        let tx = -uy
        let ty = ux
        
        return [
            CGPoint(x: base.x + ux * 28, y: base.y + uy * 28),
            CGPoint(x: base.x + ux * 30 + tx * 18, y: base.y + uy * 30 + ty * 18),
            CGPoint(x: base.x + ux * 30 - tx * 18, y: base.y + uy * 30 - ty * 18),
            CGPoint(x: base.x + tx * 24, y: base.y + ty * 24),
            CGPoint(x: base.x - tx * 24, y: base.y - ty * 24),
            CGPoint(x: base.x - ux * 26, y: base.y - uy * 26)
        ]
    }
    
    private func labelRect(for text: String, centeredAt point: CGPoint) -> CGRect {
        let estimated = CGFloat(text.count) * 7.1 + 18
        let width = min(150, max(56, estimated))
        let height: CGFloat = 24
        return CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
    }
    
    private func maxLabelCount(showDenseLabels: Bool) -> Int {
        switch labelDensity {
        case .low:
            return showDenseLabels ? 10 : 6
        case .medium:
            return showDenseLabels ? 18 : 10
        case .high:
            return showDenseLabels ? 30 : 16
        }
    }
}

private struct GraphNodeBubble: View {
    let node: GraphNode
    let isSelected: Bool
    
    var body: some View {
        Circle()
            .fill(node.kind.color.opacity(isSelected ? 0.95 : 0.8))
            .frame(width: isSelected ? 26 : 22, height: isSelected ? 26 : 22)
            .overlay {
                Text(node.kind.icon)
                    .font(.system(size: 11))
            }
            .shadow(color: node.kind.color.opacity(isSelected ? 0.7 : 0.2), radius: isSelected ? 10 : 3)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(isSelected ? 0.6 : 0.0), lineWidth: 1)
                    .frame(width: isSelected ? 30 : 24, height: isSelected ? 30 : 24)
                    .blur(radius: isSelected ? 0.4 : 0)
            }
    }
}

private struct SelectedNodeLabel: View {
    let node: GraphNode
    
    var body: some View {
        Text(node.title)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(node.kind.color.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 3)
            .frame(maxWidth: 140)
    }
}

private struct InlineNodeLabel: View {
    let text: String
    let tint: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.25), lineWidth: 0.8)
            }
            .frame(maxWidth: 110)
    }
}

private struct InlineLabelPlacement {
    let id: String
    let text: String
    let tint: Color
    let position: CGPoint
}

private struct VisibleNodeLegend: View {
    let nodes: [GraphNode]
    @Binding var selectedNodeID: String?
    
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

private struct Constellation3DPreviewWebView: UIViewRepresentable {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    @Binding var selectedNodeID: String?
    let resetToken: Int
    let onOpenNode: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "nodeTap")
        userContent.add(context.coordinator, name: "nodeOpen")
        config.userContentController = userContent
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pushBindings(selectedNodeID: $selectedNodeID, onOpenNode: onOpenNode)
        
        if let html = context.coordinator.initialHTML(payload: payload()) {
            webView.loadHTMLString(html, baseURL: nil)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.pushBindings(selectedNodeID: $selectedNodeID, onOpenNode: onOpenNode)
        context.coordinator.pushGraph(payload(), selectedNodeID: selectedNodeID, resetToken: resetToken)
    }
    
    private func payload() -> D3GraphPayload {
        D3GraphPayload(
            nodes: nodes.map {
                D3NodePayload(
                    id: $0.id,
                    title: $0.title,
                    kind: $0.kind.d3Kind,
                    color: $0.kind.webColor,
                    icon: $0.kind.icon
                )
            },
            links: edges.map {
                D3LinkPayload(
                    source: $0.fromID,
                    target: $0.toID,
                    weight: $0.weight
                )
            },
            labelDensity: GraphLabelDensity.medium.d3Token
        )
    }
    
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var didFinishLoad = false
        private var lastGraphJSON: String?
        private var lastResetToken: Int = 0
        private var setSelectedNode: (String?) -> Void = { _ in }
        private var openNode: (String) -> Void = { _ in }
        
        func pushBindings(selectedNodeID: Binding<String?>, onOpenNode: @escaping (String) -> Void) {
            self.setSelectedNode = { selectedNodeID.wrappedValue = $0 }
            self.openNode = onOpenNode
        }
        
        func initialHTML(payload: D3GraphPayload) -> String? {
            guard let json = payload.jsonString else { return nil }
            lastGraphJSON = json
            return Self.htmlTemplate.replacingOccurrences(of: "__INITIAL_GRAPH_JSON__", with: json)
        }
        
        func pushGraph(_ payload: D3GraphPayload, selectedNodeID: String?, resetToken: Int) {
            guard didFinishLoad, let webView, let json = payload.jsonString else { return }
            
            if lastGraphJSON != json {
                webView.evaluateJavaScript("window.__updateGraph(\(json));")
                lastGraphJSON = json
            }
            
            if let selectedNodeID, let selectedLiteral = selectedNodeID.jsSingleQuoted {
                webView.evaluateJavaScript("window.__selectNode(\(selectedLiteral));")
            } else {
                webView.evaluateJavaScript("window.__selectNode(null);")
            }
            
            if resetToken != lastResetToken {
                lastResetToken = resetToken
                webView.evaluateJavaScript("window.__resetView();")
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoad = true
            if let json = lastGraphJSON {
                webView.evaluateJavaScript("window.__updateGraph(\(json));")
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let id = message.body as? String else { return }
            if message.name == "nodeTap" {
                setSelectedNode(id)
            } else if message.name == "nodeOpen" {
                openNode(id)
            }
        }
        
        static let htmlTemplate = #"""
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <style>
    html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
    #root { width: 100%; height: 100%; position: relative; }
    #canvas { width: 100%; height: 100%; display: block; }
    #hint {
      position: absolute; left: 10px; bottom: 8px; padding: 6px 8px; border-radius: 10px;
      color: rgba(235, 243, 255, 0.92); font: 11px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: rgba(10, 20, 56, 0.4); pointer-events: none;
    }
  </style>
</head>
<body>
  <div id="root">
    <canvas id="canvas"></canvas>
    <div id="hint">Drag to rotate · Tap a node to select · Double-tap to open</div>
  </div>
  <script>
    let graph = __INITIAL_GRAPH_JSON__;
    let selectedNodeId = null;
    let spinX = -0.45;
    let spinY = 0.32;
    let velocityX = 0.0;
    let velocityY = 0.0022;
    let dragging = false;
    let lastX = 0;
    let lastY = 0;
    let hoverNodeId = null;
    let lastTap = { id: null, time: 0 };
    
    const root = document.getElementById("root");
    const canvas = document.getElementById("canvas");
    const ctx = canvas.getContext("2d");
    
    function resize() {
      const dpr = window.devicePixelRatio || 1;
      const w = root.clientWidth || 320;
      const h = root.clientHeight || 280;
      canvas.width = Math.floor(w * dpr);
      canvas.height = Math.floor(h * dpr);
      canvas.style.width = w + "px";
      canvas.style.height = h + "px";
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    
    function hash01(str) {
      let h = 2166136261;
      for (let i = 0; i < str.length; i++) {
        h ^= str.charCodeAt(i);
        h = Math.imul(h, 16777619);
      }
      return (h >>> 0) / 4294967295;
    }
    
    function buildState() {
      const nodes = graph.nodes.map((n) => {
        const u = hash01(n.id + ":u");
        const v = hash01(n.id + ":v");
        const theta = u * Math.PI * 2;
        const phi = Math.acos(2 * v - 1);
        const r = 0.75 + hash01(n.id + ":r") * 0.38;
        return {
          ...n,
          x: Math.sin(phi) * Math.cos(theta) * r,
          y: Math.cos(phi) * r,
          z: Math.sin(phi) * Math.sin(theta) * r
        };
      });
      const nodeById = new Map(nodes.map((n) => [n.id, n]));
      const links = graph.links
        .map((l) => ({ ...l, a: nodeById.get(l.source), b: nodeById.get(l.target) }))
        .filter((l) => l.a && l.b);
      return { nodes, links };
    }
    
    let state = buildState();
    
    function rotate(p, ax, ay) {
      const cosY = Math.cos(ay), sinY = Math.sin(ay);
      const cosX = Math.cos(ax), sinX = Math.sin(ax);
      let x = p.x * cosY - p.z * sinY;
      let z = p.x * sinY + p.z * cosY;
      let y = p.y * cosX - z * sinX;
      z = p.y * sinX + z * cosX;
      return { x, y, z };
    }
    
    function project(rot, w, h) {
      const fov = Math.min(w, h) * 0.9;
      const depth = rot.z + 2.3;
      const s = fov / Math.max(0.2, depth);
      return { px: w * 0.5 + rot.x * s, py: h * 0.5 + rot.y * s, scale: s, depth };
    }
    
    function draw() {
      const w = root.clientWidth || 320;
      const h = root.clientHeight || 280;
      ctx.clearRect(0, 0, w, h);
      
      const bg = ctx.createRadialGradient(w * 0.2, h * 0.1, 8, w * 0.5, h * 0.5, Math.max(w, h));
      bg.addColorStop(0, "rgba(20, 32, 71, 0.94)");
      bg.addColorStop(0.45, "rgba(10, 18, 51, 0.96)");
      bg.addColorStop(1, "rgba(5, 12, 36, 0.98)");
      ctx.fillStyle = bg;
      ctx.fillRect(0, 0, w, h);
      
      const projected = state.nodes.map((node) => {
        const r = rotate(node, spinX, spinY);
        const p = project(r, w, h);
        return { node, ...p };
      }).sort((a, b) => b.depth - a.depth);
      
      const pos = new Map(projected.map((p) => [p.node.id, p]));
      
      for (const link of state.links) {
        const a = pos.get(link.source);
        const b = pos.get(link.target);
        if (!a || !b) continue;
        const alpha = 0.16 + Math.max(0, 0.32 - Math.abs((a.depth + b.depth) * 0.08));
        ctx.strokeStyle = `rgba(205, 220, 255, ${alpha})`;
        ctx.lineWidth = Math.min(2.2, 0.5 + (link.weight || 1) * 0.45);
        ctx.beginPath();
        ctx.moveTo(a.px, a.py);
        ctx.lineTo(b.px, b.py);
        ctx.stroke();
      }
      
      for (const p of projected) {
        const isSelected = p.node.id === selectedNodeId;
        const isHover = p.node.id === hoverNodeId;
        const radius = (isSelected ? 7.8 : 6.2) * Math.min(1.55, Math.max(0.7, p.scale / 95));
        
        ctx.beginPath();
        ctx.fillStyle = p.node.color;
        ctx.globalAlpha = selectedNodeId && !isSelected ? 0.48 : 0.96;
        ctx.arc(p.px, p.py, radius, 0, Math.PI * 2);
        ctx.fill();
        ctx.globalAlpha = 1.0;
        
        ctx.lineWidth = isSelected ? 2.2 : (isHover ? 1.6 : 1.0);
        ctx.strokeStyle = isSelected ? "rgba(255,255,255,0.95)" : "rgba(255,255,255,0.45)";
        ctx.stroke();
        
        if (isHover || isSelected) {
          drawLabel(p.node.title, p.px + 11, p.py - 10);
        }
      }
    }
    
    function drawLabel(text, x, y) {
      ctx.font = "12px -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif";
      const w = Math.min(188, Math.max(52, ctx.measureText(text).width + 14));
      const h = 24;
      ctx.fillStyle = "rgba(18, 24, 48, 0.86)";
      roundRect(x, y - h, w, h, 10);
      ctx.fill();
      ctx.strokeStyle = "rgba(210, 220, 255, 0.4)";
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.fillStyle = "rgba(245, 248, 255, 0.97)";
      ctx.fillText(text, x + 7, y - 8);
    }
    
    function roundRect(x, y, w, h, r) {
      ctx.beginPath();
      ctx.moveTo(x + r, y);
      ctx.lineTo(x + w - r, y);
      ctx.quadraticCurveTo(x + w, y, x + w, y + r);
      ctx.lineTo(x + w, y + h - r);
      ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
      ctx.lineTo(x + r, y + h);
      ctx.quadraticCurveTo(x, y + h, x, y + h - r);
      ctx.lineTo(x, y + r);
      ctx.quadraticCurveTo(x, y, x + r, y);
      ctx.closePath();
    }
    
    function pickNode(clientX, clientY) {
      const rect = canvas.getBoundingClientRect();
      const x = clientX - rect.left;
      const y = clientY - rect.top;
      let best = null;
      let bestDist = 22;
      const w = root.clientWidth || 320;
      const h = root.clientHeight || 280;
      
      for (const node of state.nodes) {
        const r = rotate(node, spinX, spinY);
        const p = project(r, w, h);
        const d = Math.hypot(p.px - x, p.py - y);
        if (d < bestDist) {
          bestDist = d;
          best = node.id;
        }
      }
      return best;
    }
    
    function tick() {
      if (!dragging) {
        spinX += velocityX;
        spinY += velocityY;
        velocityX *= 0.985;
        velocityY *= 0.988;
      }
      draw();
      requestAnimationFrame(tick);
    }
    
    canvas.addEventListener("mousedown", (e) => {
      dragging = true;
      lastX = e.clientX;
      lastY = e.clientY;
    });
    window.addEventListener("mouseup", () => { dragging = false; });
    window.addEventListener("mousemove", (e) => {
      if (dragging) {
        const dx = e.clientX - lastX;
        const dy = e.clientY - lastY;
        spinY += dx * 0.006;
        spinX += dy * 0.006;
        velocityY = dx * 0.00024;
        velocityX = dy * 0.00024;
        lastX = e.clientX;
        lastY = e.clientY;
      } else {
        hoverNodeId = pickNode(e.clientX, e.clientY);
      }
    });
    
    canvas.addEventListener("touchstart", (e) => {
      const t = e.touches[0];
      dragging = true;
      lastX = t.clientX;
      lastY = t.clientY;
    }, { passive: true });
    
    canvas.addEventListener("touchmove", (e) => {
      const t = e.touches[0];
      const dx = t.clientX - lastX;
      const dy = t.clientY - lastY;
      spinY += dx * 0.006;
      spinX += dy * 0.006;
      velocityY = dx * 0.00024;
      velocityX = dy * 0.00024;
      lastX = t.clientX;
      lastY = t.clientY;
      hoverNodeId = pickNode(t.clientX, t.clientY);
    }, { passive: true });
    
    canvas.addEventListener("touchend", () => {
      dragging = false;
    }, { passive: true });
    
    canvas.addEventListener("click", (e) => {
      const id = pickNode(e.clientX, e.clientY);
      if (!id) return;
      selectedNodeId = id;
      if (window.webkit?.messageHandlers?.nodeTap) {
        window.webkit.messageHandlers.nodeTap.postMessage(id);
      }
      const now = Date.now();
      if (lastTap.id === id && (now - lastTap.time) < 320) {
        if (window.webkit?.messageHandlers?.nodeOpen) {
          window.webkit.messageHandlers.nodeOpen.postMessage(id);
        }
      }
      lastTap = { id, time: now };
    });
    
    window.__updateGraph = function(nextGraph) {
      graph = nextGraph;
      state = buildState();
    };
    
    window.__selectNode = function(id) {
      selectedNodeId = id;
    };
    
    window.__resetView = function() {
      spinX = -0.45;
      spinY = 0.32;
      velocityX = 0.0;
      velocityY = 0.0022;
      hoverNodeId = null;
      selectedNodeId = null;
    };
    
    window.addEventListener("resize", resize);
    resize();
    tick();
  </script>
</body>
</html>
"""#
    }
}

private struct ConstellationD3WebView: UIViewRepresentable {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    @Binding var selectedNodeID: String?
    let resetToken: Int
    let labelDensity: GraphLabelDensity
    let onOpenNode: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "nodeTap")
        userContent.add(context.coordinator, name: "nodeOpen")
        config.userContentController = userContent
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pushBindings(selectedNodeID: $selectedNodeID, onOpenNode: onOpenNode)
        
        if let html = context.coordinator.initialHTML(payload: payload()) {
            webView.loadHTMLString(html, baseURL: nil)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.pushBindings(selectedNodeID: $selectedNodeID, onOpenNode: onOpenNode)
        context.coordinator.pushGraph(payload(), selectedNodeID: selectedNodeID, resetToken: resetToken)
    }
    
    private func payload() -> D3GraphPayload {
        D3GraphPayload(
            nodes: nodes.map {
                D3NodePayload(
                    id: $0.id,
                    title: $0.title,
                    kind: $0.kind.d3Kind,
                    color: $0.kind.webColor,
                    icon: $0.kind.icon
                )
            },
            links: edges.map {
                D3LinkPayload(
                    source: $0.fromID,
                    target: $0.toID,
                    weight: $0.weight
                )
            },
            labelDensity: labelDensity.d3Token
        )
    }
    
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var didFinishLoad = false
        private var lastGraphJSON: String?
        private var lastResetToken: Int = 0
        private var setSelectedNode: (String?) -> Void = { _ in }
        private var openNode: (String) -> Void = { _ in }
        
        func pushBindings(selectedNodeID: Binding<String?>, onOpenNode: @escaping (String) -> Void) {
            self.setSelectedNode = { selectedNodeID.wrappedValue = $0 }
            self.openNode = onOpenNode
        }
        
        func initialHTML(payload: D3GraphPayload) -> String? {
            guard let json = payload.jsonString else { return nil }
            lastGraphJSON = json
            return Self.htmlTemplate.replacingOccurrences(of: "__INITIAL_GRAPH_JSON__", with: json)
        }
        
        func pushGraph(_ payload: D3GraphPayload, selectedNodeID: String?, resetToken: Int) {
            guard didFinishLoad, let webView, let json = payload.jsonString else { return }
            
            if lastGraphJSON != json {
                let updateJS = "window.__updateGraph(\(json));"
                webView.evaluateJavaScript(updateJS)
                lastGraphJSON = json
            }
            
            if let selectedNodeID, let selectedLiteral = selectedNodeID.jsSingleQuoted {
                webView.evaluateJavaScript("window.__selectNode(\(selectedLiteral));")
            } else {
                webView.evaluateJavaScript("window.__selectNode(null);")
            }
            
            if resetToken != lastResetToken {
                lastResetToken = resetToken
                webView.evaluateJavaScript("window.__resetView();")
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoad = true
            if let json = lastGraphJSON {
                webView.evaluateJavaScript("window.__updateGraph(\(json));")
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let id = message.body as? String else { return }
            if message.name == "nodeTap" {
                setSelectedNode(id)
            } else if message.name == "nodeOpen" {
                openNode(id)
            }
        }
        
        static let htmlTemplate = #"""
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <style>
    html, body {
      margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden;
      background: radial-gradient(circle at 20% 15%, #142047 0%, #0a1233 38%, #050c24 100%);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    }
    #root { width: 100%; height: 100%; }
    .link { stroke: rgba(210, 220, 255, 0.4); stroke-linecap: round; }
    .node circle { stroke: rgba(255,255,255,0.2); stroke-width: 1.2px; }
    .node text {
      fill: rgba(242, 246, 255, 0.95);
      font-size: 11px;
      paint-order: stroke;
      stroke: rgba(5, 12, 36, 0.95);
      stroke-width: 3.2px;
      stroke-linejoin: round;
      pointer-events: none;
    }
    .node.selected circle { stroke: rgba(255,255,255,0.85); stroke-width: 2.5px; }
  </style>
</head>
<body>
  <div id="root"></div>
  <script src="https://d3js.org/d3.v7.min.js"></script>
  <script>
    const initialGraph = __INITIAL_GRAPH_JSON__;
    let graph = initialGraph;
    let selectedNodeId = null;
    let zoomRef = null;
    let svgRef = null;
    let stageRef = null;
    let simulation = null;
    
    function canShowLabel(node, density, neighbors) {
      if (node.id === selectedNodeId) return true;
      if (neighbors.has(node.id)) return true;
      if (density === "high") return true;
      if (density === "medium") return node.kind === "theme";
      return false;
    }
    
    function neighborSet(links, id) {
      const result = new Set();
      if (!id) return result;
      for (const link of links) {
        const a = typeof link.source === "object" ? link.source.id : link.source;
        const b = typeof link.target === "object" ? link.target.id : link.target;
        if (a === id) result.add(b);
        if (b === id) result.add(a);
      }
      return result;
    }
    
    function render() {
      if (!window.d3) return;
      
      const root = document.getElementById("root");
      const width = root.clientWidth || 320;
      const height = root.clientHeight || 300;
      root.innerHTML = "";
      
      svgRef = d3.select(root).append("svg")
        .attr("width", width)
        .attr("height", height);
      
      const stage = svgRef.append("g");
      stageRef = stage;
      
      zoomRef = d3.zoom()
        .scaleExtent([0.45, 3.5])
        .on("zoom", (event) => stage.attr("transform", event.transform));
      svgRef.call(zoomRef);
      
      const links = graph.links.map((d) => ({ ...d }));
      const nodes = graph.nodes.map((d) => ({ ...d }));
      const neighbors = neighborSet(links, selectedNodeId);
      
      const link = stage.append("g")
        .selectAll("line")
        .data(links)
        .join("line")
        .attr("class", "link")
        .attr("stroke-width", (d) => Math.min(2.8, 1 + d.weight * 0.45))
        .attr("stroke-opacity", (d) => {
          if (!selectedNodeId) return 0.38;
          const a = typeof d.source === "object" ? d.source.id : d.source;
          const b = typeof d.target === "object" ? d.target.id : d.target;
          return (a === selectedNodeId || b === selectedNodeId) ? 0.88 : 0.1;
        });
      
      let lastTapAt = { time: 0, id: null };
      
      const node = stage.append("g")
        .selectAll("g")
        .data(nodes)
        .join("g")
        .attr("class", (d) => d.id === selectedNodeId ? "node selected" : "node")
        .style("cursor", "pointer")
        .on("click", (_, d) => {
          const now = Date.now();
          const isDoubleTap = lastTapAt.id === d.id && (now - lastTapAt.time) < 320;
          lastTapAt.time = now;
          lastTapAt.id = d.id;
          
          selectedNodeId = d.id;
          if (window.webkit?.messageHandlers?.nodeTap) {
            window.webkit.messageHandlers.nodeTap.postMessage(d.id);
          }
          
          if (isDoubleTap && window.webkit?.messageHandlers?.nodeOpen) {
            window.webkit.messageHandlers.nodeOpen.postMessage(d.id);
          }
          
          render();
        });
      
      node.append("circle")
        .attr("r", (d) => d.id === selectedNodeId ? 11.5 : 9.4)
        .attr("fill", (d) => d.color)
        .attr("fill-opacity", (d) => {
          if (!selectedNodeId) return 0.95;
          return (d.id === selectedNodeId || neighbors.has(d.id)) ? 0.98 : 0.32;
        });
      
      node.append("text")
        .attr("dy", -13)
        .attr("text-anchor", "middle")
        .style("display", (d) => canShowLabel(d, graph.labelDensity, neighbors) ? "block" : "none")
        .text((d) => d.title);
      
      simulation = d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id((d) => d.id).distance((d) => 90 + (d.weight || 1) * 4))
        .force("charge", d3.forceManyBody().strength(-260))
        .force("center", d3.forceCenter(width / 2, height / 2))
        .force("collision", d3.forceCollide().radius((d) => d.id === selectedNodeId ? 24 : 20))
        .alpha(0.95)
        .alphaDecay(0.028);
      
      node.call(
        d3.drag()
          .on("start", (event) => {
            if (!event.active) simulation.alphaTarget(0.3).restart();
            event.subject.fx = event.subject.x;
            event.subject.fy = event.subject.y;
          })
          .on("drag", (event) => {
            event.subject.fx = event.x;
            event.subject.fy = event.y;
          })
          .on("end", (event) => {
            if (!event.active) simulation.alphaTarget(0);
            event.subject.fx = null;
            event.subject.fy = null;
          })
      );
      
      simulation.on("tick", () => {
        link
          .attr("x1", (d) => d.source.x)
          .attr("y1", (d) => d.source.y)
          .attr("x2", (d) => d.target.x)
          .attr("y2", (d) => d.target.y);
        
        node.attr("transform", (d) => `translate(${d.x},${d.y})`);
      });
    }
    
    window.__updateGraph = function(nextGraph) {
      graph = nextGraph;
      render();
    };
    
    window.__selectNode = function(id) {
      selectedNodeId = id;
      render();
    };
    
    window.__resetView = function() {
      if (svgRef && zoomRef) {
        svgRef.transition().duration(360).call(zoomRef.transform, d3.zoomIdentity);
      }
      if (simulation) {
        simulation.alpha(0.85).restart();
      }
    };
    
    if (window.d3) {
      render();
    } else {
      const root = document.getElementById("root");
      root.innerHTML = '<div style="color:#dbe7ff;opacity:0.9;padding:16px;font-size:13px;">Unable to load D3. Check network and reload the graph.</div>';
    }
  </script>
</body>
</html>
"""#
    }
}

private struct D3GraphPayload: Codable {
    let nodes: [D3NodePayload]
    let links: [D3LinkPayload]
    let labelDensity: String
    
    var jsonString: String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
}

private struct D3NodePayload: Codable {
    let id: String
    let title: String
    let kind: String
    let color: String
    let icon: String
}

private struct D3LinkPayload: Codable {
    let source: String
    let target: String
    let weight: Int
}

private struct GraphData {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let positions: [String: CGPoint]
}

private struct GraphNode: Identifiable {
    let id: String
    let title: String
    let kind: GraphNodeKind
    let reference: String?
}

private struct GraphEdge: Identifiable {
    let id: String
    let fromID: String
    let toID: String
    let weight: Int
    let source: GraphEdgeSource
    
    var baseColor: Color {
        switch source {
        case .theme:
            return Color.gray
        case .collection:
            return Color.cyan
        case .hybrid:
            return Color.mint
        }
    }
    
    var highlightColor: Color {
        switch source {
        case .theme:
            return Color.gray
        case .collection:
            return Color.cyan
        case .hybrid:
            return Color.teal
        }
    }
    
    var width: CGFloat {
        if source.containsCollection {
            return weight > 1 ? 2.3 : 1.8
        }
        return weight > 1 ? 1.5 : 0.95
    }
    
    var opacity: Double {
        if source.containsCollection {
            return weight > 1 ? 0.75 : 0.55
        }
        return weight > 1 ? 0.35 : 0.2
    }
}

private struct EdgeAggregate {
    var weight: Int
    var source: GraphEdgeSource
}

private enum GraphEdgeSource {
    case theme
    case collection
    case hybrid
    
    var containsCollection: Bool {
        self == .collection || self == .hybrid
    }
    
    func merged(with other: GraphEdgeSource) -> GraphEdgeSource {
        if self == other { return self }
        return .hybrid
    }
    
    var priority: Int {
        switch self {
        case .hybrid: return 3
        case .collection: return 2
        case .theme: return 1
        }
    }
}

private enum GraphNodeKind: Hashable {
    case movie
    case tvShow
    case theme
    
    var color: Color {
        switch self {
        case .movie: return .blue
        case .tvShow: return .green
        case .theme: return .purple
        }
    }
    
    var icon: String {
        switch self {
        case .movie: return "🎬"
        case .tvShow: return "📺"
        case .theme: return "⭐"
        }
    }
    
    var label: String {
        switch self {
        case .movie: return "Movie"
        case .tvShow: return "TV Show"
        case .theme: return "Theme"
        }
    }
    
    var labelPriority: Int {
        switch self {
        case .theme: return 3
        case .movie: return 2
        case .tvShow: return 1
        }
    }
    
    var webColor: String {
        switch self {
        case .movie: return "#3b82f6"
        case .tvShow: return "#22c55e"
        case .theme: return "#c026d3"
        }
    }
    
    var d3Kind: String {
        switch self {
        case .movie: return "movie"
        case .tvShow: return "tvShow"
        case .theme: return "theme"
        }
    }
}

private enum GraphFilter: CaseIterable {
    case all
    case movies
    case tvShows
    case themes
    
    var title: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .tvShows: return "TV"
        case .themes: return "Themes"
        }
    }
    
    var visibleKinds: Set<GraphNodeKind> {
        switch self {
        case .all: return [.movie, .tvShow, .theme]
        case .movies: return [.movie, .theme]
        case .tvShows: return [.tvShow, .theme]
        case .themes: return [.theme]
        }
    }
}

private enum GraphDensityMode: CaseIterable {
    case simple
    case detailed
    
    var title: String {
        switch self {
        case .simple: return "Simple"
        case .detailed: return "Detailed"
        }
    }
}

private enum GraphLabelDensity: CaseIterable {
    case low
    case medium
    case high
    
    var title: String {
        switch self {
        case .low: return "Labels: Low"
        case .medium: return "Labels: Medium"
        case .high: return "Labels: High"
        }
    }
    
    var d3Token: String {
        switch self {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }
}

private enum GraphFilterToken {
    static let all = "__all__"
}

private func applyGraphFilter(nodes: [GraphNode], edges: [GraphEdge], filter: GraphFilter) -> (nodes: [GraphNode], edges: [GraphEdge]) {
    let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    
    func filtered(allowedIDs: Set<String>) -> (nodes: [GraphNode], edges: [GraphEdge]) {
        let filteredNodes = nodes.filter { allowedIDs.contains($0.id) }
        let filteredEdges = edges.filter { allowedIDs.contains($0.fromID) && allowedIDs.contains($0.toID) }
        return (filteredNodes, filteredEdges)
    }
    
    switch filter {
    case .all:
        let allIDs = Set(nodes.map(\.id))
        return filtered(allowedIDs: allIDs)
        
    case .themes:
        let themeIDs = Set(nodes.filter { $0.kind == .theme }.map(\.id))
        return filtered(allowedIDs: themeIDs)
        
    case .movies:
        let movieIDs = Set(nodes.filter { $0.kind == .movie }.map(\.id))
        var allowed = movieIDs
        
        for edge in edges {
            guard let fromKind = nodeByID[edge.fromID]?.kind, let toKind = nodeByID[edge.toID]?.kind else { continue }
            if fromKind == .movie && toKind == .theme {
                allowed.insert(edge.toID)
            } else if fromKind == .theme && toKind == .movie {
                allowed.insert(edge.fromID)
            }
        }
        
        return filtered(allowedIDs: allowed)
        
    case .tvShows:
        let showIDs = Set(nodes.filter { $0.kind == .tvShow }.map(\.id))
        var allowed = showIDs
        
        for edge in edges {
            guard let fromKind = nodeByID[edge.fromID]?.kind, let toKind = nodeByID[edge.toID]?.kind else { continue }
            if fromKind == .tvShow && toKind == .theme {
                allowed.insert(edge.toID)
            } else if fromKind == .theme && toKind == .tvShow {
                allowed.insert(edge.fromID)
            }
        }
        
        return filtered(allowedIDs: allowed)
    }
}

private struct ThemeSelection: Identifiable {
    let id: String
}

private struct GraphAnimationTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 0
}

private extension EnvironmentValues {
    var graphAnimationTime: TimeInterval {
        get { self[GraphAnimationTimeKey.self] }
        set { self[GraphAnimationTimeKey.self] = newValue }
    }
}

private extension String {
    var jsSingleQuoted: String? {
        guard let data = try? JSONEncoder().encode(self), var json = String(data: data, encoding: .utf8) else { return nil }
        if json.hasPrefix("\""), json.hasSuffix("\""), json.count >= 2 {
            json.removeFirst()
            json.removeLast()
        }
        let escaped = json.replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}
