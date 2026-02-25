import Cocoa
import WebKit

final class MainWindowController: NSWindowController {
    private enum UI {
        static let toolbarHeight: CGFloat = 74
        static let tabChipSize = NSSize(width: 96, height: 48)
    }

    private let rootContainer = NSView()
    private let toolbarContainer = LiquidGlassToolbarView()
    private let webContainer = NSView()

    private let tabStripContainer = NSView()
    private let tabStripScrollView = NSScrollView()
    private let tabStripDocumentView = NSView()
    private let tabStripStackView = NSStackView()
    private let newTabButton = NSButton(title: "+", target: nil, action: nil)
    private let rightPanelView = NSView()
    private let addressDisplayView = AddressDisplayView()
    private let addressEditorField = NSTextField()
    private let tabSearchField = NSSearchField()

    private var tabStripMinLeadingConstraint: NSLayoutConstraint?
    private var tabStripWidthConstraint: NSLayoutConstraint?
    private var rightPanelWidthConstraint: NSLayoutConstraint?
    private var tabStripHeightConstraint: NSLayoutConstraint?

    private let tabManager: TabManager
    private let session: BrowserSession
    private let actions: ActionCenter

    private var overlayView: GestureOverlayView?
    private var isAddressEditing = false
    private var tabSearchQuery = ""
    private var currentAddressURLString = ""
    private var interactiveTabSwitchState: InteractiveTabSwitchState?

    private struct InteractiveTabSwitchState {
        let fromWebView: WKWebView
        let toWebView: WKWebView
        let targetIndex: Int
        let direction: ActionCenter.GestureTabSwitchDirection
    }

    init() {
        tabManager = TabManager()
        session = BrowserSession(tabManager: tabManager)
        actions = ActionCenter(tabManager: tabManager, session: session)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Vidarr"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        configureWindow()
        configureBindings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        ensureInitialTabVisible()
        DispatchQueue.main.async { [weak self] in
            self?.syncToolbarLayout()
        }
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }

        rootContainer.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.wantsLayer = true
        webContainer.layer?.backgroundColor = NSColor.white.cgColor

        contentView.addSubview(rootContainer)
        rootContainer.addSubview(toolbarContainer)
        rootContainer.addSubview(webContainer)

        setupToolbarUI()

