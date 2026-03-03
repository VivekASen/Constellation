import SwiftUI

/// Shared graph domain models, enums, and helper filtering logic.
/// Kept renderer-agnostic so both Home (3D preview) and immersive (D3) can reuse it.
struct ConstellationGraphData {
    let nodes: [ConstellationGraphNode]
    let edges: [ConstellationGraphEdge]
    let positions: [String: CGPoint]
}

struct ConstellationGraphNode: Identifiable {
    let id: String
    let title: String
    let kind: ConstellationGraphNodeKind
    let reference: String?
}

struct ConstellationGraphEdge: Identifiable {
    let id: String
    let fromID: String
    let toID: String
    let weight: Int
    let source: ConstellationGraphEdgeSource
    
    // MARK: - Styling
    var baseColor: Color {
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
    
    var highlightColor: Color {
        switch source {
        case .theme:
            return Color.gray
        case .genre:
            return Color.orange
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

struct ConstellationGraphEdgeAggregate {
    var weight: Int
    var source: ConstellationGraphEdgeSource
}

enum ConstellationGraphEdgeSource {
    case theme
    case genre
    case collection
    case hybrid
    
    var containsCollection: Bool {
        self == .collection || self == .hybrid
    }
    
    func merged(with other: ConstellationGraphEdgeSource) -> ConstellationGraphEdgeSource {
        if self == other { return self }
        return .hybrid
    }
    
    var priority: Int {
        switch self {
        case .hybrid: return 3
        case .collection: return 2
        case .theme: return 1
        case .genre: return 1
        }
    }
}

enum ConstellationGraphNodeKind: Hashable {
    case movie
    case tvShow
    case book
    case theme
    case genre
    
    // MARK: - Presentation
    var color: Color {
        switch self {
        case .movie: return .blue
        case .tvShow: return .green
        case .book: return .orange
        case .theme: return .purple
        case .genre: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .movie: return "🎬"
        case .tvShow: return "📺"
        case .book: return "📚"
        case .theme: return "⭐"
        case .genre: return "🏷️"
        }
    }
    
    var label: String {
        switch self {
        case .movie: return "Movie"
        case .tvShow: return "TV Show"
        case .book: return "Book"
        case .theme: return "Theme"
        case .genre: return "Genre"
        }
    }
    
    var labelPriority: Int {
        switch self {
        case .theme: return 3
        case .genre: return 2
        case .movie: return 2
        case .tvShow: return 1
        case .book: return 1
        }
    }
    
    var webColor: String {
        switch self {
        case .movie: return "#3b82f6"
        case .tvShow: return "#22c55e"
        case .book: return "#f97316"
        case .theme: return "#c026d3"
        case .genre: return "#f59e0b"
        }
    }
    
    var d3Kind: String {
        switch self {
        case .movie: return "movie"
        case .tvShow: return "tvShow"
        case .book: return "book"
        case .theme: return "theme"
        case .genre: return "genre"
        }
    }
}

enum ConstellationGraphFilter: CaseIterable {
    case all
    case movies
    case tvShows
    case books
    case themes
    case genres
    
    var title: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .tvShows: return "TV"
        case .books: return "Books"
        case .themes: return "Themes"
        case .genres: return "Genres"
        }
    }
    
    var visibleKinds: Set<ConstellationGraphNodeKind> {
        switch self {
        case .all: return [.movie, .tvShow, .book, .theme, .genre]
        case .movies: return [.movie, .theme, .genre]
        case .tvShows: return [.tvShow, .theme, .genre]
        case .books: return [.book, .theme, .genre]
        case .themes: return [.theme]
        case .genres: return [.genre]
        }
    }
}

enum ConstellationGraphDensityMode: CaseIterable {
    case simple
    case detailed
    
    var title: String {
        switch self {
        case .simple: return "Simple"
        case .detailed: return "Detailed"
        }
    }
}

enum ConstellationGraphLabelDensity: CaseIterable {
    case low
    case medium
    case high
    
    // MARK: - Presentation
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

enum ConstellationGraphFilterToken {
    static let all = "__all__"
}

func applyConstellationGraphFilter(nodes: [ConstellationGraphNode], edges: [ConstellationGraphEdge], filter: ConstellationGraphFilter) -> (nodes: [ConstellationGraphNode], edges: [ConstellationGraphEdge]) {
    let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    
    // Preserve node/edge ordering while constraining to allowed node IDs.
    func filtered(allowedIDs: Set<String>) -> (nodes: [ConstellationGraphNode], edges: [ConstellationGraphEdge]) {
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

    case .genres:
        let genreIDs = Set(nodes.filter { $0.kind == .genre }.map(\.id))
        return filtered(allowedIDs: genreIDs)
        
    case .movies:
        let movieIDs = Set(nodes.filter { $0.kind == .movie }.map(\.id))
        var allowed = movieIDs
        
        for edge in edges {
            guard let fromKind = nodeByID[edge.fromID]?.kind, let toKind = nodeByID[edge.toID]?.kind else { continue }
            if fromKind == .movie && (toKind == .theme || toKind == .genre) {
                allowed.insert(edge.toID)
            } else if (fromKind == .theme || fromKind == .genre) && toKind == .movie {
                allowed.insert(edge.fromID)
            }
        }
        
        return filtered(allowedIDs: allowed)
        
    case .tvShows:
        let showIDs = Set(nodes.filter { $0.kind == .tvShow }.map(\.id))
        var allowed = showIDs
        
        for edge in edges {
            guard let fromKind = nodeByID[edge.fromID]?.kind, let toKind = nodeByID[edge.toID]?.kind else { continue }
            if fromKind == .tvShow && (toKind == .theme || toKind == .genre) {
                allowed.insert(edge.toID)
            } else if (fromKind == .theme || fromKind == .genre) && toKind == .tvShow {
                allowed.insert(edge.fromID)
            }
        }
        
        return filtered(allowedIDs: allowed)

    case .books:
        let bookIDs = Set(nodes.filter { $0.kind == .book }.map(\.id))
        var allowed = bookIDs

        for edge in edges {
            guard let fromKind = nodeByID[edge.fromID]?.kind, let toKind = nodeByID[edge.toID]?.kind else { continue }
            if fromKind == .book && (toKind == .theme || toKind == .genre) {
                allowed.insert(edge.toID)
            } else if (fromKind == .theme || fromKind == .genre) && toKind == .book {
                allowed.insert(edge.fromID)
            }
        }

        return filtered(allowedIDs: allowed)
    }
}

struct ConstellationThemeSelection: Identifiable {
    let id: String
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
