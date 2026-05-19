import AppKit
import VTuberMeetCore

@MainActor
final class MainViewController: NSViewController {
    weak var windowController: MainWindowController?

    private let chatService = ChatService()
    private let ttsPlaybackCoordinator = LocalTTSPlaybackCoordinator()
    private let ttsUpstreamLauncher = LocalTTSUpstreamLauncher()
    private let avatarView = AvatarView()
    private let headerView = NSStackView()
    private let contentStack = NSStackView()
    private let sidePanel = NSStackView()
    private let transcriptScrollView = NSScrollView()
    private let transcriptDocumentView = NSView()
    private let transcriptStack = NSStackView()
    private let inputTextView = MessageTextView()
    private let sendButton = NSButton(title: "말 걸기", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")
    private let llmLabel = NSTextField(labelWithString: "대화 준비 확인 중")
    private let ttsLabel = NSTextField(labelWithString: "로컬 TTS 준비 확인 중")
    private let ttsRetryButton = NSButton(title: "TTS 시작/재연결", target: nil, action: nil)
    private let presetPopup = NSPopUpButton()
    private let alwaysOnTopButton = NSButton(checkboxWithTitle: "항상 위", target: nil, action: nil)
    private let companionModeButton = NSButton(checkboxWithTitle: "컴패니언 모드", target: nil, action: nil)
    private let exitCompanionButton = NSButton(title: "전체 모드", target: nil, action: nil)
    private var avatarPresets: [AvatarPreset] = []
    private var selectedPreset: AvatarPreset?
    private var sendTask: Task<Void, Never>?
    private var ttsBackendServer: LocalTTSBackendServer?
    private var ttsConfiguration: LocalTTSConfiguration?
    private var ttsPrepareTask: Task<Bool, Never>?
    private var llmStatusDot: NSView?
    private var ttsStatusDot: NSView?

    private var isBusy = false {
        didSet { updateBusyState() }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Design.parchment.cgColor
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startTTSBackend()
        loadAvatarPresets()
        refreshLocalModelStatus()
    }

    deinit {
        ttsBackendServer?.stop()
    }

    func setCompanionMode(_ enabled: Bool) {
        headerView.isHidden = enabled
        sidePanel.isHidden = enabled
        exitCompanionButton.isHidden = !enabled
        companionModeButton.state = enabled ? .on : .off
    }

    private func buildLayout() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        configureHeader()
        root.addArrangedSubview(headerView)

        contentStack.orientation = .horizontal
        contentStack.spacing = 14
        contentStack.alignment = .top
        contentStack.distribution = .fill
        root.addArrangedSubview(contentStack)

        let avatarPanel = PanelView()
        avatarPanel.translatesAutoresizingMaskIntoConstraints = false
        avatarPanel.addSubview(avatarView)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(avatarPanel)

        NSLayoutConstraint.activate([
            avatarPanel.widthAnchor.constraint(equalToConstant: 560),
            avatarPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 620),
            avatarView.leadingAnchor.constraint(equalTo: avatarPanel.leadingAnchor, constant: 8),
            avatarView.trailingAnchor.constraint(equalTo: avatarPanel.trailingAnchor, constant: -8),
            avatarView.topAnchor.constraint(equalTo: avatarPanel.topAnchor, constant: 8),
            avatarView.bottomAnchor.constraint(equalTo: avatarPanel.bottomAnchor, constant: -8)
        ])

        configureSidePanel()
        contentStack.addArrangedSubview(sidePanel)