        NSLayoutConstraint.activate([
            rootContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            toolbarContainer.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            toolbarContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: UI.toolbarHeight),

            webContainer.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor)
        ])
    }

    private func setupToolbarUI() {
        tabStripContainer.translatesAutoresizingMaskIntoConstraints = false
        tabStripContainer.wantsLayer = true
        tabStripContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        tabStripContainer.layer?.cornerRadius = 6
        tabStripContainer.layer?.masksToBounds = true

        tabStripScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabStripScrollView.drawsBackground = false
        tabStripScrollView.hasVerticalScroller = false
        tabStripScrollView.hasHorizontalScroller = false
        tabStripScrollView.autohidesScrollers = true
        tabStripScrollView.borderType = .noBorder
        tabStripScrollView.scrollerStyle = .overlay
        tabStripScrollView.verticalScrollElasticity = .none
        tabStripScrollView.horizontalScrollElasticity = .automatic
        tabStripScrollView.contentView = HorizontalOnlyClipView()
        tabStripContainer.addSubview(tabStripScrollView)

        tabStripDocumentView.translatesAutoresizingMaskIntoConstraints = true
        tabStripDocumentView.wantsLayer = true
        tabStripDocumentView.layer?.backgroundColor = NSColor.clear.cgColor
        tabStripScrollView.documentView = tabStripDocumentView

        tabStripStackView.translatesAutoresizingMaskIntoConstraints = true
        tabStripStackView.orientation = .horizontal
        tabStripStackView.alignment = .centerY
        tabStripStackView.spacing = 6
        tabStripDocumentView.addSubview(tabStripStackView)

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.target = self
        newTabButton.action = #selector(didTapNewTab)
        newTabButton.isBordered = false
        newTabButton.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        newTabButton.contentTintColor = NSColor(calibratedWhite: 0.22, alpha: 0.92)

        rightPanelView.translatesAutoresizingMaskIntoConstraints = false

        addressDisplayView.translatesAutoresizingMaskIntoConstraints = false
        addressDisplayView.onClick = { [weak self] in
            self?.beginAddressEditing()
        }

        addressEditorField.translatesAutoresizingMaskIntoConstraints = false
        addressEditorField.delegate = self
        addressEditorField.font = NSFont.systemFont(ofSize: 12.0)
        addressEditorField.focusRingType = .none
        addressEditorField.bezelStyle = .roundedBezel
        addressEditorField.isHidden = true

        tabSearchField.translatesAutoresizingMaskIntoConstraints = false
        tabSearchField.font = NSFont.systemFont(ofSize: 12.0)
        tabSearchField.placeholderString = "タブを検索"
        tabSearchField.sendsSearchStringImmediately = true
        tabSearchField.sendsWholeSearchString = false
        tabSearchField.target = self
        tabSearchField.action = #selector(tabSearchDidChange(_:))

        let toolbarContent = toolbarContainer.contentLayoutView
        toolbarContent.addSubview(tabStripContainer)
        toolbarContent.addSubview(newTabButton)
        toolbarContent.addSubview(rightPanelView)
        rightPanelView.addSubview(addressDisplayView)
        rightPanelView.addSubview(addressEditorField)
        rightPanelView.addSubview(tabSearchField)

        let minLeading = tabStripContainer.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarContent.leadingAnchor, constant: 84)
        tabStripMinLeadingConstraint = minLeading
        let tabWidth = tabStripContainer.widthAnchor.constraint(equalToConstant: 520)
        tabStripWidthConstraint = tabWidth
        let tabHeight = tabStripContainer.heightAnchor.constraint(equalToConstant: UI.tabChipSize.height + 4)
        tabStripHeightConstraint = tabHeight
        let rightPanelWidth = rightPanelView.widthAnchor.constraint(equalToConstant: 250)
        rightPanelWidthConstraint = rightPanelWidth

        NSLayoutConstraint.activate([
            minLeading,
            tabWidth,
            tabHeight,
            tabStripContainer.centerXAnchor.constraint(equalTo: toolbarContent.centerXAnchor),
            tabStripContainer.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 8),
            tabStripContainer.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -6),

            tabStripScrollView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabStripScrollView.leadingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor),
            tabStripScrollView.trailingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor),
            tabStripScrollView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),

            newTabButton.centerYAnchor.constraint(equalTo: tabStripContainer.centerYAnchor),
            newTabButton.trailingAnchor.constraint(equalTo: rightPanelView.leadingAnchor, constant: -8),
            newTabButton.widthAnchor.constraint(equalToConstant: 24),
            newTabButton.heightAnchor.constraint(equalToConstant: 24),

            rightPanelView.trailingAnchor.constraint(equalTo: toolbarContent.trailingAnchor, constant: -10),
            rightPanelView.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 7),
            rightPanelView.bottomAnchor.constraint(equalTo: toolbarContent.bottomAnchor, constant: -7),
            rightPanelWidth,

            addressDisplayView.topAnchor.constraint(equalTo: rightPanelView.topAnchor),
            addressDisplayView.leadingAnchor.constraint(equalTo: rightPanelView.leadingAnchor),
            addressDisplayView.trailingAnchor.constraint(equalTo: rightPanelView.trailingAnchor),
            addressDisplayView.heightAnchor.constraint(equalToConstant: 16),

            addressEditorField.centerYAnchor.constraint(equalTo: addressDisplayView.centerYAnchor),
            addressEditorField.leadingAnchor.constraint(equalTo: addressDisplayView.leadingAnchor),
            addressEditorField.trailingAnchor.constraint(equalTo: addressDisplayView.trailingAnchor),
            addressEditorField.heightAnchor.constraint(equalToConstant: 20),

            tabSearchField.leadingAnchor.constraint(equalTo: rightPanelView.leadingAnchor),
            tabSearchField.trailingAnchor.constraint(equalTo: rightPanelView.trailingAnchor),
            tabSearchField.bottomAnchor.constraint(equalTo: rightPanelView.bottomAnchor),
            tabSearchField.heightAnchor.constraint(equalToConstant: 22),
            tabSearchField.topAnchor.constraint(greaterThanOrEqualTo: addressDisplayView.bottomAnchor, constant: 5)
        ])

        applyAddressDisplayMode(display: "")
    }

    private func configureBindings() {
        tabManager.delegate = self
        actions.focusAddressField = { [weak self] in
            self?.beginAddressEditing()
        }
        actions.confirmCloseProtectedTab = { [weak self] in
            self?.confirmCloseProtectedTab() ?? false
        }
        actions.performGestureTabSwitch = { [weak self] direction in
            self?.performGestureTabSwitch(direction: direction)
        }
        actions.beginInteractiveGestureTabSwitch = { [weak self] direction in
            self?.beginInteractiveTabSwitch(direction: direction) ?? false
        }
        actions.updateInteractiveGestureTabSwitch = { [weak self] totalX in
            self?.updateInteractiveTabSwitch(totalX: totalX)
        }
        actions.finishInteractiveGestureTabSwitch = { [weak self] totalX in
            self?.finishInteractiveTabSwitch(totalX: totalX)
        }
    }

    private func ensureInitialTabVisible() {
        if let current = tabManager.currentWebView {
            if current.superview == nil {
                attachWebView(current)
            }
            if current.url == nil {
                current.load(URLRequest(url: BrowserSession.defaultHomeURL))
            }
            return
        }

        actions.newTab()
    }

    @objc private func didTapNewTab() {
        actions.newTab()
    }

    @objc private func tabSearchDidChange(_ sender: NSSearchField) {
        tabSearchQuery = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildTabStrip()
    }

    private func beginAddressEditing() {
        guard !isAddressEditing else { return }
        isAddressEditing = true

        addressDisplayView.isHidden = true
        addressEditorField.isHidden = false
        addressEditorField.stringValue = currentAddressURLString

        window?.makeFirstResponder(addressEditorField)
        addressEditorField.selectText(nil)
    }

    private func endAddressEditingWithoutSubmit() {
        guard isAddressEditing else { return }
        isAddressEditing = false
        let display = tabManager.currentWebView?.url?.absoluteString ?? ""
        applyAddressDisplayMode(display: display)
        window?.makeFirstResponder(nil)
    }

    private func submitAddressFieldIfNeeded() {
        let input = addressEditorField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            actions.openLocationInput(input)
        }
        isAddressEditing = false
        applyAddressDisplayMode(display: input)
        window?.makeFirstResponder(nil)
    }

    private func applyAddressDisplayMode(display: String) {
        currentAddressURLString = display
        addressDisplayView.update(text: display)

        addressEditorField.stringValue = display
        addressEditorField.isHidden = true
        addressDisplayView.isHidden = false
    }

    private func attachWebView(_ webView: WKWebView) {
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        overlayView = nil

        webView.navigationDelegate = self
        clearLayoutConstraints(for: webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)
        ])

        let overlay = GestureOverlayView(frame: .zero)
        overlay.actionCenter = actions
        overlay.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: webContainer.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)
        ])

        overlayView = overlay
        applyAddressDisplayMode(display: webView.url?.absoluteString ?? "")
        rebuildTabStrip()
    }

    private func performGestureTabSwitch(direction: ActionCenter.GestureTabSwitchDirection) {
        guard interactiveTabSwitchState == nil else { return }
        switch direction {
        case .left:
            tabManager.selectNextTab()
        case .right:
            tabManager.selectPrevTab()
        }
    }

    private func beginInteractiveTabSwitch(direction: ActionCenter.GestureTabSwitchDirection) -> Bool {
        guard interactiveTabSwitchState == nil else { return true }

        let count = tabManager.tabCount
        guard count > 1 else { return false }

        let currentIndex = tabManager.currentIndex
        guard currentIndex >= 0, currentIndex < count else { return false }
        guard let fromWebView = tabManager.currentWebView else { return false }

        let targetIndex: Int
        switch direction {
        case .left:
            targetIndex = (currentIndex + 1 + count) % count
        case .right:
            targetIndex = (currentIndex - 1 + count) % count
        }
        guard targetIndex != currentIndex else { return false }
        guard let toWebView = tabManager.webView(at: targetIndex) else { return false }

        prepareInteractiveTabSwitchViews(from: fromWebView, to: toWebView, direction: direction)
        interactiveTabSwitchState = InteractiveTabSwitchState(
            fromWebView: fromWebView,
            toWebView: toWebView,
            targetIndex: targetIndex,
            direction: direction
        )
        return true
    }

    private func prepareInteractiveTabSwitchViews(
        from fromWebView: WKWebView,
        to toWebView: WKWebView,
        direction: ActionCenter.GestureTabSwitchDirection
    ) {
        fromWebView.navigationDelegate = self
        toWebView.navigationDelegate = self

        clearLayoutConstraints(for: fromWebView)
        clearLayoutConstraints(for: toWebView)
        fromWebView.translatesAutoresizingMaskIntoConstraints = true
        toWebView.translatesAutoresizingMaskIntoConstraints = true

        let bounds = webContainer.bounds
        fromWebView.frame = bounds
        let startX = direction == .left ? bounds.width : -bounds.width
        toWebView.frame = bounds.offsetBy(dx: startX, dy: 0)

        if toWebView.superview !== webContainer {
            if let overlay = overlayView {
                webContainer.addSubview(toWebView, positioned: .below, relativeTo: overlay)
            } else {
                webContainer.addSubview(toWebView, positioned: .below, relativeTo: fromWebView)
            }
        }

        if fromWebView.superview !== webContainer {
            if let overlay = overlayView {
                webContainer.addSubview(fromWebView, positioned: .below, relativeTo: overlay)
            } else {
                webContainer.addSubview(fromWebView)
            }
        }

        webContainer.layoutSubtreeIfNeeded()
    }

    private func clearLayoutConstraints(for webView: WKWebView) {
        let related = webContainer.constraints.filter { constraint in
            (constraint.firstItem as AnyObject?) === webView
                || (constraint.secondItem as AnyObject?) === webView
        }
        if !related.isEmpty {
            webContainer.removeConstraints(related)
        }
    }

    private func updateInteractiveTabSwitch(totalX: CGFloat) {
        guard let state = interactiveTabSwitchState else { return }
        let bounds = webContainer.bounds
        let width = bounds.width
        guard width > 1 else { return }

        let offset: CGFloat
        switch state.direction {
        case .left:
            offset = max(-width, min(0, totalX))
            state.fromWebView.frame = bounds.offsetBy(dx: offset, dy: 0)
            state.toWebView.frame = bounds.offsetBy(dx: width + offset, dy: 0)
        case .right:
            offset = min(width, max(0, totalX))
            state.fromWebView.frame = bounds.offsetBy(dx: offset, dy: 0)
            state.toWebView.frame = bounds.offsetBy(dx: -width + offset, dy: 0)
        }
    }

    private func finishInteractiveTabSwitch(totalX: CGFloat) {
        guard let state = interactiveTabSwitchState else { return }
        interactiveTabSwitchState = nil

        let width = webContainer.bounds.width
        guard width > 1 else {
            tabManager.selectTab(index: state.targetIndex)
            return
        }

        let commitThreshold = max(88, width * 0.22)
        let shouldCommit: Bool
        switch state.direction {
        case .left:
            shouldCommit = totalX <= -commitThreshold
        case .right:
            shouldCommit = totalX >= commitThreshold
        }

        let fromTargetX: CGFloat
        let toTargetX: CGFloat
        if shouldCommit {
            fromTargetX = state.direction == .left ? -width : width
            toTargetX = 0
        } else {
            fromTargetX = 0
            toTargetX = state.direction == .left ? width : -width
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            state.fromWebView.animator().frame.origin.x = fromTargetX
            state.toWebView.animator().frame.origin.x = toTargetX
        } completionHandler: { [weak self] in
            guard let self else { return }
            if shouldCommit {
                self.tabManager.selectTab(index: state.targetIndex)
            } else {
                self.attachWebView(state.fromWebView)
            }
        }
    }

    private func captureThumbnail(for webView: WKWebView) {
        guard webView.bounds.width > 1, webView.bounds.height > 1 else { return }

        let width = min(webView.bounds.width, 320)
        let height = min(webView.bounds.height, 160)
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)

        webView.takeSnapshot(with: config) { [weak self, weak webView] image, _ in
            guard let self, let webView else { return }
            self.tabManager.updateThumbnail(for: webView, image: image)
        }
    }

    private func rebuildTabStrip() {
        tabStripStackView.arrangedSubviews.forEach {
            tabStripStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let visibleItems: [TabStripItem]
        if tabSearchQuery.isEmpty {
            visibleItems = tabManager.tabStripItems
        } else {
            visibleItems = tabManager.tabStripItems.filter { item in
                item.title.localizedCaseInsensitiveContains(tabSearchQuery)
            }
        }

        for item in visibleItems {
            let chip = TabChipView(
                index: item.index,
                title: item.title,
                thumbnail: item.thumbnail,
                size: UI.tabChipSize,
                isActive: item.isActive,
                isProtected: item.isProtected
            )
            chip.onSelect = { [weak self] index in
                self?.tabManager.selectTab(index: index)
            }
            chip.onToggleProtection = { [weak self] index in
                self?.tabManager.toggleProtection(index: index)
            }
            tabStripStackView.addArrangedSubview(chip)
        }

        layoutTabStripAndRevealActive()
    }

    private func confirmCloseProtectedTab() -> Bool {
        guard let window else { return false }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保護タブを閉じますか？"
        alert.informativeText = "このタブは保護されています。閉じるには確認が必要です。"
        alert.addButton(withTitle: "閉じる")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func syncToolbarLayout() {
        guard let window, let contentView = window.contentView else { return }

        let trafficButtons: [NSButton] = [.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }

        let maxButtonX = trafficButtons.compactMap { button -> CGFloat? in
            guard let superview = button.superview else { return nil }
            let rect = contentView.convert(button.frame, from: superview)
            return rect.maxX
        }.max() ?? 74

        tabStripMinLeadingConstraint?.constant = maxButtonX + 10

        let rightPanelWidth = min(300, max(220, window.frame.width * 0.24))
        rightPanelWidthConstraint?.constant = rightPanelWidth

        let reservedRight = rightPanelWidth + 10 + 20 + 8 + 12
        let available = window.frame.width - (maxButtonX + 10) - reservedRight
        tabStripWidthConstraint?.constant = min(640, max(220, available))
        tabStripHeightConstraint?.constant = UI.tabChipSize.height + 6
        layoutTabStripAndRevealActive()
    }

    private func layoutTabStripAndRevealActive() {
        guard let clipView = tabStripScrollView.contentView as NSClipView? else { return }

        tabStripStackView.layoutSubtreeIfNeeded()

        let contentHeight = max(tabStripContainer.bounds.height, UI.tabChipSize.height)
        let chipWidth = tabStripStackView.fittingSize.width
        let viewportWidth = tabStripContainer.bounds.width
        let documentWidth = max(chipWidth, viewportWidth)
        let centeredX = chipWidth < viewportWidth ? (viewportWidth - chipWidth) * 0.5 : 0
        tabStripDocumentView.frame = CGRect(x: 0, y: 0, width: documentWidth, height: contentHeight)
        tabStripStackView.frame = CGRect(x: centeredX, y: 0, width: chipWidth, height: contentHeight)

        if chipWidth > viewportWidth,
           let activeChip = tabStripStackView.arrangedSubviews.first(where: {
            ($0 as? TabChipView)?.isActiveChip == true
        }) {
            var target = activeChip.frame.insetBy(dx: -16, dy: 0)
            target.origin.y = 0
            target.size.height = contentHeight
            clipView.scrollToVisible(target)
            tabStripScrollView.reflectScrolledClipView(clipView)
        } else {
            clipView.scroll(to: .zero)
            tabStripScrollView.reflectScrolledClipView(clipView)
        }
    }
}

extension MainWindowController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            submitAddressFieldIfNeeded()
            return true
        }

        if commandSelector == #selector(cancelOperation(_:)) {
            endAddressEditingWithoutSubmit()
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if isAddressEditing, window?.firstResponder !== addressEditorField.currentEditor() {
            endAddressEditingWithoutSubmit()
        }
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        syncToolbarLayout()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        syncToolbarLayout()
    }
}

