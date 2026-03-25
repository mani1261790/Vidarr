import Foundation

/// すべてのブラウザ操作の入口。
/// UI / ジェスチャーの双方はこのクラス経由で操作する。
final class ActionCenter {
    enum GestureTabSwitchDirection {
        case left
        case right
    }

    private let tabManager: TabManager
    private let session: BrowserSession

    var focusAddressField: (() -> Void)?
    var confirmCloseProtectedTab: (() -> Bool)?
    var performGestureTabSwitch: ((GestureTabSwitchDirection) -> Void)?
    var beginInteractiveGestureTabSwitch: ((GestureTabSwitchDirection) -> Bool)?
    var updateInteractiveGestureTabSwitch: ((CGFloat) -> Void)?
    var finishInteractiveGestureTabSwitch: ((CGFloat) -> Void)?

    init(tabManager: TabManager, session: BrowserSession) {
        self.tabManager = tabManager
        self.session = session
    }

    // MARK: - Tabs
    func newTab() {
        tabManager.newTab(url: BrowserSession.defaultHomeURL)
    }

    func tabNext() {
        tabManager.selectNextTab()
    }

    func tabPrev() {
        tabManager.selectPrevTab()
    }

    func gestureTabSwitchLeft() {
        if let performGestureTabSwitch {
            performGestureTabSwitch(.left)
            return
        }
        tabNext()
    }

    func gestureTabSwitchRight() {
        if let performGestureTabSwitch {
            performGestureTabSwitch(.right)
            return
        }
        tabPrev()
    }

    func beginInteractiveTabSwitch(direction: GestureTabSwitchDirection) -> Bool {
        beginInteractiveGestureTabSwitch?(direction) ?? false
    }

    func updateInteractiveTabSwitch(totalX: CGFloat) {
        updateInteractiveGestureTabSwitch?(totalX)
    }

    func finishInteractiveTabSwitch(totalX: CGFloat) {
        finishInteractiveGestureTabSwitch?(totalX)
    }

    func tabClose() {
        if tabManager.isCurrentTabProtected {
            let confirmed = confirmCloseProtectedTab?() ?? false
            if !confirmed {
                return
            }
        }
        tabManager.closeCurrentTab()
    }

    func tabCloseAll() {
        tabManager.closeAllTabs()
    }

    func tabReopenClosed() {
        tabManager.reopenClosedTab()
    }

    // MARK: - Navigation
    func goBack() {
        session.goBack()
    }

    func goForward() {
        session.goForward()
    }

    // MARK: - Reload
    func reload() {
        tabManager.reloadCurrentTab()
    }

    func reloadAll() {
        tabManager.reloadAllTabs()
    }

    // MARK: - Location / Search
    func openLocationInput(_ rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL = normalizeToURL(from: trimmed)
        if tabManager.currentWebView == nil {
            tabManager.newTab(url: targetURL)
        } else {
            session.load(url: targetURL)
        }
    }

    func search() {
        focusAddressField?()
    }

    private func normalizeToURL(from input: String) -> URL {
        if let url = URL(string: input), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https", "file", "about":
                return url
            default:
                return searchURL(for: input)
            }
        }

        if input.contains(" ") {
            return searchURL(for: input)
        }

        if input.contains(".") {
            return URL(string: "https://\(input)") ?? searchURL(for: input)
        }

        return searchURL(for: input)
    }

    private func searchURL(for query: String) -> URL {
        BrowserPreferences.shared.searchURL(for: query)
    }
}
