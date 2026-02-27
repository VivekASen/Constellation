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
    
    @State private var selectedMovie: Movie?
    @State private var selectedTVShow: TVShow?
    @State private var selectedTheme: ThemeSelection?
    
    var body: some View {
        let graph = buildGraph()
        let visibleKinds = filter.visibleKinds
        let visibleNodes = graph.nodes.filter { visibleKinds.contains($0.kind) }
        let visibleNodeIDs = Set(visibleNodes.map(\.id))
        let visibleEdges = graph.edges.filter { visibleNodeIDs.contains($0.fromID) && visibleNodeIDs.contains($0.toID) }
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Constellation Graph")
                    .font(.headline)
                
                Spacer()
                
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
            }
            
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                    
                    graphLayer(
                        size: proxy.size,
                        nodes: visibleNodes,
                        edges: visibleEdges,
                        positions: graph.positions
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
            .frame(height: 330)
            
            if let selected = graph.nodes.first(where: { $0.id == selectedNodeID }) {
                selectedNodePanel(selected)
            }
        }
        .sheet(item: $selectedMovie) { movie in
            NavigationStack {
                MovieDetailView(movie: movie)
            }
        }
        .sheet(item: $selectedTVShow) { show in
            NavigationStack {
                TVShowDetailView(show: show)
            }
        }
        .sheet(item: $selectedTheme) { theme in
            NavigationStack {
                ThemeDetailView(themeName: theme.id)
            }
        }
    }
    
    @ViewBuilder
    private func graphLayer(
        size: CGSize,
        nodes: [GraphNode],
        edges: [GraphEdge],
        positions: [String: CGPoint]
    ) -> some View {
        ZStack {
            ForEach(edges) { edge in
                if let from = positions[edge.fromID], let to = positions[edge.toID] {
                    Path { path in
                        path.move(to: point(for: from, in: size))
                        path.addLine(to: point(for: to, in: size))
                    }
                    .stroke(Color.gray.opacity(edge.weight > 1 ? 0.4 : 0.24), lineWidth: edge.weight > 1 ? 1.6 : 1.0)
                }
            }
            
            ForEach(nodes) { node in
                if let position = positions[node.id] {
                    GraphNodeBubble(node: node, isSelected: selectedNodeID == node.id)
                        .position(point(for: position, in: size))
                        .onTapGesture {
                            selectedNodeID = node.id
                        }
                }
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
    
    private func point(for normalized: CGPoint, in size: CGSize) -> CGPoint {
        let minSide = min(size.width, size.height)
        return CGPoint(
            x: size.width / 2 + normalized.x * minSide * 0.44,
            y: size.height / 2 + normalized.y * minSide * 0.44
        )
    }
    
    private func buildGraph() -> GraphData {
        let trimmedMovies = Array(movies.prefix(14))
        let trimmedShows = Array(tvShows.prefix(14))
        
        let themeCounts = Dictionary(grouping: (trimmedMovies.flatMap(\.themes) + trimmedShows.flatMap(\.themes)), by: { $0 })
            .mapValues(\.count)
        
        let topThemes = themeCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(16)
            .map(\.key)
        
        var nodes: [GraphNode] = []
        var positions: [String: CGPoint] = [:]
        var edgeWeights: [String: Int] = [:]
        
        for (index, movie) in trimmedMovies.enumerated() {
            let node = GraphNode(
                id: "movie::\(movie.id.uuidString)",
                title: movie.title,
                kind: .movie,
                reference: movie.id.uuidString
            )
            nodes.append(node)
            positions[node.id] = ringPosition(index: index, total: max(trimmedMovies.count, 1), radius: 0.73, phase: 0.0)
        }
        
        for (index, show) in trimmedShows.enumerated() {
            let node = GraphNode(
                id: "show::\(show.id.uuidString)",
                title: show.title,
                kind: .tvShow,
                reference: show.id.uuidString
            )
            nodes.append(node)
            positions[node.id] = ringPosition(index: index, total: max(trimmedShows.count, 1), radius: 0.54, phase: .pi / 6)
        }
        
        for (index, theme) in topThemes.enumerated() {
            let node = GraphNode(
                id: "theme::\(theme)",
                title: theme,
                kind: .theme,
                reference: theme
            )
            nodes.append(node)
            positions[node.id] = ringPosition(index: index, total: max(topThemes.count, 1), radius: 0.3, phase: .pi / 12)
        }
        
        let topThemeSet = Set(topThemes)
        
        for movie in trimmedMovies {
            let fromID = "movie::\(movie.id.uuidString)"
            for theme in movie.themes where topThemeSet.contains(theme) {
                let toID = "theme::\(theme)"
                incrementEdgeWeight(fromID: fromID, toID: toID, in: &edgeWeights)
            }
        }
        
        for show in trimmedShows {
            let fromID = "show::\(show.id.uuidString)"
            for theme in show.themes where topThemeSet.contains(theme) {
                let toID = "theme::\(theme)"
                incrementEdgeWeight(fromID: fromID, toID: toID, in: &edgeWeights)
            }
        }
        
        let movieIDs = Set(trimmedMovies.map { $0.id.uuidString })
        let showIDs = Set(trimmedShows.map { $0.id.uuidString })
        
        for collection in collections {
            let members = (collection.movieIDs.filter { movieIDs.contains($0) }.map { "movie::\($0)" }
                + collection.showIDs.filter { showIDs.contains($0) }.map { "show::\($0)" })
            
            if members.count < 2 { continue }
            
            for i in 0..<(members.count - 1) {
                for j in (i + 1)..<members.count {
                    incrementEdgeWeight(fromID: members[i], toID: members[j], in: &edgeWeights)
                }
            }
        }
        
        let edges = edgeWeights.map { key, weight -> GraphEdge in
            let ids = key.split(separator: "|").map(String.init)
            return GraphEdge(id: key, fromID: ids[0], toID: ids[1], weight: weight)
        }
        
        return GraphData(nodes: nodes, edges: edges, positions: positions)
    }
    
    private func ringPosition(index: Int, total: Int, radius: CGFloat, phase: CGFloat) -> CGPoint {
        guard total > 0 else { return .zero }
        let angle = (CGFloat(index) / CGFloat(total)) * (.pi * 2) + phase
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }
    
    private func incrementEdgeWeight(fromID: String, toID: String, in storage: inout [String: Int]) {
        let key = fromID < toID ? "\(fromID)|\(toID)" : "\(toID)|\(fromID)"
        storage[key, default: 0] += 1
    }
}

private struct GraphNodeBubble: View {
    let node: GraphNode
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(node.kind.color.opacity(isSelected ? 0.95 : 0.8))
                .frame(width: isSelected ? 26 : 22, height: isSelected ? 26 : 22)
                .overlay {
                    Text(node.kind.icon)
                        .font(.system(size: 11))
                }
            
            Text(node.title)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 74)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 3)
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
}

private enum GraphNodeKind {
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

private struct ThemeSelection: Identifiable {
    let id: String
}
