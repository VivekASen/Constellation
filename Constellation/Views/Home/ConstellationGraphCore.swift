import SwiftUI

struct GraphData {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let positions: [String: CGPoint]
}

struct GraphNode: Identifiable {
    let id: String
    let title: String
    let kind: GraphNodeKind
    let reference: String?
}

struct GraphEdge: Identifiable {
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

struct EdgeAggregate {
    var weight: Int
    var source: GraphEdgeSource
}

enum GraphEdgeSource {
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

enum GraphNodeKind: Hashable {
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

enum GraphFilter: CaseIterable {
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

enum GraphDensityMode: CaseIterable {
    case simple
    case detailed
    
    var title: String {
        switch self {
        case .simple: return "Simple"
        case .detailed: return "Detailed"
        }
    }
}

enum GraphLabelDensity: CaseIterable {
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

enum GraphFilterToken {
    static let all = "__all__"
}

func applyGraphFilter(nodes: [GraphNode], edges: [GraphEdge], filter: GraphFilter) -> (nodes: [GraphNode], edges: [GraphEdge]) {
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

struct ThemeSelection: Identifiable {
    let id: String
}

struct GraphAnimationTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 0
}

extension EnvironmentValues {
    var graphAnimationTime: TimeInterval {
        get { self[GraphAnimationTimeKey.self] }
        set { self[GraphAnimationTimeKey.self] = newValue }
    }
}

extension String {
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
