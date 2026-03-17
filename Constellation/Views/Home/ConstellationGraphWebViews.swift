import SwiftUI
import WebKit

struct ConstellationGraphViewportSnapshot: Equatable {
    struct MiniMapPoint: Equatable {
        let id: Int
        let x: Double
        let y: Double
        let isSelected: Bool
    }

    var contentMinX: Double
    var contentMaxX: Double
    var contentMinY: Double
    var contentMaxY: Double
    var viewportMinX: Double
    var viewportMaxX: Double
    var viewportMinY: Double
    var viewportMaxY: Double
    var zoomScale: Double
    var translateX: Double
    var translateY: Double
    var points: [MiniMapPoint]

    static let empty = ConstellationGraphViewportSnapshot(
        contentMinX: 0,
        contentMaxX: 1,
        contentMinY: 0,
        contentMaxY: 1,
        viewportMinX: 0,
        viewportMaxX: 1,
        viewportMinY: 0,
        viewportMaxY: 1,
        zoomScale: 1,
        translateX: 0,
        translateY: 0,
        points: []
    )
}

struct ConstellationGraphTransform: Equatable {
    let zoomScale: Double
    let translateX: Double
    let translateY: Double
}

/// Web-backed graph renderers:
/// - Home 3D rotating preview canvas
/// - Immersive D3 force-directed graph with interactions and effects
struct Constellation3DPreviewWebView: UIViewRepresentable {
    let nodes: [ConstellationGraphNode]
    let edges: [ConstellationGraphEdge]
    @Binding var selectedNodeID: String?
    let resetToken: Int
    let onInteraction: () -> Void
    let onOpenNode: (String) -> Void
    
    // MARK: - UIViewRepresentable
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "nodeTap")
        userContent.add(context.coordinator, name: "nodeOpen")
        userContent.add(context.coordinator, name: "interaction")
        config.userContentController = userContent
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pushBindings(selectedNodeID: $selectedNodeID, onOpenNode: onOpenNode, onInteraction: onInteraction)
        
        if let rendered = context.coordinator.initialHTML(payload: payload()) {
            webView.loadHTMLString(rendered.html, baseURL: rendered.baseURL)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.pushBindings(selectedNodeID: $selectedNodeID, onOpenNode: onOpenNode, onInteraction: onInteraction)
        context.coordinator.pushGraph(payload(), selectedNodeID: selectedNodeID, resetToken: resetToken)
    }
    
    private func payload() -> D3GraphPayload {
        let sortedNodes = nodes.sorted { $0.id < $1.id }
        let sortedEdges = edges.sorted {
            if $0.fromID == $1.fromID {
                if $0.toID == $1.toID {
                    return $0.weight < $1.weight
                }
                return $0.toID < $1.toID
            }
            return $0.fromID < $1.fromID
        }
        return D3GraphPayload(
            nodes: sortedNodes.map {
                D3NodePayload(
                    id: $0.id,
                    title: $0.title,
                    kind: $0.kind.d3Kind,
                    color: $0.kind.webColor,
                    icon: $0.kind.icon
                )
            },
            links: sortedEdges.map {
                D3LinkPayload(
                    source: $0.fromID,
                    target: $0.toID,
                    weight: $0.weight
                )
            },
            labelDensity: ConstellationGraphLabelDensity.medium.d3Token
        )
    }
    
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var didFinishLoad = false
        private var lastGraphJSON: String?
        private var lastResetToken: Int = 0
        private var setSelectedNode: (String?) -> Void = { _ in }
        private var openNode: (String) -> Void = { _ in }
        private var interaction: () -> Void = {}
        
        // MARK: - Bindings
        func pushBindings(
            selectedNodeID: Binding<String?>,
            onOpenNode: @escaping (String) -> Void,
            onInteraction: @escaping () -> Void
        ) {
            self.setSelectedNode = { selectedNodeID.wrappedValue = $0 }
            self.openNode = onOpenNode
            self.interaction = onInteraction
        }
        
        // MARK: - Graph Sync
        func initialHTML(payload: D3GraphPayload) -> (html: String, baseURL: URL?)? {
            guard let json = payload.jsonString else { return nil }
            lastGraphJSON = json
            return ConstellationGraphHTMLLoader.renderedTemplate(named: Self.htmlTemplateName, payloadJSON: json)
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
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoad = true
            if let json = lastGraphJSON {
                webView.evaluateJavaScript("window.__updateGraph(\(json));")
            }
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "interaction" {
                interaction()
                return
            }
            
            if message.name == "nodeTap" {
                let id = message.body as? String
                setSelectedNode((id?.isEmpty == false) ? id : nil)
            } else if message.name == "nodeOpen" {
                guard let id = message.body as? String, !id.isEmpty else { return }
                openNode(id)
            }
        }
        
        // MARK: - HTML
        static let htmlTemplateName = "Constellation3DPreview.html"
    }
}

