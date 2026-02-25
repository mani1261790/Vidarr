import AppKit
import Foundation
import WebKit

protocol TabManagerDelegate: AnyObject {
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?)
    func tabManager(_ manager: TabManager, didUpdateTabs count: Int)
}

struct TabStripItem {
    let index: Int
    let title: String
    let isActive: Bool
    let isProtected: Bool
    let thumbnail: NSImage?
}

final class TabManager {
    weak var delegate: TabManagerDelegate?

    private struct Tab {
        let webView: WKWebView
        var lastKnownURL: URL?
        var thumbnail: NSImage?
        var isProtected: Bool
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

    var isCurrentTabProtected: Bool {
        guard currentIndex >= 0, currentIndex < tabs.count else { return false }
        return tabs[currentIndex].isProtected
    }

    var tabStripItems: [TabStripItem] {
        tabs.enumerated().map { index, tab in
            let resolvedURL = tab.webView.url ?? tab.lastKnownURL
            let fallbackTitle = resolvedURL?.host ?? resolvedURL?.absoluteString ?? "New Tab"
            let resolvedTitle = tab.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (resolvedTitle?.isEmpty == false) ? resolvedTitle! : fallbackTitle
            return TabStripItem(
                index: index,
                title: title,
                isActive: index == currentIndex,
                isProtected: tab.isProtected,
                thumbnail: tab.thumbnail
            )
        }
    }

    func newTab(url: URL?) {
        performOnMain { [weak self] in
            guard let self else { return }

            let webView = BrowserSession.makeConfiguredWebView()
            var tab = Tab(webView: webView, lastKnownURL: nil, thumbnail: nil, isProtected: false)
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

    func webView(at index: Int) -> WKWebView? {
        guard index >= 0, index < tabs.count else { return nil }
        return tabs[index].webView
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
                ensureAtLeastOneTab()
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

            let selectedWebView = currentWebView
            var retained: [Tab] = []
            for tab in tabs {
                if tab.isProtected {
                    retained.append(tab)
                } else {
                    pushClosed(ClosedTabSnapshot(url: tab.webView.url ?? tab.lastKnownURL))
                }
            }

            tabs = retained

            if tabs.isEmpty {
                ensureAtLeastOneTab()
                return
            }

            if let selectedWebView,
               let retainedIndex = tabs.firstIndex(where: { $0.webView === selectedWebView }) {
                currentIndex = retainedIndex
            } else {
                currentIndex = 0
            }
            delegate?.tabManager(self, didUpdateTabs: tabs.count)
            delegate?.tabManager(self, didSelect: tabs[currentIndex].webView)
        }
    }

    func toggleProtection(index: Int) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard index >= 0, index < tabs.count else { return }
            tabs[index].isProtected.toggle()
            delegate?.tabManager(self, didUpdateTabs: tabs.count)
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

    func updateMetadata(for webView: WKWebView) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard let index = tabs.firstIndex(where: { $0.webView === webView }) else { return }
            tabs[index].lastKnownURL = webView.url
            delegate?.tabManager(self, didUpdateTabs: tabs.count)
        }
    }

    func updateThumbnail(for webView: WKWebView, image: NSImage?) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard let index = tabs.firstIndex(where: { $0.webView === webView }) else { return }
            tabs[index].thumbnail = image
            delegate?.tabManager(self, didUpdateTabs: tabs.count)
        }
    }

    private func pushClosed(_ snapshot: ClosedTabSnapshot) {
        closedStack.append(snapshot)
        if closedStack.count > 20 {
            closedStack.removeFirst(closedStack.count - 20)
        }
    }

    private func ensureAtLeastOneTab() {
        guard tabs.isEmpty else { return }
        newTab(url: BrowserSession.defaultHomeURL)
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
