import Cocoa
import WebKit

final class MainWindowController: NSWindowController {
    private enum UI {
        static let toolbarHeight: CGFloat = 56
        static let tabChipSize = NSSize(width: 116, height: 38)
    }

    private let rootContainer = NSView()
    private let toolbarContainer = LiquidGlassToolbarView()
    private let webContainer = NSView()

    private let tabStripContainer = NSView()
    private let tabStripStackView = NSStackView()
    private let newTabButton = NSButton(title: "+", target: nil, action: nil)
    private let addressDisplayView = AddressDisplayView()
    private let addressEditorField = NSTextField()

    private var tabStripMinLeadingConstraint: NSLayoutConstraint?
    private var tabStripWidthConstraint: NSLayoutConstraint?
    private var addressWidthConstraint: NSLayoutConstraint?

    private let tabManager: TabManager
    private let session: BrowserSession
    private let actions: ActionCenter

    private var overlayView: GestureOverlayView?
    private var isAddressEditing = false
    private var currentAddressURLString = ""

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
        tabStripContainer.layer?.backgroundColor = NSColor.clear.cgColor
        tabStripContainer.layer?.masksToBounds = true

        tabStripStackView.translatesAutoresizingMaskIntoConstraints = false
        tabStripStackView.orientation = .horizontal
        tabStripStackView.alignment = .centerY
        tabStripStackView.spacing = 6
        tabStripContainer.addSubview(tabStripStackView)

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.target = self
        newTabButton.action = #selector(didTapNewTab)
        newTabButton.isBordered = false
        newTabButton.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        newTabButton.contentTintColor = NSColor(calibratedWhite: 0.22, alpha: 0.92)

        addressDisplayView.translatesAutoresizingMaskIntoConstraints = false
        addressDisplayView.onClick = { [weak self] in
            self?.beginAddressEditing()
        }

        addressEditorField.translatesAutoresizingMaskIntoConstraints = false
        addressEditorField.delegate = self
        addressEditorField.font = NSFont.systemFont(ofSize: 12.5)
        addressEditorField.focusRingType = .none
        addressEditorField.bezelStyle = .roundedBezel
        addressEditorField.isHidden = true

        let toolbarContent = toolbarContainer.contentLayoutView
        toolbarContent.addSubview(tabStripContainer)
        toolbarContent.addSubview(newTabButton)
        toolbarContent.addSubview(addressDisplayView)
        toolbarContent.addSubview(addressEditorField)

