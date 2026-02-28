//
//  ConstellationGraphView.swift
//  Constellation
//
//  Created by Codex on 2/27/26.
//

import SwiftUI

struct ConstellationGraphView: View {
    let movies: [Movie]
    let tvShows: [TVShow]
    let collections: [ItemCollection]
    
    @State private var zoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var selectedNodeID: String?
    @State private var filter: GraphFilter = .all
    @State private var showImmersiveMode = false
    @State private var selectedThemeFilter: String = GraphFilterToken.all
    @State private var selectedCollectionFilter: String = GraphFilterToken.all
    @State private var densityMode: GraphDensityMode = .simple
    @State private var panStart: CGSize = .zero
    @State private var zoomStart: CGFloat = 1.0
    @State private var canvasSize: CGSize = .zero
    
    @State private var selectedMovie: Movie?
    @State private var selectedTVShow: TVShow?
    @State private var selectedTheme: ThemeSelection?
    
    var body: some View {
        let themeOptions = Array(Set(movies.flatMap(\.themes) + tvShows.flatMap(\.themes))).sorted()
        let collectionOptions = collections.sorted { $0.name < $1.name }
        let selectedTheme = selectedThemeFilter == GraphFilterToken.all ? nil : selectedThemeFilter
        let selectedCollection = selectedCollectionFilter == GraphFilterToken.all ? nil : selectedCollectionFilter
        
        let graph = buildGraph(themeFilter: selectedTheme, collectionFilter: selectedCollection, densityMode: densityMode)
        let filteredGraph = applyGraphFilter(nodes: graph.nodes, edges: graph.edges, filter: filter)
        let visibleNodes = filteredGraph.nodes
        let allVisibleEdges = filteredGraph.edges
        let focusNodeIDs = focusNodeSet(selectedID: selectedNodeID, edges: allVisibleEdges)
        let renderedEdges = focusNodeIDs == nil
            ? allVisibleEdges
            : allVisibleEdges.filter { edge in
                focusNodeIDs!.contains(edge.fromID) && focusNodeIDs!.contains(edge.toID)
            }
        let renderedNodes = visibleNodes
        let displayEdges = densityMode == .simple ? Array(renderedEdges.prefix(70)) : renderedEdges
        
        let showDenseLabels = densityMode == .detailed || selectedTheme != nil || selectedCollection != nil
        
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
            
            HStack(spacing: 8) {
                ForEach(GraphFilter.allCases, id: \.self) { option in
                    Button(option.title) {
                        filter = option
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(filter == option ? Color.blue.opacity(0.2) : Color.gray.opacity(0.14))
                    .foregroundStyle(filter == option ? .blue : .secondary)
                    .clipShape(Capsule())
                }
            }
            
            Picker("Density", selection: $densityMode) {
                ForEach(GraphDensityMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            
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
                    .background(Color.gray.opacity(0.14))
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
                    .background(Color.gray.opacity(0.14))
                    .clipShape(Capsule())
                }
            }
            
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                    
                    graphLayer(
                        size: proxy.size,
                        nodes: renderedNodes,
                        edges: displayEdges,
                        positions: graph.positions,
                        animated: false,
                        showDenseLabels: showDenseLabels,
                        focusNodeIDs: focusNodeIDs
                    )
                    .scaleEffect(zoom)
                    .offset(pan)
                    .contentShape(Rectangle())
                    .gesture(graphGesture(maxZoom: 2.2))
                    .onAppear { canvasSize = proxy.size }
                    .onChange(of: proxy.size) { _, newValue in
                        canvasSize = newValue
                    }
                    
                    if visibleNodes.isEmpty {
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
            
            VisibleNodeLegend(nodes: visibleNodes, selectedNodeID: $selectedNodeID)
            
            if let selected = graph.nodes.first(where: { $0.id == selectedNodeID }) {
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
                graph: graph,
                filter: filter,
                showDenseLabels: showDenseLabels,
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
        .onChange(of: selectedNodeID) { _, newValue in
            guard let newValue else { return }
            focusOnNode(
                nodeID: newValue,
                positions: graph.positions,
                canvasSize: canvasSize,
                targetZoom: 1.35,
                maxZoom: 2.2
            )
        }
    }
    
    @ViewBuilder
    private func graphLayer(
        size: CGSize,
        nodes: [GraphNode],
        edges: [GraphEdge],
        positions: [String: CGPoint],
        animated: Bool,
        showDenseLabels: Bool,
        focusNodeIDs: Set<String>?
    ) -> some View {
        let edgeView = GraphEdgesLayer(
            edges: edges,
            size: size,
            positions: positions,
            animated: animated,
            focusNodeIDs: focusNodeIDs
        )
        let nodeView = GraphNodesLayer(
            nodes: nodes,
            size: size,
            positions: positions,
            selectedNodeID: $selectedNodeID,
            showDenseLabels: showDenseLabels,
            focusNodeIDs: focusNodeIDs
        )
        
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                ZStack {
                    edgeView
                        .environment(\.graphAnimationTime, timeline.date.timeIntervalSinceReferenceDate)
                    nodeView
                }
            }
        } else {
            ZStack {
                edgeView
                    .environment(\.graphAnimationTime, 0)
                nodeView
            }
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
    
    private func graphGesture(maxZoom: CGFloat) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    pan = CGSize(
                        width: panStart.width + value.translation.width,
                        height: panStart.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    panStart = pan
                },
            MagnificationGesture()
                .onChanged { value in
                    zoom = min(max(zoomStart * value, 0.65), maxZoom)
                }
                .onEnded { _ in
                    zoomStart = zoom
                }
        )
    }
    
    private func resetViewport() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            zoom = 1.0
            pan = .zero
            zoomStart = 1.0
            panStart = .zero
            selectedNodeID = nil
        }
    }

    private func focusNodeSet(selectedID: String?, edges: [GraphEdge]) -> Set<String>? {
        guard let selectedID else { return nil }
        var neighbors: Set<String> = [selectedID]
        for edge in edges {
            if edge.fromID == selectedID {
                neighbors.insert(edge.toID)
            } else if edge.toID == selectedID {
                neighbors.insert(edge.fromID)
            }
        }
        return neighbors.count > 1 ? neighbors : nil
    }

    private func focusOnNode(
        nodeID: String,
        positions: [String: CGPoint],
        canvasSize: CGSize,
        targetZoom: CGFloat,
        maxZoom: CGFloat
    ) {
        guard canvasSize.width > 0, canvasSize.height > 0, let normalized = positions[nodeID] else { return }
        let zoomValue = min(max(targetZoom, 0.65), maxZoom)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let point = graphPoint(for: normalized, in: canvasSize)
        let focusedPan = CGSize(
            width: -((point.x - center.x) * zoomValue),
            height: -((point.y - center.y) * zoomValue)
        )
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            zoom = zoomValue
            pan = focusedPan
            zoomStart = zoomValue
            panStart = focusedPan
        }
    }

    private func graphPoint(for normalized: CGPoint, in size: CGSize) -> CGPoint {
        let minSide = min(size.width, size.height)
        return CGPoint(
            x: size.width / 2 + normalized.x * minSide * 0.46,
            y: size.height / 2 + normalized.y * minSide * 0.46
        )
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
    let filter: GraphFilter
    let showDenseLabels: Bool
    let onClose: () -> Void
    let onOpenNode: (GraphNode) -> Void
    
    @State private var selectedNodeID: String?
    @State private var zoom: CGFloat = 1.0
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize = .zero
    @State private var zoomStart: CGFloat = 1.0
    @State private var canvasSize: CGSize = .zero
    
    private var visibleNodes: [GraphNode] {
        applyGraphFilter(nodes: graph.nodes, edges: graph.edges, filter: filter).nodes
    }
    
    private var visibleEdges: [GraphEdge] {
        applyGraphFilter(nodes: graph.nodes, edges: graph.edges, filter: filter).edges
    }

    private var focusNodeIDs: Set<String>? {
        guard let selectedNodeID else { return nil }
        var neighbors: Set<String> = [selectedNodeID]
        for edge in visibleEdges {
            if edge.fromID == selectedNodeID {
                neighbors.insert(edge.toID)
            } else if edge.toID == selectedNodeID {
                neighbors.insert(edge.fromID)
            }
        }
        return neighbors.count > 1 ? neighbors : nil
    }

    private var displayEdges: [GraphEdge] {
        guard let focusNodeIDs else { return visibleEdges }
        return visibleEdges.filter { focusNodeIDs.contains($0.fromID) && focusNodeIDs.contains($0.toID) }
    }
    
    var body: some View {
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
                
                GeometryReader { proxy in
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        ZStack {
                            GraphEdgesLayer(
                                edges: displayEdges,
                                size: proxy.size,
                                positions: graph.positions,
                                animated: true,
                                focusNodeIDs: focusNodeIDs
                            )
                                .environment(\.graphAnimationTime, timeline.date.timeIntervalSinceReferenceDate)
                            GraphNodesLayer(
                                nodes: visibleNodes,
                                size: proxy.size,
                                positions: graph.positions,
                                selectedNodeID: $selectedNodeID,
                                showDenseLabels: showDenseLabels,
                                focusNodeIDs: focusNodeIDs
                            )
                        }
                        .scaleEffect(zoom)
                        .offset(pan)
                        .contentShape(Rectangle())
                        .gesture(graphGesture(maxZoom: 2.5))
                        .onAppear { canvasSize = proxy.size }
                        .onChange(of: proxy.size) { _, newValue in
                            canvasSize = newValue
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .foregroundStyle(.white)
        .onChange(of: selectedNodeID) { _, newValue in
            guard let newValue else { return }
            focusOnNode(nodeID: newValue, targetZoom: 1.55, maxZoom: 2.5)
        }
    }
    
    private func graphGesture(maxZoom: CGFloat) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    pan = CGSize(
                        width: panStart.width + value.translation.width,
                        height: panStart.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    panStart = pan
                },
            MagnificationGesture()
                .onChanged { value in
                    zoom = min(max(zoomStart * value, 0.65), maxZoom)
                }
                .onEnded { _ in
                    zoomStart = zoom
                }
        )
    }
    
    private func resetViewport() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            zoom = 1.0
            pan = .zero
            zoomStart = 1.0
            panStart = .zero
            selectedNodeID = nil
        }
    }

    private func focusOnNode(nodeID: String, targetZoom: CGFloat, maxZoom: CGFloat) {
        guard canvasSize.width > 0, canvasSize.height > 0, let normalized = graph.positions[nodeID] else { return }
        let zoomValue = min(max(targetZoom, 0.65), maxZoom)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let point = graphPoint(for: normalized, in: canvasSize)
        let focusedPan = CGSize(
            width: -((point.x - center.x) * zoomValue),
            height: -((point.y - center.y) * zoomValue)
        )
        withAnimation(.spring(response: 0.6, dampingFraction: 0.83)) {
            zoom = zoomValue
            pan = focusedPan
            zoomStart = zoomValue
            panStart = focusedPan
        }
    }

    private func graphPoint(for normalized: CGPoint, in size: CGSize) -> CGPoint {
        let minSide = min(size.width, size.height)
        return CGPoint(
            x: size.width / 2 + normalized.x * minSide * 0.46,
            y: size.height / 2 + normalized.y * minSide * 0.46
        )
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
        
        let maxLabels = showDenseLabels ? 30 : 15
        let minSpacing: CGFloat = showDenseLabels ? 30 : 38
        var result: [InlineLabelPlacement] = []
        
        for node in candidates {
            guard let p = positions[node.id] else { continue }
            let proposed = labelPoint(for: p)
            let overlaps = result.contains { distance($0.position, proposed) < minSpacing }
            let blockedBySelection = avoidPoints.contains { distance($0, proposed) < 72 }
            if overlaps || blockedBySelection { continue }
            
            result.append(
                InlineLabelPlacement(
                    id: node.id,
                    text: node.title,
                    tint: node.kind.color,
                    position: proposed
                )
            )
            
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
