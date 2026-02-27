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
    
    @State private var selectedMovie: Movie?
    @State private var selectedTVShow: TVShow?
    @State private var selectedTheme: ThemeSelection?
    
    var body: some View {
        let themeOptions = Array(Set(movies.flatMap(\.themes) + tvShows.flatMap(\.themes))).sorted()
        let collectionOptions = collections.sorted { $0.name < $1.name }
        let selectedTheme = selectedThemeFilter == GraphFilterToken.all ? nil : selectedThemeFilter
        let selectedCollection = selectedCollectionFilter == GraphFilterToken.all ? nil : selectedCollectionFilter
        
        let graph = buildGraph(themeFilter: selectedTheme, collectionFilter: selectedCollection)
        let visibleKinds = filter.visibleKinds
        let visibleNodes = graph.nodes.filter { visibleKinds.contains($0.kind) }
        let visibleNodeIDs = Set(visibleNodes.map(\.id))
        let visibleEdges = graph.edges.filter { visibleNodeIDs.contains($0.fromID) && visibleNodeIDs.contains($0.toID) }
        let showDenseLabels = visibleNodes.count <= 22 || selectedTheme != nil || selectedCollection != nil
        
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
                        nodes: visibleNodes,
                        edges: visibleEdges,
                        positions: graph.positions,
                        animated: false,
                        showDenseLabels: showDenseLabels
                    )
                    .scaleEffect(zoom)
                    .offset(pan)
                    .gesture(
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    pan = value.translation
                                },
                            MagnificationGesture()
                                .onChanged { value in
                                    zoom = min(max(value, 0.7), 2.2)
                                }
                        )
                    )
                    
                    if visibleNodes.isEmpty {
                        ContentUnavailableView(
                            "No Graph Nodes",
                            systemImage: "network",
                            description: Text("Add more items to render meaningful graph connections")
                        )
                    }
                }
            }
            .frame(height: 390)
            
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
    }
    
    @ViewBuilder
    private func graphLayer(
        size: CGSize,
        nodes: [GraphNode],
        edges: [GraphEdge],
        positions: [String: CGPoint],
        animated: Bool,
        showDenseLabels: Bool
    ) -> some View {
        let edgeView = GraphEdgesLayer(edges: edges, size: size, positions: positions, animated: animated)
        let nodeView = GraphNodesLayer(
            nodes: nodes,
            size: size,
            positions: positions,
            selectedNodeID: $selectedNodeID,
            showDenseLabels: showDenseLabels
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
    
    private func buildGraph(themeFilter: String?, collectionFilter: String?) -> GraphData {
        let recentMovieIDs = Set(movies.prefix(14).map { $0.id.uuidString })
        let recentShowIDs = Set(tvShows.prefix(14).map { $0.id.uuidString })
        let collectionMovieIDs = Set(collections.flatMap(\.movieIDs))
        let collectionShowIDs = Set(collections.flatMap(\.showIDs))
        
        var selectedMovies = Array(
            movies.filter { recentMovieIDs.contains($0.id.uuidString) || collectionMovieIDs.contains($0.id.uuidString) }
                .prefix(16)
        )
        var selectedShows = Array(
            tvShows.filter { recentShowIDs.contains($0.id.uuidString) || collectionShowIDs.contains($0.id.uuidString) }
                .prefix(16)
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
        
        let topThemes = themeCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(themeFilter == nil ? 12 : 8)
            .map(\.key)
        
        var nodes: [GraphNode] = []
        var positions: [String: CGPoint] = [:]
        var edgeMeta: [String: EdgeAggregate] = [:]
        
        for (index, movie) in selectedMovies.enumerated() {
            let node = GraphNode(id: "movie::\(movie.id.uuidString)", title: movie.title, kind: .movie, reference: movie.id.uuidString)
            nodes.append(node)
            positions[node.id] = ringPosition(index: index, total: max(selectedMovies.count, 1), radius: 0.86, phase: 0.0)
        }
        
        for (index, show) in selectedShows.enumerated() {
            let node = GraphNode(id: "show::\(show.id.uuidString)", title: show.title, kind: .tvShow, reference: show.id.uuidString)
            nodes.append(node)
            positions[node.id] = ringPosition(index: index, total: max(selectedShows.count, 1), radius: 0.66, phase: .pi / 8)
        }
        
        for (index, theme) in topThemes.enumerated() {
            let node = GraphNode(id: "theme::\(theme)", title: theme, kind: .theme, reference: theme)
            nodes.append(node)
            positions[node.id] = ringPosition(index: index, total: max(topThemes.count, 1), radius: 0.42, phase: .pi / 12)
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
        
        return GraphData(nodes: nodes, edges: Array(prioritizedEdges), positions: positions)
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
    
    private var visibleNodes: [GraphNode] {
        let kinds = filter.visibleKinds
        return graph.nodes.filter { kinds.contains($0.kind) }
    }
    
    private var visibleEdges: [GraphEdge] {
        let ids = Set(visibleNodes.map(\.id))
        return graph.edges.filter { ids.contains($0.fromID) && ids.contains($0.toID) }
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                GeometryReader { proxy in
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        ZStack {
                            GraphEdgesLayer(edges: visibleEdges, size: proxy.size, positions: graph.positions, animated: true)
                                .environment(\.graphAnimationTime, timeline.date.timeIntervalSinceReferenceDate)
                            GraphNodesLayer(
                                nodes: visibleNodes,
                                size: proxy.size,
                                positions: graph.positions,
                                selectedNodeID: $selectedNodeID,
                                showDenseLabels: showDenseLabels
                            )
                        }
                        .scaleEffect(zoom)
                        .offset(pan)
                        .gesture(
                            SimultaneousGesture(
                                DragGesture().onChanged { value in
                                    pan = value.translation
                                },
                                MagnificationGesture().onChanged { value in
                                    zoom = min(max(value, 0.7), 2.5)
                                }
                            )
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .foregroundStyle(.white)
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
                    
                    line
                        .stroke(edge.baseColor.opacity(edge.opacity), lineWidth: edge.width)
                    
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
            x: size.width / 2 + normalized.x * minSide * 0.44,
            y: size.height / 2 + normalized.y * minSide * 0.44
        )
    }
}

private struct GraphNodesLayer: View {
    let nodes: [GraphNode]
    let size: CGSize
    let positions: [String: CGPoint]
    @Binding var selectedNodeID: String?
    let showDenseLabels: Bool
    
    var body: some View {
        ZStack {
            ForEach(nodes) { node in
                if let position = positions[node.id] {
                    GraphNodeBubble(node: node, isSelected: selectedNodeID == node.id)
                        .position(point(for: position, in: size))
                        .onTapGesture {
                            selectedNodeID = node.id
                        }
                    
                    if shouldShowInlineLabel(for: node) {
                        InlineNodeLabel(text: node.title, tint: node.kind.color)
                            .position(labelPoint(for: position))
                            .allowsHitTesting(false)
                    }
                }
            }
            
            if let selectedNodeID,
               let selectedNode = nodes.first(where: { $0.id == selectedNodeID }),
               let selectedPosition = positions[selectedNodeID] {
                SelectedNodeLabel(node: selectedNode)
                    .position(
                        CGPoint(
                            x: point(for: selectedPosition, in: size).x,
                            y: point(for: selectedPosition, in: size).y - 24
                        )
                    )
            }
        }
    }
    
    private func point(for normalized: CGPoint, in size: CGSize) -> CGPoint {
        let minSide = min(size.width, size.height)
        return CGPoint(
            x: size.width / 2 + normalized.x * minSide * 0.44,
            y: size.height / 2 + normalized.y * minSide * 0.44
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
    
    private func shouldShowInlineLabel(for node: GraphNode) -> Bool {
        if selectedNodeID == node.id { return false }
        if node.kind == .theme { return true }
        return showDenseLabels
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

private enum GraphFilterToken {
    static let all = "__all__"
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
