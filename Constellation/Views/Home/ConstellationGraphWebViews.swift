import SwiftUI
import WebKit

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
            
            guard let id = message.body as? String else { return }
            if message.name == "nodeTap" {
                setSelectedNode(id)
            } else if message.name == "nodeOpen" {
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
    let resetToken: Int
    let labelDensity: ConstellationGraphLabelDensity
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
        config.userContentController = userContent
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.pushBindings(selectedNodeID: $selectedNodeID, onOpenNode: onOpenNode)
        
        if let rendered = context.coordinator.initialHTML(payload: payload()) {
            webView.loadHTMLString(rendered.html, baseURL: rendered.baseURL)
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
        
        // MARK: - Bindings
        func pushBindings(selectedNodeID: Binding<String?>, onOpenNode: @escaping (String) -> Void) {
            self.setSelectedNode = { selectedNodeID.wrappedValue = $0 }
            self.openNode = onOpenNode
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
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoad = true
            if let json = lastGraphJSON {
                webView.evaluateJavaScript("window.__updateGraph(\(json));")
            }
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let id = message.body as? String else { return }
            if message.name == "nodeTap" {
                setSelectedNode(id)
            } else if message.name == "nodeOpen" {
                openNode(id)
            }
        }
        
        // MARK: - HTML
        static let htmlTemplateName = "ConstellationImmersiveD3.html"
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
