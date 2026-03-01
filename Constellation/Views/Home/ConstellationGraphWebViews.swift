import SwiftUI
import WebKit

struct Constellation3DPreviewWebView: UIViewRepresentable {
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
    let velocityY = 0.0;
    const baseAutoSpinY = 0.0008;
    const idleResumeMs = 2600;
    let autoSpin = true;
    let lastInteractionAt = Date.now();
    let dragging = false;
    let lastX = 0;
    let lastY = 0;
    let hoverNodeId = null;
    let lastTap = { id: null, time: 0 };
    let frontCaptionNodeIds = [];
    
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
      
      frontCaptionNodeIds.length = 0;
      const frontCandidates = projected
        .slice()
        .sort((a, b) => a.depth - b.depth)
        .slice(0, 8);
      const minLabelDistance = 50;
      for (const c of frontCandidates) {
        if (frontCaptionNodeIds.length >= 5) break;
        const tooClose = frontCaptionNodeIds.some((picked) => {
          const dx = picked.px - c.px;
          const dy = picked.py - c.py;
          return Math.hypot(dx, dy) < minLabelDistance;
        });
        if (!tooClose) {
          frontCaptionNodeIds.push(c);
        }
      }
      
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
        
        const isFrontCaption = !hoverNodeId && !selectedNodeId && autoSpin && frontCaptionNodeIds.some((n) => n.node.id === p.node.id);
        if (isHover || isSelected || isFrontCaption) {
          drawLabel(p.node.title, p.px + 11, p.py - 10, isFrontCaption ? 0.92 : 1.0);
        }
      }
    }
    
    function drawLabel(text, x, y, alpha = 1.0) {
      const a = Math.max(0.2, Math.min(1.0, alpha));
      ctx.font = "12px -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif";
      const w = Math.min(188, Math.max(52, ctx.measureText(text).width + 14));
      const h = 24;
      ctx.fillStyle = `rgba(18, 24, 48, ${0.86 * a})`;
      roundRect(x, y - h, w, h, 10);
      ctx.fill();
      ctx.strokeStyle = `rgba(210, 220, 255, ${0.4 * a})`;
      ctx.lineWidth = 1;
      ctx.stroke();
      ctx.fillStyle = `rgba(245, 248, 255, ${0.97 * a})`;
      ctx.fillText(text, x + 7, y - 8);
    }

    function markInteraction() {
      lastInteractionAt = Date.now();
      autoSpin = false;
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
      if (!dragging && !autoSpin && (Date.now() - lastInteractionAt) > idleResumeMs) {
        autoSpin = true;
      }
      if (!dragging) {
        if (autoSpin) {
          velocityY = velocityY * 0.92 + baseAutoSpinY * 0.08;
          velocityX *= 0.95;
        } else {
          velocityY *= 0.965;
        }
        spinX += velocityX;
        spinY += velocityY;
        velocityX *= 0.985;
      }
      draw();
      requestAnimationFrame(tick);
    }
    
    canvas.addEventListener("mousedown", (e) => {
      markInteraction();
      dragging = true;
      lastX = e.clientX;
      lastY = e.clientY;
    });
    window.addEventListener("mouseup", () => { dragging = false; });
    window.addEventListener("mousemove", (e) => {
      if (dragging) {
        markInteraction();
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
      markInteraction();
      const t = e.touches[0];
      dragging = true;
      lastX = t.clientX;
      lastY = t.clientY;
    }, { passive: true });
    
    canvas.addEventListener("touchmove", (e) => {
      markInteraction();
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
      markInteraction();
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
      velocityY = 0.0;
      hoverNodeId = null;
      frontCaptionNodeIds.length = 0;
      selectedNodeId = null;
      autoSpin = true;
      lastInteractionAt = Date.now();
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

struct ConstellationD3WebView: UIViewRepresentable {
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
    let lastTapAt = { time: 0, id: null };
    let sparkTimer = null;
    
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
      if (sparkTimer) {
        sparkTimer.stop();
      }
      
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
      const nodeById = new Map(nodes.map((n) => [n.id, n]));
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
      
      const kindOf = (endpoint) => {
        if (typeof endpoint === "object") return endpoint.kind;
        return nodeById.get(endpoint)?.kind;
      };
      const themeLinks = links.filter((l) => kindOf(l.source) === "theme" || kindOf(l.target) === "theme");
      const sparkCount = Math.max(0, Math.min(16, Math.floor(themeLinks.length * 0.45)));
      const sparks = Array.from({ length: sparkCount }, (_, i) => ({
        id: i,
        linkIndex: i % Math.max(1, themeLinks.length),
        phase: (i * 0.6180339) % 1,
        speed: 0.14 + ((i * 7) % 5) * 0.018,
      }));
      const sparkLayer = stage.append("g")
        .style("pointer-events", "none")
        .selectAll("circle")
        .data(sparks)
        .join("circle")
        .attr("r", 0)
        .attr("fill", "#a5f3fc")
        .attr("opacity", 0);
      
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
        })
        .on("dblclick", (event, d) => {
          event.preventDefault();
          if (window.webkit?.messageHandlers?.nodeOpen) {
            window.webkit.messageHandlers.nodeOpen.postMessage(d.id);
          }
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
      
      function animateSparks(t) {
        sparkLayer
          .attr("cx", (s) => {
            const l = themeLinks[s.linkIndex];
            if (!l || !l.source || !l.target) return -100;
            const p = (t * s.speed + s.phase) % 1;
            return l.source.x + (l.target.x - l.source.x) * p;
          })
          .attr("cy", (s) => {
            const l = themeLinks[s.linkIndex];
            if (!l || !l.source || !l.target) return -100;
            const p = (t * s.speed + s.phase) % 1;
            return l.source.y + (l.target.y - l.source.y) * p;
          })
          .attr("r", (s) => {
            const flicker = (Math.sin(t * 2.1 + s.phase * 11) + 1) * 0.5;
            return flicker > 0.73 ? 1.7 : 0;
          })
          .attr("opacity", (s) => {
            const flicker = (Math.sin(t * 2.1 + s.phase * 11) + 1) * 0.5;
            return flicker > 0.73 ? 0.95 : 0;
          });
      }
      
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
      
      sparkTimer = d3.timer(() => {
        animateSparks(Date.now() / 1000);
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

struct D3GraphPayload: Codable {
    let nodes: [D3NodePayload]
    let links: [D3LinkPayload]
    let labelDensity: String
    
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
