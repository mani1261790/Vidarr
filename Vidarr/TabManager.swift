import Foundation
import WebKit

protocol TabManagerDelegate: AnyObject {
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?)
    func tabManager(_ manager: TabManager, didUpdateTabs count: Int)
}

final class TabManager {
    weak var delegate: TabManagerDelegate?

    private struct Tab {
        let webView: WKWebView
        var lastKnownURL: URL?
    }

    private struct ClosedTabSnapshot {
        let url: URL?
    }

    private var tabs: [Tab] = []
    private var closedStack: [ClosedTabSnapshot] = []

    private(set) var currentIndex: Int = -1

    var currentWebView: WKWebView? {
        guard currentIndex >= 0, currentIndex < tabs.count else { return nil }
        return tabs[currentIndex].webView
    }

    var tabCount: Int { tabs.count }

    var canReopenClosedTab: Bool { !closedStack.isEmpty }

    func newTab(url: URL?) {
        performOnMain { [weak self] in
            guard let self else { return }

            let webView = BrowserSession.makeConfiguredWebView()
            var tab = Tab(webView: webView, lastKnownURL: nil)
            tabs.append(tab)
            currentIndex = tabs.count - 1

            delegate?.tabManager(self, didUpdateTabs: tabs.count)
            delegate?.tabManager(self, didSelect: webView)

            if let targetURL = url {
                tab.lastKnownURL = targetURL
                webView.load(URLRequest(url: targetURL))
                tabs[currentIndex] = tab
            }
        }
    }

    func selectTab(index: Int) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard index >= 0, index < tabs.count else { return }
            currentIndex = index
            delegate?.tabManager(self, didSelect: tabs[index].webView)
        }
    }

    func selectNextTab() {
        performOnMain { [weak self] in
            guard let self, !tabs.isEmpty else { return }
            let next = (currentIndex + 1 + tabs.count) % tabs.count
            selectTab(index: next)
        }
    }

    func selectPrevTab() {
        performOnMain { [weak self] in
            guard let self, !tabs.isEmpty else { return }
            let previous = (currentIndex - 1 + tabs.count) % tabs.count
            selectTab(index: previous)
        }
    }

    func closeCurrentTab() {
        performOnMain { [weak self] in
            guard let self else { return }
            guard currentIndex >= 0, currentIndex < tabs.count else { return }

            let removed = tabs.remove(at: currentIndex)
            pushClosed(ClosedTabSnapshot(url: removed.webView.url ?? removed.lastKnownURL))

            if tabs.isEmpty {
                currentIndex = -1
                delegate?.tabManager(self, didUpdateTabs: 0)
                delegate?.tabManager(self, didSelect: nil)
                return
            }

            currentIndex = min(currentIndex, tabs.count - 1)
            delegate?.tabManager(self, didUpdateTabs: tabs.count)
            delegate?.tabManager(self, didSelect: tabs[currentIndex].webView)
        }
    }

    func closeAllTabs() {
        performOnMain { [weak self] in
            guard let self else { return }

            for tab in tabs {
                pushClosed(ClosedTabSnapshot(url: tab.webView.url ?? tab.lastKnownURL))
            }

            tabs.removeAll()
            currentIndex = -1
            delegate?.tabManager(self, didUpdateTabs: 0)
            delegate?.tabManager(self, didSelect: nil)
        }
    }

    func reopenClosedTab() {
        performOnMain { [weak self] in
            guard let self, let snapshot = closedStack.popLast() else { return }
            newTab(url: snapshot.url)
        }
    }

    func reloadCurrentTab() {
        performOnMain { [weak self] in
            self?.currentWebView?.reload()
        }
    }

    func reloadAllTabs() {
        performOnMain { [weak self] in
            guard let self else { return }
            for tab in tabs {
                tab.webView.reload()
            }
        }
    }

    private func pushClosed(_ snapshot: ClosedTabSnapshot) {
        closedStack.append(snapshot)
        if closedStack.count > 20 {
            closedStack.removeFirst(closedStack.count - 20)
        }
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
