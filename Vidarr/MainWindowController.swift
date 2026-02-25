import Cocoa
import WebKit

final class MainWindowController: NSWindowController {
    private let rootContainer = NSView()
    private let toolbarContainer = NSView()
    private let webContainer = NSView()

    private let addressField = NSTextField()
    private let newTabButton = NSButton(title: "+", target: nil, action: nil)
    private let tabStripContainer = NSView()
    private let tabStripStackView = NSStackView()

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

        toolbarContainer.wantsLayer = true
        toolbarContainer.layer?.backgroundColor = NSColor(calibratedWhite: 0.88, alpha: 0.96).cgColor

        setupToolbarUI()

        NSLayoutConstraint.activate([
            rootContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            toolbarContainer.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            toolbarContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: 48),

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
        tabStripContainer.addSubview(tabStripStackView)

        tabStripStackView.translatesAutoresizingMaskIntoConstraints = false
        tabStripStackView.orientation = .horizontal
        tabStripStackView.alignment = .centerY
        tabStripStackView.spacing = 6

        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.placeholderString = "開きたいページを入力"
        addressField.font = NSFont.systemFont(ofSize: 13)
        addressField.focusRingType = .none
        addressField.bezelStyle = .roundedBezel
        addressField.delegate = self

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.bezelStyle = .texturedRounded
        newTabButton.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        newTabButton.target = self
        newTabButton.action = #selector(didTapNewTab)

        toolbarContainer.addSubview(tabStripContainer)
        toolbarContainer.addSubview(newTabButton)
        toolbarContainer.addSubview(addressField)

        NSLayoutConstraint.activate([
            tabStripContainer.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: 8),
            tabStripContainer.topAnchor.constraint(equalTo: toolbarContainer.topAnchor, constant: 6),
            tabStripContainer.bottomAnchor.constraint(equalTo: toolbarContainer.bottomAnchor, constant: -6),

            tabStripStackView.leadingAnchor.constraint(equalTo: tabStripContainer.leadingAnchor),
            tabStripStackView.trailingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor),
            tabStripStackView.topAnchor.constraint(equalTo: tabStripContainer.topAnchor),
            tabStripStackView.bottomAnchor.constraint(equalTo: tabStripContainer.bottomAnchor),

            newTabButton.leadingAnchor.constraint(equalTo: tabStripContainer.trailingAnchor, constant: 8),
            newTabButton.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 28),

            addressField.leadingAnchor.constraint(equalTo: newTabButton.trailingAnchor, constant: 10),
            addressField.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -10),
            addressField.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            addressField.heightAnchor.constraint(equalToConstant: 28),
            addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 250)
        ])

        addressField.setContentHuggingPriority(.required, for: .horizontal)
        addressField.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        rebuildTabStrip()
    }

    private func rebuildTabStrip() {
        tabStripStackView.arrangedSubviews.forEach {
            tabStripStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for item in tabManager.tabStripItems {
            let chip = TabChipView(index: item.index, title: item.title, isActive: item.isActive)
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
        if tabManager.currentWebView === webView {
            addressField.stringValue = webView.url?.absoluteString ?? ""
            rebuildTabStrip()
        }
    }
}

private final class TabChipView: NSView {
    private let index: Int
    private let preview = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let isActive: Bool

    var onSelect: ((Int) -> Void)?

    init(index: Int, title: String, isActive: Bool) {
        self.index = index
        self.isActive = isActive
        super.init(frame: .zero)
        setupView(title: title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }

    private func setupView(title: String) {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1

        if isActive {
            layer?.backgroundColor = NSColor(calibratedWhite: 0.3, alpha: 0.9).cgColor
            layer?.borderColor = NSColor(calibratedWhite: 0.2, alpha: 0.8).cgColor
        } else {
            layer?.backgroundColor = NSColor(calibratedWhite: 0.75, alpha: 0.55).cgColor
            layer?.borderColor = NSColor(calibratedWhite: 0.6, alpha: 0.5).cgColor
        }

        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 2
        preview.layer?.backgroundColor = isActive
            ? NSColor(calibratedWhite: 0.9, alpha: 0.45).cgColor
            : NSColor(calibratedWhite: 0.95, alpha: 0.4).cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = title
        titleLabel.textColor = isActive ? NSColor.white : NSColor.labelColor

        addSubview(preview)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            preview.widthAnchor.constraint(equalToConstant: 20),
            preview.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            heightAnchor.constraint(equalToConstant: 28)
        ])

        let preferredWidth = widthAnchor.constraint(equalToConstant: 130)
        preferredWidth.priority = .defaultLow
        preferredWidth.isActive = true
    }
}
