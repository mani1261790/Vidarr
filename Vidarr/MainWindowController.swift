import Cocoa
import WebKit

final class MainWindowController: NSWindowController {
    private let rootContainer = NSView()
    private let toolbarContainer = GradientBarView()
    private let webContainer = NSView()

    private let tabStripContainer = NSView()
    private let tabStripStackView = NSStackView()
    private let newTabButton = NSButton(title: "+", target: nil, action: nil)
    private let addressField = NSTextField()

    private let tabManager: TabManager
    private let session: BrowserSession
    private let actions: ActionCenter

    private var overlayView: GestureOverlayView?

    init() {
        tabManager = TabManager()
        session = BrowserSession(tabManager: tabManager)
        actions = ActionCenter(tabManager: tabManager, session: session)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Vidarr"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .unified
        }
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        configureWindow()
        configureBindings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }

        rootContainer.translatesAutoresizingMaskIntoConstraints = false
        toolbarContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.translatesAutoresizingMaskIntoConstraints = false

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
            toolbarContainer.heightAnchor.constraint(equalToConstant: 50),

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
        newTabButton.bezelStyle = .texturedRounded
        newTabButton.font = NSFont.systemFont(ofSize: 15, weight: .regular)

        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.placeholderString = "開きたいページを入力"
        addressField.font = NSFont.systemFont(ofSize: 12.5)
        addressField.focusRingType = .none
        addressField.bezelStyle = .roundedBezel
        addressField.delegate = self

        toolbarContainer.addSubview(tabStripContainer)
        toolbarContainer.addSubview(newTabButton)
        toolbarContainer.addSubview(addressField)

        NSLayoutConstraint.activate([
            tabStripContainer.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: 8),
            tabStripContainer.topAnchor.constraint(equalTo: toolbarContainer.topAnchor, constant: 8),
            tabStripContainer.bottomAnchor.constraint(equalTo: toolbarContainer.bottomAnchor, constant: -8),
            tabStripContainer.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -8),

            tabStripStackView.leadingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor),
            tabStripStackView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabStripStackView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),
            tabStripStackView.trailingAnchor.constraint(lessThanOrEqualTo: tabStripContainer.trailingAnchor),

            newTabButton.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            newTabButton.trailingAnchor.constraint(equalTo: addressField.leadingAnchor, constant: -10),
            newTabButton.widthAnchor.constraint(equalToConstant: 28),

            addressField.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            addressField.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -10),
            addressField.heightAnchor.constraint(equalToConstant: 27),
            addressField.widthAnchor.constraint(equalToConstant: 320)
        ])
    }

    private func configureBindings() {
        tabManager.delegate = self

        actions.focusAddressField = { [weak self] in
            self?.focusAddressField()
        }

        actions.newTab()
    }

    @objc private func didTapNewTab() {
        actions.newTab()
    }

    private func submitAddressFieldIfNeeded() {
        actions.openLocationInput(addressField.stringValue)
    }

    private func focusAddressField() {
        window?.makeFirstResponder(addressField)
        addressField.selectText(nil)
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
        addressField.stringValue = webView.url?.absoluteString ?? ""
        captureThumbnail(for: webView)
        rebuildTabStrip()
    }

    private func captureThumbnail(for webView: WKWebView) {
        guard webView.bounds.width > 1, webView.bounds.height > 1 else { return }

        let width = min(webView.bounds.width, 360)
        let height = min(webView.bounds.height, 220)
        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = CGRect(x: 0, y: 0, width: width, height: height)

        webView.takeSnapshot(with: snapshotConfig) { [weak self, weak webView] image, _ in
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
            let chip = TabChipView(index: item.index, title: item.title, thumbnail: item.thumbnail, isActive: item.isActive)
            chip.onSelect = { [weak self] index in
                self?.tabManager.selectTab(index: index)
            }
            tabStripStackView.addArrangedSubview(chip)
        }
    }
}

extension MainWindowController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            submitAddressFieldIfNeeded()
            return true
        }
        return false
    }
}

extension MainWindowController: TabManagerDelegate {
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?) {
        guard let webView else {
            webContainer.subviews.forEach { $0.removeFromSuperview() }
            overlayView = nil
            addressField.stringValue = ""
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

        if tabManager.currentWebView === webView {
            addressField.stringValue = webView.url?.absoluteString ?? ""
            rebuildTabStrip()
        }
    }
}

private final class GradientBarView: NSView {
    private let gradientLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.addSublayer(gradientLayer)
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        gradientLayer.colors = [
            NSColor(calibratedWhite: 0.82, alpha: 0.98).cgColor,
            NSColor(calibratedWhite: 0.72, alpha: 0.98).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)

        layer?.borderColor = NSColor(calibratedWhite: 0.42, alpha: 0.65).cgColor
        layer?.borderWidth = 0.6
    }
}

private final class TabChipView: NSView {
    private let index: Int
    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    var onSelect: ((Int) -> Void)?

    init(index: Int, title: String, thumbnail: NSImage?, isActive: Bool) {
        self.index = index
        super.init(frame: .zero)
        setupView(title: title, thumbnail: thumbnail, isActive: isActive)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }

    private func setupView(title: String, thumbnail: NSImage?, isActive: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        toolTip = title

        layer?.cornerRadius = 3
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = isActive
            ? NSColor(calibratedWhite: 0.16, alpha: 0.85).cgColor
            : NSColor(calibratedWhite: 0.5, alpha: 0.5).cgColor
        layer?.backgroundColor = isActive
            ? NSColor(calibratedWhite: 0.22, alpha: 0.95).cgColor
            : NSColor(calibratedWhite: 0.82, alpha: 0.55).cgColor

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleAxesIndependently
        thumbnailView.image = thumbnail
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = NSColor(calibratedWhite: 0.93, alpha: 0.9).cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = isActive ? .white : .secondaryLabelColor
        titleLabel.stringValue = title

        addSubview(thumbnailView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 108),
            heightAnchor.constraint(equalToConstant: 34),

            thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            thumbnailView.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -1),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            titleLabel.heightAnchor.constraint(equalToConstant: 10)
        ])
    }
}
