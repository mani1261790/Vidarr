import Cocoa
import WebKit

final class MainWindowController: NSWindowController {
    private let rootContainer = NSView()
    private let toolbarContainer = NSView()
    private let webContainer = NSView()

    private let addressField = NSTextField()
    private let newTabButton = NSButton(title: "+", target: nil, action: nil)
    private let tabCountLabel = NSTextField(labelWithString: "0")

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
        window.setFrameAutosaveName("MainWindow")

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
        toolbarContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.88).cgColor

        setupToolbarUI()

        NSLayoutConstraint.activate([
            rootContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            toolbarContainer.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            toolbarContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: 44),

            webContainer.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor)
        ])
    }

    private func setupToolbarUI() {
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.placeholderString = "Search or enter website name"
        addressField.font = NSFont.systemFont(ofSize: 13)
        addressField.focusRingType = .none
        addressField.bezelStyle = .roundedBezel
        addressField.delegate = self

        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.bezelStyle = .texturedRounded
        newTabButton.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        newTabButton.target = self
        newTabButton.action = #selector(didTapNewTab)

        tabCountLabel.translatesAutoresizingMaskIntoConstraints = false
        tabCountLabel.alignment = .right
        tabCountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        tabCountLabel.textColor = .secondaryLabelColor

        toolbarContainer.addSubview(newTabButton)
        toolbarContainer.addSubview(addressField)
        toolbarContainer.addSubview(tabCountLabel)

        NSLayoutConstraint.activate([
            newTabButton.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: 10),
            newTabButton.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 26),

            addressField.leadingAnchor.constraint(equalTo: newTabButton.trailingAnchor, constant: 8),
            addressField.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            addressField.heightAnchor.constraint(equalToConstant: 28),

            tabCountLabel.leadingAnchor.constraint(equalTo: addressField.trailingAnchor, constant: 8),
            tabCountLabel.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -10),
            tabCountLabel.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            tabCountLabel.widthAnchor.constraint(equalToConstant: 36)
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
            return
        }
        attachWebView(webView)
    }

    func tabManager(_ manager: TabManager, didUpdateTabs count: Int) {
        tabCountLabel.stringValue = "\(count)"
    }
}

extension MainWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if tabManager.currentWebView === webView {
            addressField.stringValue = webView.url?.absoluteString ?? ""
        }
    }
}
