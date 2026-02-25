import Cocoa
import WebKit

final class MainWindowController: NSWindowController, TabManagerDelegate {
    private let contentContainer = NSView()
    private let toolbarContainer = NSView()
    private let webContainer = NSView()

    private let tabManager: TabManager
    private let session: BrowserSession
    private let actions: ActionCenter

    private var overlayView: GestureOverlayView!

    // MARK: - Init
    init() {
        self.tabManager = TabManager()
        self.session = BrowserSession(tabManager: tabManager)
        self.actions = ActionCenter(tabManager: tabManager, session: session)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Vidarr"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .unified
        }

        super.init(window: window)

        self.window?.contentView = contentContainer
        setupLayout()

        tabManager.delegate = self
        tabManager.newTab(url: URL(string: "https://www.google.com"))
        tabManager.selectTab(index: 0)

        // 検索フォーカスフック（まだ UI がないのでダミー）
        actions.focusAddressField = { [weak self] in
            guard let self else { return }
            print("Focus address field (placeholder)")
            self.window?.makeFirstResponder(nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout
    private func setupLayout() {
        guard let contentView = self.window?.contentView else { return }
        [toolbarContainer, webContainer].forEach { v in
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        // Toolbar placeholder
        toolbarContainer.wantsLayer = true
        toolbarContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.8).cgColor

        NSLayoutConstraint.activate([
            toolbarContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbarContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbarContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbarContainer.heightAnchor.constraint(equalToConstant: 44),

            webContainer.topAnchor.constraint(equalTo: toolbarContainer.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // 初期の WebView コンテナは空。タブ選択時に挿入。
    }

    // MARK: - TabManagerDelegate
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?) {
        // 既存の subviews を置き換え
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        overlayView?.removeFromSuperview()

        guard let webView = webView else { return }

        webView.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)
        ])

        // Overlay
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
        self.overlayView = overlay
    }

    func tabManager(_ manager: TabManager, didUpdateTabs count: Int) {
        // 将来的にタブ UI を更新するためのフック
        print("Tab count: \(count)")
    }
}