struct ConstellationD3WebView: UIViewRepresentable {
    let nodes: [ConstellationGraphNode]
    let edges: [ConstellationGraphEdge]
    @Binding var selectedNodeID: String?
    let focusNodeID: String?
    let resetToken: Int
    let fitToContentToken: Int
    let graphRevision: Int
    let initialTransform: ConstellationGraphTransform?
    let labelDensity: ConstellationGraphLabelDensity
    let onOpenNode: (String) -> Void
    let onViewportChange: (ConstellationGraphViewportSnapshot) -> Void
    let onInteractionChanged: (Bool) -> Void
    
    // MARK: - UIViewRepresentable
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "nodeTap")
        userContent.add(context.coordinator, name: "nodeOpen")
        userContent.add(context.coordinator, name: "viewport")
        userContent.add(context.coordinator, name: "interaction")
        config.userContentController = userContent
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pushBindings(
            selectedNodeID: $selectedNodeID,
            onOpenNode: onOpenNode,
            onViewportChange: onViewportChange,
            onInteractionChanged: onInteractionChanged
        )
        
        if let rendered = context.coordinator.initialHTML(payload: payload()) {
            webView.loadHTMLString(rendered.html, baseURL: rendered.baseURL)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.pushBindings(
            selectedNodeID: $selectedNodeID,
            onOpenNode: onOpenNode,
            onViewportChange: onViewportChange,
            onInteractionChanged: onInteractionChanged
        )
        context.coordinator.pushGraph(
            payload(),
            selectedNodeID: selectedNodeID,
            focusNodeID: focusNodeID,
            resetToken: resetToken,
            fitToContentToken: fitToContentToken,
            graphRevision: graphRevision,
            initialTransform: initialTransform
        )
    }
    
    private func payload() -> D3GraphPayload {
        let sortedNodes = nodes.sorted { $0.id < $1.id }
        let sortedEdges = edges.sorted {
            if $0.fromID == $1.fromID {
                if $0.toID == $1.toID {
                    return $0.weight < $1.weight
                }
                return $0.toID < $1.toID
            }
            return $0.fromID < $1.fromID
        }
        return D3GraphPayload(
            nodes: sortedNodes.map {
                D3NodePayload(
                    id: $0.id,
                    title: $0.title,
                    kind: $0.kind.d3Kind,
                    color: $0.kind.webColor,
                    icon: $0.kind.icon
                )
            },
            links: sortedEdges.map {
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
        private var lastFitToContentToken: Int = 0
        private var lastGraphRevision: Int = -1
        private var hasAppliedInitialTransform = false
        private var hasSyncedSelection = false
        private var lastSelectedNodeID: String?
        private var lastFocusedNodeID: String?
        private var lastViewportSnapshot: ConstellationGraphViewportSnapshot?
        private var setSelectedNode: (String?) -> Void = { _ in }
        private var openNode: (String) -> Void = { _ in }
        private var viewportChanged: (ConstellationGraphViewportSnapshot) -> Void = { _ in }
        private var interactionChanged: (Bool) -> Void = { _ in }
        
        // MARK: - Bindings
        func pushBindings(
            selectedNodeID: Binding<String?>,
            onOpenNode: @escaping (String) -> Void,
            onViewportChange: @escaping (ConstellationGraphViewportSnapshot) -> Void,
            onInteractionChanged: @escaping (Bool) -> Void
        ) {
            self.setSelectedNode = { selectedNodeID.wrappedValue = $0 }
            self.openNode = onOpenNode
            self.viewportChanged = onViewportChange
            self.interactionChanged = onInteractionChanged
        }
        
        // MARK: - Graph Sync
        func initialHTML(payload: D3GraphPayload) -> (html: String, baseURL: URL?)? {
            guard let json = payload.jsonString else { return nil }
            lastGraphJSON = json
            return ConstellationGraphHTMLLoader.renderedTemplate(named: Self.htmlTemplateName, payloadJSON: json)
        }
        
        func pushGraph(_ payload: D3GraphPayload, selectedNodeID: String?, focusNodeID: String?, resetToken: Int, fitToContentToken: Int, graphRevision: Int, initialTransform: ConstellationGraphTransform?) {
            guard didFinishLoad, let webView, let json = payload.jsonString else { return }
            
            if graphRevision != lastGraphRevision || lastGraphJSON == nil {
                let updateJS = "window.__updateGraph(\(json));"
                webView.evaluateJavaScript(updateJS)
                lastGraphJSON = json
                lastGraphRevision = graphRevision
                lastViewportSnapshot = nil
                hasAppliedInitialTransform = false
            }
            
            if !hasSyncedSelection || selectedNodeID != lastSelectedNodeID {
                hasSyncedSelection = true
                lastSelectedNodeID = selectedNodeID
                if let selectedNodeID, let selectedLiteral = selectedNodeID.jsSingleQuoted {
                    webView.evaluateJavaScript("window.__selectNode(\(selectedLiteral));")
                } else {
                    webView.evaluateJavaScript("window.__selectNode(null);")
                }
            }

            if let focusNodeID, focusNodeID != lastFocusedNodeID, let focusLiteral = focusNodeID.jsSingleQuoted {
                lastFocusedNodeID = focusNodeID
                webView.evaluateJavaScript("window.__focusNode(\(focusLiteral));")
            }
            
            if resetToken != lastResetToken {
                lastResetToken = resetToken
                lastFocusedNodeID = nil
                lastViewportSnapshot = nil
                hasAppliedInitialTransform = false
                webView.evaluateJavaScript("window.__resetView();")
            }

            if fitToContentToken != lastFitToContentToken {
                lastFitToContentToken = fitToContentToken
                webView.evaluateJavaScript("window.__fitToContent();")
            }

            if !hasAppliedInitialTransform, let initialTransform {
                hasAppliedInitialTransform = true
                let js = "window.__setTransform(\(initialTransform.zoomScale), \(initialTransform.translateX), \(initialTransform.translateY), false);"
                webView.evaluateJavaScript(js)
            }
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoad = true
            if let json = lastGraphJSON {
                webView.evaluateJavaScript("window.__updateGraph(\(json));")
            }
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "viewport",
               let payload = message.body as? [String: Any],
               let contentMinX = payload["contentMinX"] as? Double,
               let contentMaxX = payload["contentMaxX"] as? Double,
               let contentMinY = payload["contentMinY"] as? Double,
               let contentMaxY = payload["contentMaxY"] as? Double,
               let viewportMinX = payload["viewportMinX"] as? Double,
               let viewportMaxX = payload["viewportMaxX"] as? Double,
               let viewportMinY = payload["viewportMinY"] as? Double,
               let viewportMaxY = payload["viewportMaxY"] as? Double {
                let zoomScale = payload["zoomScale"] as? Double ?? 1
                let translateX = payload["translateX"] as? Double ?? 0
                let translateY = payload["translateY"] as? Double ?? 0
                let pointsPayload = payload["points"] as? [[String: Any]] ?? []
                let points: [ConstellationGraphViewportSnapshot.MiniMapPoint] = pointsPayload.enumerated().compactMap { index, item in
                    guard let x = item["x"] as? Double, let y = item["y"] as? Double else { return nil }
                    let isSelected = item["selected"] as? Bool ?? false
                    return ConstellationGraphViewportSnapshot.MiniMapPoint(id: index, x: x, y: y, isSelected: isSelected)
                }
                let snapshot = ConstellationGraphViewportSnapshot(
                    contentMinX: contentMinX,
                    contentMaxX: contentMaxX,
                    contentMinY: contentMinY,
                    contentMaxY: contentMaxY,
                    viewportMinX: viewportMinX,
                    viewportMaxX: viewportMaxX,
                    viewportMinY: viewportMinY,
                    viewportMaxY: viewportMaxY,
                    zoomScale: zoomScale,
                    translateX: translateX,
                    translateY: translateY,
                    points: points
                )
                guard shouldPublishViewport(snapshot) else { return }
                lastViewportSnapshot = snapshot
                viewportChanged(snapshot)
                return
            }

            if message.name == "interaction",
               let state = message.body as? String {
                interactionChanged(state == "start")
                return
            }

            if message.name == "nodeTap" {
                let id = message.body as? String
                hasSyncedSelection = true
                lastSelectedNodeID = id
                setSelectedNode((id?.isEmpty == false) ? id : nil)
            } else if message.name == "nodeOpen" {
                guard let id = message.body as? String, !id.isEmpty else { return }
                openNode(id)
            }
        }
        
        // MARK: - HTML
        static let htmlTemplateName = "ConstellationImmersiveD3.html"

        private func shouldPublishViewport(_ snapshot: ConstellationGraphViewportSnapshot) -> Bool {
            guard let previous = lastViewportSnapshot else { return true }

            let worldWidth = max(0.001, previous.contentMaxX - previous.contentMinX)
            let worldHeight = max(0.001, previous.contentMaxY - previous.contentMinY)
            let xDelta = abs(snapshot.viewportMinX - previous.viewportMinX)
            let yDelta = abs(snapshot.viewportMinY - previous.viewportMinY)
            let wDelta = abs((snapshot.viewportMaxX - snapshot.viewportMinX) - (previous.viewportMaxX - previous.viewportMinX))
            let hDelta = abs((snapshot.viewportMaxY - snapshot.viewportMinY) - (previous.viewportMaxY - previous.viewportMinY))

            let movedEnough = xDelta > worldWidth * 0.01 || yDelta > worldHeight * 0.01
            let zoomedEnough = wDelta > worldWidth * 0.01 || hDelta > worldHeight * 0.01
            let pointsChanged = snapshot.points.count != previous.points.count
            return movedEnough || zoomedEnough || pointsChanged
        }
    }
}

struct D3GraphPayload: Codable {
    let nodes: [D3NodePayload]
    let links: [D3LinkPayload]
    let labelDensity: String
    
    // MARK: - Encoding
    var jsonString: String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
}

struct D3NodePayload: Codable {
    let id: String
    let title: String
    let kind: String
    let color: String
    let icon: String
}

struct D3LinkPayload: Codable {
    let source: String
    let target: String
    let weight: Int
}

private enum ConstellationGraphHTMLLoader {
    private static let placeholderToken = "__INITIAL_GRAPH_JSON__"
    private static let searchSubdirectories: [String?] = ["Resources/Graph", "Graph", nil]
    
    static func renderedTemplate(named resourceName: String, payloadJSON: String) -> (html: String, baseURL: URL?)? {
        guard let url = templateURL(named: resourceName) else { return nil }
        guard let template = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let html = template.replacingOccurrences(of: placeholderToken, with: payloadJSON)
        return (html: html, baseURL: url.deletingLastPathComponent())
    }
    
    private static func templateURL(named resourceName: String) -> URL? {
        let split = resourceName.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let base = String(split.first ?? "")
        let ext = split.count > 1 ? String(split[1]) : nil
        
        for subdirectory in searchSubdirectories {
            if let ext,
               let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
            if let url = Bundle.main.url(forResource: resourceName, withExtension: nil, subdirectory: subdirectory) {
                return url
            }
        }
        
        return nil
    }
}