extension MainWindowController: TabManagerDelegate {
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?) {
        guard let webView else {
            webContainer.subviews.forEach { $0.removeFromSuperview() }
            overlayView = nil
            interactiveTabSwitchState = nil
            applyAddressDisplayMode(display: "")
            rebuildTabStrip()
            return
        }

        interactiveTabSwitchState = nil
        attachWebView(webView)
    }

    func tabManager(_ manager: TabManager, didUpdateTabs count: Int) {
        rebuildTabStrip()
    }
}

extension MainWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tabManager.updateMetadata(for: webView)
        captureThumbnail(for: webView)

        if tabManager.currentWebView === webView, !isAddressEditing {
            applyAddressDisplayMode(display: webView.url?.absoluteString ?? "")
            rebuildTabStrip()
        }
    }
}

private final class LiquidGlassToolbarView: NSView {
    let contentLayoutView = NSView()
    private let separatorLayer = CALayer()
    private let topShineLayer = CAGradientLayer()
    private let bottomDepthLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override func layout() {
        super.layout()

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        separatorLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / scale)
        topShineLayer.frame = CGRect(x: 0, y: bounds.height * 0.46, width: bounds.width, height: bounds.height * 0.54)
        bottomDepthLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.42)
    }

    override var isOpaque: Bool { false }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(separatorLayer)
        layer?.addSublayer(bottomDepthLayer)
        layer?.addSublayer(topShineLayer)
        separatorLayer.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        topShineLayer.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.02).cgColor,
            NSColor.clear.cgColor
        ]
        topShineLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        topShineLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        bottomDepthLayer.colors = [
            NSColor.black.withAlphaComponent(0.03).cgColor,
            NSColor.clear.cgColor
        ]
        bottomDepthLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        bottomDepthLayer.endPoint = CGPoint(x: 0.5, y: 1.0)

        contentLayoutView.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
            let glassContainer = NSGlassEffectContainerView()
            glassContainer.translatesAutoresizingMaskIntoConstraints = false
            glassContainer.spacing = 0
            addSubview(glassContainer)

            let glassView = NSGlassEffectView()
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.style = .clear
            glassView.cornerRadius = 0
            glassView.tintColor = NSColor.white.withAlphaComponent(0.012)
            glassView.contentView = contentLayoutView

            glassContainer.contentView = glassView

            NSLayoutConstraint.activate([
                glassContainer.topAnchor.constraint(equalTo: topAnchor),
                glassContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        } else {
            let fallback = NSVisualEffectView()
            fallback.translatesAutoresizingMaskIntoConstraints = false
            fallback.material = .underWindowBackground
            fallback.state = .followsWindowActiveState
            fallback.blendingMode = .behindWindow
            fallback.isEmphasized = false
            fallback.addSubview(contentLayoutView)
            addSubview(fallback)

            NSLayoutConstraint.activate([
                fallback.topAnchor.constraint(equalTo: topAnchor),
                fallback.leadingAnchor.constraint(equalTo: leadingAnchor),
                fallback.trailingAnchor.constraint(equalTo: trailingAnchor),
                fallback.bottomAnchor.constraint(equalTo: bottomAnchor),

                contentLayoutView.topAnchor.constraint(equalTo: fallback.topAnchor),
                contentLayoutView.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
                contentLayoutView.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
                contentLayoutView.bottomAnchor.constraint(equalTo: fallback.bottomAnchor)
            ])
        }
    }
}

