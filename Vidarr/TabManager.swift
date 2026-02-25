import Foundation
import WebKit

public protocol TabManagerDelegate: AnyObject {
    /// 選択中のタブが変わったときに呼ばれ、現在の WKWebView を提供します（存在しない場合は nil）。
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?)
    /// タブ数が変化したときに呼ばれます。
    func tabManager(_ manager: TabManager, didUpdateTabs count: Int)
}

/// シンプルなタブ管理。各タブは独自の WKWebView を持ちます。
public final class TabManager {
    public weak var delegate: TabManagerDelegate?

    private struct Tab {
        let webView: WKWebView
        var lastURL: URL?
    }

    private struct ClosedTabSnapshot {
        let url: URL?
    }

    private var tabs: [Tab] = []
    private var closedStack: [ClosedTabSnapshot] = [] // LIFO, keep last 20

    private(set) public var currentIndex: Int = -1

    public init() {}

    public var currentWebView: WKWebView? {
        guard currentIndex >= 0 && currentIndex < tabs.count else { return nil }
        return tabs[currentIndex].webView
    }

    // MARK: - Public API
    public func newTab(url: URL?) {
        performOnMain { [weak self] in
            guard let self = self else { return }
            let webView = self.createWebView()
            var tab = Tab(webView: webView, lastURL: nil)
            self.tabs.append(tab)
            self.currentIndex = self.tabs.count - 1
            self.delegate?.tabManager(self, didUpdateTabs: self.tabs.count)
            self.delegate?.tabManager(self, didSelect: webView)

            if let url = url {
                tab.lastURL = url
                webView.load(URLRequest(url: url))
                self.tabs[self.currentIndex] = tab
            }
        }
    }

    public func selectTab(index: Int) {
        performOnMain { [weak self] in
            guard let self = self else { return }
            guard index >= 0 && index < self.tabs.count else { return }
            self.currentIndex = index
            self.delegate?.tabManager(self, didSelect: self.tabs[index].webView)
        }
    }

    public func selectNextTab() {
        performOnMain { [weak self] in
            guard let self = self else { return }
            guard !self.tabs.isEmpty else { return }
            let next = (self.currentIndex + 1 + self.tabs.count) % self.tabs.count
            self.selectTab(index: next)
        }
    }

    public func selectPrevTab() {
        performOnMain { [weak self] in
            guard let self = self else { return }
            guard !self.tabs.isEmpty else { return }
            let prev = (self.currentIndex - 1 + self.tabs.count) % self.tabs.count
            self.selectTab(index: prev)
        }
    }

    public func closeCurrentTab() {
        performOnMain { [weak self] in
            guard let self = self else { return }
            guard self.currentIndex >= 0 && self.currentIndex < self.tabs.count else { return }
            let removed = self.tabs.remove(at: self.currentIndex)
            let snapshot = ClosedTabSnapshot(url: removed.webView.url ?? removed.lastURL)
            self.pushClosed(snapshot)

            if self.tabs.isEmpty {
                self.currentIndex = -1
                self.delegate?.tabManager(self, didUpdateTabs: 0)
                self.delegate?.tabManager(self, didSelect: nil)
            } else {
                self.currentIndex = min(self.currentIndex, self.tabs.count - 1)
                self.delegate?.tabManager(self, didUpdateTabs: self.tabs.count)
                self.delegate?.tabManager(self, didSelect: self.tabs[self.currentIndex].webView)
            }
        }
    }

    public func closeAllTabs() {
        performOnMain { [weak self] in
            guard let self = self else { return }
            for tab in self.tabs {
                let snapshot = ClosedTabSnapshot(url: tab.webView.url ?? tab.lastURL)
                self.pushClosed(snapshot)
            }
            self.tabs.removeAll()
            self.currentIndex = -1
            self.delegate?.tabManager(self, didUpdateTabs: 0)
            self.delegate?.tabManager(self, didSelect: nil)
        }
    }

    public func reloadCurrentTab() {
        performOnMain { [weak self] in
            self?.currentWebView?.reload()
        }
    }

    public func reloadAllTabs() {
        performOnMain { [weak self] in
            guard let self = self else { return }
            for tab in self.tabs { tab.webView.reload() }
        }
    }

    public func reopenClosedTab() {
        performOnMain { [weak self] in
            guard let self = self else { return }
            guard let snapshot = self.closedStack.popLast() else { return }
            self.newTab(url: snapshot.url)
        }
    }

    // MARK: - Helpers
    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }

    private func pushClosed(_ snapshot: ClosedTabSnapshot) {
        closedStack.append(snapshot)
        if closedStack.count > 20 {
            closedStack.removeFirst(closedStack.count - 20)
        }
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async { work() } }
    }
}
