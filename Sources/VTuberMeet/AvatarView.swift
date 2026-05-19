import AppKit
@preconcurrency import WebKit
import VTuberMeetCore

@MainActor
final class AvatarView: NSView, WKScriptMessageHandler {
    var affect: CompanionAffect = .neutral { didSet { sendStateToViewer(); updateCaption() } }
    var mood: CompanionMood {
        get { affect.mood }
        set { affect = AffectEngine.make(mood: newValue, source: .fallback) }
    }
    var motion: CompanionMotion {
        get { affect.motion }
        set {
            affect = CompanionAffect(
                mood: affect.mood,
                expression: affect.expression,
                motion: newValue,
                intensity: affect.intensity,
                duration: affect.duration,
                confidence: affect.confidence,
                source: affect.source
            )
        }
    }
    var mouthOpen: Double = 0 { didSet { sendStateToViewer() } }
    var speaking = false { didSet { sendStateToViewer(); updateCaption() } }

    private let webView: WKWebView
    private let captionLabel = NSTextField(labelWithString: "Live2D 모델을 불러오는 중")
    private let chatOverlay = ChatOverlayView()
    private var resourceServer: LocalResourceServer?
    private var viewerLoaded = false
    private var lastSentState = ""
    private var selectedPresetName = "Live2D"
    private var overlayDismissTask: Task<Void, Never>?
    private var recentMessages: [(role: String, text: String)] = []
    private var expressionProfile = AvatarExpressionProfiles.fallback(for: "unknown")

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.suppressesIncrementalRendering = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)
        webView.configuration.userContentController.add(self, name: "live2dStatus")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    private func buildView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        captionLabel.font = Design.uiFont(size: 13, weight: .semibold)
        captionLabel.textColor = Design.nearBlack
        captionLabel.wantsLayer = true
        captionLabel.layer?.backgroundColor = Design.warmSand.withAlphaComponent(0.94).cgColor
        captionLabel.layer?.borderColor = Design.border.cgColor
        captionLabel.layer?.borderWidth = 1
        captionLabel.layer?.cornerRadius = 10
        captionLabel.alignment = .center
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captionLabel)

        chatOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chatOverlay)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            captionLabel.bottomAnchor.constraint(equalTo: chatOverlay.topAnchor, constant: -8),
            captionLabel.heightAnchor.constraint(equalToConstant: 30),
            captionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 170),
            chatOverlay.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            chatOverlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            chatOverlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -56)
        ])
    }

    func selectPreset(_ preset: AvatarPreset) {
        do {
            selectedPresetName = preset.name
            expressionProfile = AvatarExpressionProfiles.profile(for: preset.id) ?? AvatarExpressionProfiles.fallback(for: preset.id)
            viewerLoaded = false; lastSentState = ""; updateCaption()
            let server = try ensureResourceServer()
            let modelPath = "/\(preset.modelDirectory)/\(preset.modelFile)"
            var components = URLComponents(url: server.url(path: "/Live2DViewer/index.html"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "model", value: modelPath),
                URLQueryItem(name: "name", value: preset.name)
            ]
            guard let viewerURL = components?.url else { throw CocoaError(.fileNoSuchFile) }
            webView.load(URLRequest(url: viewerURL))
        } catch {
            captionLabel.stringValue = "Live2D 리소스 경로 오류"
            captionLabel.textColor = Design.error
        }
    }

    private func ensureResourceServer() throws -> LocalResourceServer {
        if let resourceServer { return resourceServer }
        let rootURL = try AvatarResourceLoader.resourceRootURL()
        let server = LocalResourceServer(rootURL: rootURL)
        try server.start()
        resourceServer = server
        return server
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor [weak self] in self?.handleViewerMessage(message.body) }
    }

    private func handleViewerMessage(_ body: Any) {
        guard let payload = body as? [String: Any], let type = payload["type"] as? String else { return }
        if type == "loaded" {
            viewerLoaded = true
            if let name = payload["name"] as? String, !name.isEmpty { selectedPresetName = name }
            captionLabel.textColor = Design.charcoal; updateCaption(); sendStateToViewer()
        } else if type == "error" {
            viewerLoaded = false
            captionLabel.stringValue = "Live2D: \(payload["message"] as? String ?? "error")"
            captionLabel.textColor = Design.error
        }
    }

    private func updateCaption() {
        let prefix = viewerLoaded ? "\(selectedPresetName) · " : ""
        if speaking { captionLabel.stringValue = "\(prefix)말하는 중" }
        else if affect.mood == .angry { captionLabel.stringValue = "\(prefix)살짝 화남" }
        else if affect.mood == .happy { captionLabel.stringValue = "\(prefix)기분 좋음" }
        else if affect.mood == .curious { captionLabel.stringValue = "\(prefix)생각하는 중" }
        else if affect.mood == .sad { captionLabel.stringValue = "\(prefix)차분히 공감 중" }
        else if affect.mood == .surprised { captionLabel.stringValue = "\(prefix)깜짝 놀람" }
        else if affect.mood == .embarrassed { captionLabel.stringValue = "\(prefix)살짝 부끄러움" }
        else { captionLabel.stringValue = viewerLoaded ? "\(selectedPresetName) · 함께 있는 중" : "\(selectedPresetName) 불러오는 중" }
    }

    private func sendStateToViewer() {
        guard viewerLoaded else { return }
        let expressionMap = Dictionary(
            uniqueKeysWithValues: expressionProfile.namedExpressions.map { key, value in
                (key.rawValue, value)
            }
        )
        let profilePayload: [String: Any] = [
            "presetID": expressionProfile.presetID,
            "supportsNamedExpressions": expressionProfile.supportsNamedExpressions,
            "expressionMap": expressionMap,
            "lipSyncParameters": expressionProfile.lipSyncParameters
        ]
        let payload: [String: Any] = [
            "mood": affect.mood.rawValue,
            "expression": affect.expression.rawValue,
            "motion": affect.motion.rawValue,
            "intensity": affect.intensity,
            "duration": affect.duration,
            "confidence": affect.confidence,
            "source": affect.source.rawValue,
            "mouthOpen": max(0, min(1, mouthOpen)),
            "speaking": speaking,
            "profile": profilePayload
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.setCompanionState && window.setCompanionState(\(json));"
        guard script != lastSentState else { return }
        lastSentState = script
        webView.evaluateJavaScript(script)
    }

    func showChatMessage(role: String, text: String) {
        recentMessages.append((role: role, text: text))
        if recentMessages.count > 2 { recentMessages.removeFirst() }
        chatOverlay.updateMessages(recentMessages)
        chatOverlay.alphaValue = 1.0

        overlayDismissTask?.cancel()
        overlayDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    self?.chatOverlay.animator().alphaValue = 0.35
                }
            }
        }
    }

    func clearChatOverlay() {
        overlayDismissTask?.cancel()
        recentMessages.removeAll()
        chatOverlay.updateMessages([])
    }
}

@MainActor
final class ChatOverlayView: NSView {
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func buildView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 12
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 0.5

        stackView.orientation = .vertical
        stackView.spacing = 6
        stackView.alignment = .leading
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    func updateMessages(_ messages: [(role: String, text: String)]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for message in messages {
            let label = NSTextField(wrappingLabelWithString: "\(message.role): \(message.text)")
            label.font = Design.uiFont(size: 13, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.92)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stackView.addArrangedSubview(label)
        }
    }
}