private final class HorizontalOnlyClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = super.constrainBoundsRect(proposedBounds)
        constrained.origin.y = 0
        return constrained
    }
}

private final class AddressDisplayView: NSView {
    private let textField = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    func update(text: String) {
        textField.stringValue = text
        toolTip = text
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.systemFont(ofSize: 13.0, weight: .regular)
        textField.textColor = NSColor(calibratedWhite: 0.35, alpha: 0.92)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.usesSingleLineMode = true
        textField.alignment = .right

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class TabChipView: NSView {
    private let index: Int
    private let thumbnailView = NSImageView()
    private let protectedIconView = NSImageView()
    private let activeAccentLayer = CAGradientLayer()
    private let active: Bool
    private let protectedState: Bool

    var onSelect: ((Int) -> Void)?
    var onToggleProtection: ((Int) -> Void)?
    var isActiveChip: Bool { active }

    init(index: Int, title: String, thumbnail: NSImage?, size: NSSize, isActive: Bool, isProtected: Bool) {
        self.index = index
        self.active = isActive
        protectedState = isProtected
        super.init(frame: .zero)
        setupView(title: title, thumbnail: thumbnail, size: size, isActive: isActive, isProtected: isProtected)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onToggleProtection?(index)
        } else {
            onSelect?(index)
        }
    }

    override func layout() {
        super.layout()
        guard active else { return }
        activeAccentLayer.frame = CGRect(x: 2, y: bounds.height - 3, width: bounds.width - 4, height: 2)
    }

    private func setupView(title: String, thumbnail: NSImage?, size: NSSize, isActive: Bool, isProtected: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = title
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.borderColor = isActive
            ? NSColor.systemCyan.withAlphaComponent(0.90).cgColor
            : NSColor.white.withAlphaComponent(0.56).cgColor
        layer?.backgroundColor = isActive
            ? NSColor.systemBlue.withAlphaComponent(0.24).cgColor
            : NSColor.white.withAlphaComponent(0.30).cgColor
        layer?.shadowColor = NSColor.systemBlue.withAlphaComponent(0.92).cgColor
        layer?.shadowOpacity = isActive ? 0.52 : 0
        layer?.shadowRadius = isActive ? 8 : 0
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleAxesIndependently
        thumbnailView.image = thumbnail
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 1
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.68).cgColor
        addSubview(thumbnailView)

        protectedIconView.translatesAutoresizingMaskIntoConstraints = false
        protectedIconView.imageScaling = .scaleProportionallyUpOrDown
        protectedIconView.isHidden = !isProtected
        let icon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        protectedIconView.image = icon?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        protectedIconView.contentTintColor = NSColor.white.withAlphaComponent(0.95)
        addSubview(protectedIconView)

        if isActive {
            activeAccentLayer.colors = [
                NSColor.systemCyan.withAlphaComponent(0.95).cgColor,
                NSColor.systemBlue.withAlphaComponent(0.65).cgColor
            ]
            activeAccentLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
            activeAccentLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
            layer?.addSublayer(activeAccentLayer)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height),

            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            protectedIconView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            protectedIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            protectedIconView.widthAnchor.constraint(equalToConstant: 12),
            protectedIconView.heightAnchor.constraint(equalToConstant: 12)
        ])

        if isActive {
            activeAccentLayer.cornerRadius = 1
        }

        if protectedState {
            layer?.borderColor = NSColor.systemYellow.withAlphaComponent(isActive ? 0.95 : 0.75).cgColor
        }
    }
}
