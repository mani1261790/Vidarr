import Foundation

/// ブラウザのアクションを集約し、UI やジェスチャーから呼び出しやすくする層。
final class ActionCenter {
    private let tabManager: TabManager
    private let session: BrowserSession
    var focusAddressField: (() -> Void)? // 住所欄フォーカス用のフック（存在しない場合は nil）

    init(tabManager: TabManager, session: BrowserSession) {
        self.tabManager = tabManager
        self.session = session
    }

    // MARK: - Tabs
    func tabNext() { tabManager.selectNextTab() }
    func tabPrev() { tabManager.selectPrevTab() }
    func tabClose() { tabManager.closeCurrentTab() }
    func tabCloseAll() { tabManager.closeAllTabs() }
    func tabReopenClosed() { tabManager.reopenClosedTab() }

    // MARK: - Navigation
    func goBack() { session.goBack() }
    func goForward() { session.goForward() }

    // MARK: - Reload
    func reload() { tabManager.reloadCurrentTab() }
    func reloadAll() { tabManager.reloadAllTabs() }

    // MARK: - Search
    func search() {
        if let focus = focusAddressField {
            focus()
        } else {
            print("SEARCH")
        }
    }
}