        exitCompanionButton.target = self
        exitCompanionButton.action = #selector(disableCompanionMode)
        exitCompanionButton.bezelStyle = .rounded
        exitCompanionButton.isHidden = true
        root.addArrangedSubview(exitCompanionButton)
    }

    private func configureHeader() {
        headerView.orientation = .vertical
        headerView.spacing = 3

        let eyebrow = NSTextField(labelWithString: "VTuberMeet")
        eyebrow.font = Design.uiFont(size: 12, weight: .bold)
        eyebrow.textColor = Design.terracotta

        let title = NSTextField(wrappingLabelWithString: "내 VTuber 친구")
        title.font = Design.titleFont(size: 26)
        title.textColor = Design.nearBlack

        let subtitle = NSTextField(wrappingLabelWithString: "로컬 LLM과 로컬 TTS로 대화하는 개인용 VTuber companion")
        subtitle.font = Design.uiFont(size: 14)
        subtitle.textColor = Design.oliveGray

        headerView.addArrangedSubview(eyebrow)
        headerView.addArrangedSubview(title)
        headerView.addArrangedSubview(subtitle)
    }

    private func configureSidePanel() {
        sidePanel.orientation = .vertical
        sidePanel.spacing = 10
        sidePanel.alignment = .width
        sidePanel.translatesAutoresizingMaskIntoConstraints = false
        sidePanel.widthAnchor.constraint(equalToConstant: 400).isActive = true

        let controlsPanel = makeControlsPanel()
        let transcriptPanel = makeTranscriptPanel()
        let composerPanel = makeComposerPanel()

        sidePanel.addArrangedSubview(controlsPanel)
        sidePanel.addArrangedSubview(transcriptPanel)
        sidePanel.addArrangedSubview(composerPanel)

        NSLayoutConstraint.activate([
            controlsPanel.widthAnchor.constraint(equalTo: sidePanel.widthAnchor),
            transcriptPanel.widthAnchor.constraint(equalTo: sidePanel.widthAnchor),
            composerPanel.widthAnchor.constraint(equalTo: sidePanel.widthAnchor)
        ])
    }

    private func makeTranscriptPanel() -> NSView {
        let panel = PanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        let heading = NSTextField(labelWithString: "대화")
        heading.font = Design.titleFont(size: 16)
        heading.textColor = Design.charcoal
        stack.addArrangedSubview(heading)

        transcriptScrollView.hasVerticalScroller = true
        transcriptScrollView.drawsBackground = false
        transcriptScrollView.translatesAutoresizingMaskIntoConstraints = false

        transcriptDocumentView.translatesAutoresizingMaskIntoConstraints = false

        transcriptStack.orientation = .vertical
        transcriptStack.spacing = 12
        transcriptStack.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        transcriptStack.translatesAutoresizingMaskIntoConstraints = false
        transcriptDocumentView.addSubview(transcriptStack)
        transcriptScrollView.documentView = transcriptDocumentView
        stack.addArrangedSubview(transcriptScrollView)

        NSLayoutConstraint.activate([
            panel.heightAnchor.constraint(greaterThanOrEqualToConstant: 410),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -18),
            transcriptScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
            transcriptDocumentView.widthAnchor.constraint(equalTo: transcriptScrollView.contentView.widthAnchor),
            transcriptStack.leadingAnchor.constraint(equalTo: transcriptDocumentView.leadingAnchor),
            transcriptStack.trailingAnchor.constraint(equalTo: transcriptDocumentView.trailingAnchor),
            transcriptStack.topAnchor.constraint(equalTo: transcriptDocumentView.topAnchor),
            transcriptStack.bottomAnchor.constraint(equalTo: transcriptDocumentView.bottomAnchor),
            transcriptStack.widthAnchor.constraint(equalTo: transcriptDocumentView.widthAnchor)
        ])

        return panel
    }

    private func makeComposerPanel() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let topBorder = NSView()
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        topBorder.wantsLayer = true
        topBorder.layer?.backgroundColor = Design.border.withAlphaComponent(0.6).cgColor
        container.addSubview(topBorder)

        let inputContainer = NSView()
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.wantsLayer = true
        inputContainer.layer?.backgroundColor = Design.warmSand.cgColor
        inputContainer.layer?.cornerRadius = 18
        inputContainer.layer?.borderColor = Design.border.cgColor
        inputContainer.layer?.borderWidth = 1
        container.addSubview(inputContainer)

        let inputScroll = NSScrollView()
        inputScroll.hasVerticalScroller = true
        inputScroll.hasHorizontalScroller = false
        inputScroll.borderType = .noBorder
        inputScroll.drawsBackground = false
        inputTextView.minSize = NSSize(width: 0, height: 40)
        inputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.font = Design.uiFont(size: 15)
        inputTextView.textColor = Design.nearBlack
        inputTextView.backgroundColor = .clear
        inputTextView.string = ""
        inputTextView.isRichText = false
        inputTextView.isHorizontallyResizable = false
        inputTextView.isVerticallyResizable = true
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.textContainer?.containerSize = NSSize(width: inputScroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.autoresizingMask = [.width]
        inputTextView.onSubmit = { [weak self] in
            self?.sendMessage()
        }
        inputScroll.documentView = inputTextView
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(inputScroll)

        sendButton.target = self
        sendButton.action = #selector(sendMessage)
        sendButton.bezelStyle = .regularSquare
        sendButton.wantsLayer = true
        sendButton.layer?.backgroundColor = Design.brand.cgColor
        sendButton.layer?.cornerRadius = 16
        sendButton.contentTintColor = .white
        sendButton.font = Design.uiFont(size: 14, weight: .semibold)
        sendButton.isBordered = false
        sendButton.toolTip = "Enter로도 전송할 수 있어요"
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sendButton)

        errorLabel.font = Design.uiFont(size: 12)
        errorLabel.textColor = Design.error
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            topBorder.topAnchor.constraint(equalTo: container.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),
            inputContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            inputContainer.topAnchor.constraint(equalTo: topBorder.bottomAnchor, constant: 12),
            inputContainer.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -8),
            sendButton.leadingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: 10),
            sendButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            sendButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 52),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
            inputScroll.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            inputScroll.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),
            inputScroll.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 8),
            inputScroll.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),
            inputScroll.heightAnchor.constraint(equalToConstant: 40),
            errorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            errorLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            errorLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }

    private func makeControlsPanel() -> NSView {
        let panel = PanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        let heading = NSTextField(labelWithString: "설정")
        heading.font = Design.titleFont(size: 18)
        heading.textColor = Design.nearBlack

        let description = NSTextField(wrappingLabelWithString: "캐릭터, 창 모드, 로컬 AI/TTS 상태를 한곳에서 확인합니다.")
        description.font = Design.uiFont(size: 12)
        description.textColor = Design.stone

        let characterSection = makeSectionHeader("캐릭터")
        presetPopup.target = self
        presetPopup.action = #selector(selectAvatarPreset)
        presetPopup.bezelStyle = .rounded

        let windowSection = makeSectionHeader("창 모드")
        alwaysOnTopButton.target = self
        alwaysOnTopButton.action = #selector(toggleAlwaysOnTop)
        companionModeButton.target = self
        companionModeButton.action = #selector(toggleCompanionMode)

        let servicesSection = makeSectionHeader("서비스 상태")

        llmLabel.font = Design.uiFont(size: 12)
        llmLabel.textColor = Design.oliveGray

        ttsLabel.font = Design.uiFont(size: 12)
        ttsLabel.textColor = Design.oliveGray

        let ttsHint = NSTextField(wrappingLabelWithString: "음성 서버는 앱이 로컬에서 자동으로 확인하고, 꺼져 있으면 127.0.0.1에만 시작합니다.")
        ttsHint.font = Design.uiFont(size: 11)
        ttsHint.textColor = Design.stone

        ttsRetryButton.target = self
        ttsRetryButton.action = #selector(reconnectLocalTTS)
        ttsRetryButton.bezelStyle = .rounded
        ttsRetryButton.toolTip = "로컬 TTS 서버를 확인하고 꺼져 있으면 로컬에서 시작합니다"

        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(description)
        stack.addArrangedSubview(characterSection)
        stack.addArrangedSubview(presetPopup)
        stack.addArrangedSubview(windowSection)
        stack.addArrangedSubview(alwaysOnTopButton)
        stack.addArrangedSubview(companionModeButton)
        stack.addArrangedSubview(servicesSection)
        let llmRow = makeStatusRow(label: llmLabel, dotColor: statusDotColor(for: llmLabel.stringValue))
        llmStatusDot = llmRow.arrangedSubviews.first
        stack.addArrangedSubview(llmRow)
        let ttsRow = makeStatusRow(label: ttsLabel, dotColor: statusDotColor(for: ttsLabel.stringValue))
        ttsStatusDot = ttsRow.arrangedSubviews.first
        stack.addArrangedSubview(ttsRow)
        stack.addArrangedSubview(ttsHint)
        stack.addArrangedSubview(ttsRetryButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -18),
            presetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 260)
        ])

        return panel
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = Design.uiFont(size: 11, weight: .bold)
        label.textColor = Design.stone
        return label
    }

    private func makeStatusRow(label: NSTextField, dotColor: NSColor) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY

        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = dotColor.cgColor
        dot.layer?.cornerRadius = 4
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8)
        ])

        row.addArrangedSubview(dot)
        row.addArrangedSubview(label)
        return row
    }

    private func statusDotColor(for status: String) -> NSColor {
        if status.contains("준비됨") || status.contains("연결됨") {
            return NSColor(hex: 0x4ADE80)
        } else if status.contains("오류") || status.contains("필요") {
            return Design.error
        } else {
            return NSColor(hex: 0xFBBF24)
        }
    }

    private func updateLLMStatus(_ text: String) {
        llmLabel.stringValue = text
        llmStatusDot?.layer?.backgroundColor = statusDotColor(for: text).cgColor
    }

    private func updateTTSStatus(_ text: String) {
        ttsLabel.stringValue = text
        ttsStatusDot?.layer?.backgroundColor = statusDotColor(for: text).cgColor
    }

    private func loadAvatarPresets() {
        do {
            avatarPresets = try AvatarResourceLoader.loadPresets()
            presetPopup.removeAllItems()
            presetPopup.addItems(withTitles: avatarPresets.map(\.name))

            guard let first = avatarPresets.first else { return }
            selectedPreset = first
            avatarView.selectPreset(first)
            appendMessage(role: "System", text: "캐릭터 ‘\(first.name)’를 불러왔어요.", emphasized: true)
            appendMessage(role: first.name, text: "안녕, 나는 \(first.name)이에요. 여기서 같이 이야기하고 싶어서 기다리고 있었어요.", emphasized: false)
        } catch {
            appendMessage(role: "System", text: "프리셋 정보를 읽지 못했습니다: \(error.localizedDescription)", emphasized: true)
        }
    }

    @objc private func selectAvatarPreset() {
        let index = presetPopup.indexOfSelectedItem
        guard avatarPresets.indices.contains(index) else { return }

        let preset = avatarPresets[index]
        selectedPreset = preset
        avatarView.selectPreset(preset)
        appendMessage(role: "System", text: "캐릭터를 ‘\(preset.name)’로 바꿨습니다.", emphasized: true)
    }

    @objc private func sendMessage() {
        do {
            errorLabel.stringValue = ""
            let text = try ChatService.validate(inputTextView.string)
            let characterName = selectedPreset?.name ?? "Live2D"

            isBusy = true
            appendMessage(role: "You", text: text.trimmingCharacters(in: .whitespacesAndNewlines), emphasized: false)
            inputTextView.string = ""

            sendTask?.cancel()
            sendTask = Task { [weak self] in
                await self?.sendMessageToLocalLLM(text: text, characterName: characterName)
            }
        } catch {
            errorLabel.stringValue = error.localizedDescription
            avatarView.mood = .curious
            isBusy = false
        }
    }

    private func sendMessageToLocalLLM(text: String, characterName: String) async {
        do {
            let response = try await chatService.respond(to: text, characterName: characterName)
            guard !Task.isCancelled else { return }
            updateLLMStatus("대화 준비됨")
            appendMessage(role: selectedPreset?.name ?? characterName, text: response.text, emphasized: false)
            avatarView.affect = response.affect
            await speakWithLocalTTS(response.text)
            isBusy = false
        } catch {
            guard !Task.isCancelled else { return }
            errorLabel.stringValue = error.localizedDescription
            avatarView.mood = .curious
            isBusy = false
        }
    }

    private func startTTSBackend() {
        do {
            let configuration = try LocalTTSConfiguration.load()
            let service = LocalTTSService(configuration: configuration)
            let server = LocalTTSBackendServer(service: service)
            try server.start()
            ttsConfiguration = configuration
            ttsBackendServer = server
            updateTTSStatus("앱 음성 proxy 준비됨 · upstream 확인 중")
            Task { [weak self] in
                await self?.prepareLocalTTSUpstream(allowStart: true)
            }
        } catch {
            updateTTSStatus("로컬 TTS 설정 오류: \(error.localizedDescription)")
        }
    }

    @objc private func reconnectLocalTTS() {
        Task { [weak self] in
            await self?.prepareLocalTTSUpstream(allowStart: true)
        }
    }

    @discardableResult
    private func prepareLocalTTSUpstream(allowStart: Bool) async -> Bool {
        if let ttsPrepareTask {
            return await ttsPrepareTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.runLocalTTSPreparation(allowStart: allowStart)
        }
        ttsPrepareTask = task
        let result = await task.value
        ttsPrepareTask = nil
        return result
    }

    private func runLocalTTSPreparation(allowStart: Bool) async -> Bool {
        guard let configuration = ttsConfiguration else {
            updateTTSStatus("로컬 TTS 설정을 먼저 확인해야 합니다.")
            return false
        }

        ttsRetryButton.isEnabled = false
        updateTTSStatus(allowStart ? "로컬 TTS 서버 확인/시작 중" : "로컬 TTS 서버 확인 중")
        defer { ttsRetryButton.isEnabled = true }

        if !allowStart {
            let reachable = await ttsUpstreamLauncher.isReachable(configuration.apiURL)
            updateTTSStatus(reachable ? "로컬 TTS 연결됨" : "로컬 TTS 서버가 꺼져 있습니다")
            return reachable
        }

        do {
            let scriptURL = try AvatarResourceLoader.resourceURL(path: "start_local_tts_api.sh")
            let status = await ttsUpstreamLauncher.startIfNeeded(apiURL: configuration.apiURL, scriptURL: scriptURL)
            updateTTSStatus("\(status.userMessage) · \(configuration.apiURL.host ?? "localhost"):\(configuration.apiURL.port ?? 9888)")
            return status.isUsable
        } catch {
            updateTTSStatus("로컬 TTS 시작 스크립트를 찾지 못했습니다: \(error.localizedDescription)")
            return false
        }
    }

    private func speakWithLocalTTS(_ text: String) async {
        guard let endpointURL = ttsBackendServer?.url(path: "/api/tts") else {
            updateTTSStatus("로컬 TTS 비활성화: 로컬 backend를 시작하지 못했습니다.")
            return
        }

        guard await prepareLocalTTSUpstream(allowStart: true) else {
            avatarView.speaking = false
            avatarView.mouthOpen = 0
            avatarView.mood = .curious
            return
        }

        do {
            try await ttsPlaybackCoordinator.speak(
                text: text,
                endpointURL: endpointURL,
                onMouthOpen: { [weak self] mouthOpen in
                    self?.avatarView.mouthOpen = mouthOpen
                },
                onSpeaking: { [weak self] speaking in
                    self?.avatarView.speaking = speaking
                    if !speaking {
                        self?.updateTTSStatus("로컬 TTS 준비됨")
                    }
                }
            )
            updateTTSStatus("로컬 TTS 재생 중")
        } catch {
            avatarView.speaking = false
            avatarView.mouthOpen = 0
            updateTTSStatus("로컬 TTS 오류: \(error.localizedDescription) · TTS 시작/재연결을 눌러 주세요")
        }
    }

    private func refreshLocalModelStatus() {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await chatService.availableLocalModel()
                updateLLMStatus("대화 준비됨")
            } catch {
                updateLLMStatus("대화 설정 필요")
            }
        }
    }

    @objc private func toggleAlwaysOnTop() {
        windowController?.setAlwaysOnTop(alwaysOnTopButton.state == .on)
    }

    @objc private func toggleCompanionMode() {
        windowController?.setCompanionMode(companionModeButton.state == .on)
    }

    @objc private func disableCompanionMode() {
        companionModeButton.state = .off
        windowController?.setCompanionMode(false)
    }

    private var lastMessageKind: MessageKind = .system
    private var lastMessageTime = Date()

    private func appendMessage(role: String, text: String, emphasized: Bool) {
        let kind = messageKind(role: role, emphasized: emphasized)
        let now = Date()
        let showTime = now.timeIntervalSince(lastMessageTime) > 60 || kind != lastMessageKind
        lastMessageTime = now
        lastMessageKind = kind

        avatarView.showChatMessage(role: displayRole(role, kind: kind), text: text)

        let groupStack = NSStackView()
        groupStack.orientation = .vertical
        groupStack.spacing = 2
        groupStack.translatesAutoresizingMaskIntoConstraints = false

        if kind == .incoming {
            let nameLabel = NSTextField(labelWithString: role)
            nameLabel.font = Design.uiFont(size: 11, weight: .medium)
            nameLabel.textColor = Design.oliveGray
            groupStack.addArrangedSubview(nameLabel)
        }

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .bottom
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let bubble = PanelView()
        bubble.fillColor = bubbleFillColor(for: kind)
        bubble.strokeColor = kind == .outgoing ? NSColor(hex: 0xFEE500) : Design.border
        bubble.layer?.cornerRadius = kind == .system ? 10 : 14
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.shadow = bubbleShadow(for: kind)

        let body = NSTextField(wrappingLabelWithString: text)
        body.font = Design.uiFont(size: 14)
        body.textColor = bodyTextColor(for: kind)
        body.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(body)

        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: kind == .system ? 10 : 14),
            body.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: kind == .system ? -10 : -14),
            body.topAnchor.constraint(equalTo: bubble.topAnchor, constant: kind == .system ? 6 : 10),
            body.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: kind == .system ? -6 : -10),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])

        let timeLabel = NSTextField(labelWithString: timeString(now))
        timeLabel.font = Design.uiFont(size: 10)
        timeLabel.textColor = Design.stone.withAlphaComponent(0.8)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        if kind == .outgoing {
            row.addArrangedSubview(NSView())
            row.addArrangedSubview(timeLabel)
            row.addArrangedSubview(bubble)
        } else if kind == .system {
            row.addArrangedSubview(NSView())
            row.addArrangedSubview(bubble)
            row.addArrangedSubview(NSView())
        } else {
            row.addArrangedSubview(bubble)
            row.addArrangedSubview(timeLabel)
            row.addArrangedSubview(NSView())
        }

        groupStack.addArrangedSubview(row)

        if showTime {
            let timeRow = NSStackView()
            timeRow.orientation = .horizontal
            timeRow.alignment = .centerY
            let timeCenter = NSTextField(labelWithString: timeString(now))
            timeCenter.font = Design.uiFont(size: 10)
            timeCenter.textColor = Design.stone.withAlphaComponent(0.6)
            timeRow.addArrangedSubview(NSView())
            timeRow.addArrangedSubview(timeCenter)
            timeRow.addArrangedSubview(NSView())
            transcriptStack.addArrangedSubview(timeRow)
            timeRow.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
        }

        transcriptStack.addArrangedSubview(groupStack)
        groupStack.widthAnchor.constraint(equalTo: transcriptStack.widthAnchor).isActive = true
        transcriptStack.layoutSubtreeIfNeeded()
        scrollTranscriptToBottom()
    }

    private enum MessageKind {
        case incoming
        case outgoing
        case system
    }

    private func messageKind(role: String, emphasized: Bool) -> MessageKind {
        if emphasized || role == "System" { return .system }
        return role == "You" ? .outgoing : .incoming
    }

    private func displayRole(_ role: String, kind: MessageKind) -> String {
        switch kind {
        case .incoming: role
        case .outgoing: "나"
        case .system: "안내"
        }
    }

    private func bubbleFillColor(for kind: MessageKind) -> NSColor {
        switch kind {
        case .incoming: Design.ivory
        case .outgoing: NSColor(hex: 0xFEE500)
        case .system: Design.warmSand
        }
    }

    private func roleTextColor(for kind: MessageKind) -> NSColor {
        switch kind {
        case .incoming, .system: Design.oliveGray
        case .outgoing: NSColor(hex: 0x2B2400)
        }
    }

    private func bodyTextColor(for kind: MessageKind) -> NSColor {
        switch kind {
        case .incoming, .system: Design.nearBlack
        case .outgoing: NSColor(hex: 0x1E1B00)
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "a h:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }

    private func bubbleShadow(for kind: MessageKind) -> NSShadow? {
        guard kind != .system else { return nil }
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.shadowBlurRadius = 4
        return shadow
    }

    private func scrollTranscriptToBottom() {
        transcriptDocumentView.layoutSubtreeIfNeeded()
        let visibleHeight = transcriptScrollView.contentView.bounds.height
        let documentHeight = transcriptDocumentView.bounds.height
        let y = max(0, documentHeight - visibleHeight)
        transcriptScrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        transcriptScrollView.reflectScrolledClipView(transcriptScrollView.contentView)
    }

    private func updateBusyState() {
        sendButton.isEnabled = !isBusy
        inputTextView.isEditable = !isBusy
        sendButton.title = isBusy ? "응답 중" : "말 걸기"
    }
}