        let minLeading = tabStripContainer.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarContent.leadingAnchor, constant: 84)
        tabStripMinLeadingConstraint = minLeading
        let tabWidth = tabStripContainer.widthAnchor.constraint(equalToConstant: 520)
        tabStripWidthConstraint = tabWidth
        let addressWidth = addressDisplayView.widthAnchor.constraint(equalToConstant: 240)
        addressWidthConstraint = addressWidth

        NSLayoutConstraint.activate([
            minLeading,
            tabWidth,
            tabStripContainer.centerXAnchor.constraint(equalTo: toolbarContent.centerXAnchor),
            tabStripContainer.topAnchor.constraint(equalTo: toolbarContent.topAnchor, constant: 5),
            tabStripContainer.bottomAnchor.constraint(equalTo: toolbarContent.bottomAnchor, constant: -5),
            tabStripContainer.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -6),

            tabStripStackView.centerXAnchor.constraint(equalTo: tabStripContainer.centerXAnchor),
            tabStripStackView.leadingAnchor.constraint(greaterThanOrEqualTo: tabStripContainer.leadingAnchor),
            tabStripStackView.trailingAnchor.constraint(lessThanOrEqualTo: tabStripContainer.trailingAnchor),
            tabStripStackView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabStripStackView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),

            newTabButton.centerYAnchor.constraint(equalTo: toolbarContent.centerYAnchor),
            newTabButton.trailingAnchor.constraint(equalTo: addressDisplayView.leadingAnchor, constant: -8),
            newTabButton.widthAnchor.constraint(equalToConstant: 22),
            newTabButton.heightAnchor.constraint(equalToConstant: 22),

            addressDisplayView.centerYAnchor.constraint(equalTo: toolbarContent.centerYAnchor),
            addressDisplayView.trailingAnchor.constraint(equalTo: toolbarContent.trailingAnchor, constant: -10),
            addressDisplayView.heightAnchor.constraint(equalToConstant: 24),
            addressWidth,

            addressEditorField.centerYAnchor.constraint(equalTo: addressDisplayView.centerYAnchor),
            addressEditorField.leadingAnchor.constraint(equalTo: addressDisplayView.leadingAnchor),
            addressEditorField.trailingAnchor.constraint(equalTo: addressDisplayView.trailingAnchor),
            addressEditorField.heightAnchor.constraint(equalTo: addressDisplayView.heightAnchor)
        ])

        applyAddressDisplayMode(display: "")
    }

    private func configureBindings() {
        tabManager.delegate = self
        actions.focusAddressField = { [weak self] in
            self?.beginAddressEditing()
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
        addressDisplayView.update(text: display.isEmpty ? "開きたいページを入力" : display)

        addressEditorField.stringValue = display
        addressEditorField.isHidden = true
        addressDisplayView.isHidden = false
    }

    private func attachWebView(_ webView: WKWebView) {
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        overlayView = nil

        webView.navigationDelegate = self
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

        for item in tabManager.tabStripItems {
            let chip = TabChipView(
                index: item.index,
                title: item.title,
                thumbnail: item.thumbnail,
                size: UI.tabChipSize,
                isActive: item.isActive
            )
            chip.onSelect = { [weak self] index in
                self?.tabManager.selectTab(index: index)
            }
            tabStripStackView.addArrangedSubview(chip)
        }
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

        let addressWidth = min(280, max(210, window.frame.width * 0.22))
        addressWidthConstraint?.constant = addressWidth

        let reservedRight = addressWidth + 10 + 20 + 8 + 12
        let available = window.frame.width - (maxButtonX + 10) - reservedRight
        tabStripWidthConstraint?.constant = min(640, max(220, available))
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
            applyAddressDisplayMode(display: "")
            rebuildTabStrip()
            return
        }

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
    }

    private func setupView() {
        wantsLayer = true
        layer?.addSublayer(separatorLayer)
        separatorLayer.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor

        contentLayoutView.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
            let glassContainer = NSGlassEffectContainerView()
            glassContainer.translatesAutoresizingMaskIntoConstraints = false
            glassContainer.spacing = 0
            addSubview(glassContainer)

            let glassView = NSGlassEffectView()
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.style = .regular
            glassView.cornerRadius = 0
            glassView.tintColor = NSColor.white.withAlphaComponent(0.06)
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
            fallback.material = .headerView
            fallback.state = .followsWindowActiveState
            fallback.blendingMode = .behindWindow
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
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.34).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.systemFont(ofSize: 11.5)
        textField.textColor = NSColor(calibratedWhite: 0.22, alpha: 0.92)
        textField.lineBreakMode = .byTruncatingMiddle
        textField.usesSingleLineMode = true

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

private final class TabChipView: NSView {
    private let index: Int
    private let thumbnailView = NSImageView()

    var onSelect: ((Int) -> Void)?

    init(index: Int, title: String, thumbnail: NSImage?, size: NSSize, isActive: Bool) {
        self.index = index
        super.init(frame: .zero)
        setupView(title: title, thumbnail: thumbnail, size: size, isActive: isActive)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }

    private func setupView(title: String, thumbnail: NSImage?, size: NSSize, isActive: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = title
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = isActive
            ? NSColor.white.withAlphaComponent(0.90).cgColor
            : NSColor.white.withAlphaComponent(0.56).cgColor
        layer?.backgroundColor = isActive
            ? NSColor.white.withAlphaComponent(0.52).cgColor
            : NSColor.white.withAlphaComponent(0.30).cgColor

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleAxesIndependently
        thumbnailView.image = thumbnail
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.68).cgColor
        addSubview(thumbnailView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height),

            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            thumbnailView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
    }
}
