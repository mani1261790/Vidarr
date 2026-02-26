import AppKit
import Foundation
import WebKit

enum BrowserTabGroup: String, CaseIterable {
    case regular
    case privateMode

    var displayName: String {
        switch self {
        case .regular:
            return "通常タブグループ"
        case .privateMode:
            return "プライベートタブグループ"
        }
    }
}

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
        let group: BrowserTabGroup
        let url: URL?
    }

    private var regularTabs: [Tab] = []
    private var privateTabs: [Tab] = []
    private var regularCurrentIndex: Int = -1
    private var privateCurrentIndex: Int = -1

    private var closedStack: [ClosedTabSnapshot] = []

    private(set) var currentGroup: BrowserTabGroup = .regular

    var currentWebView: WKWebView? {
        webView(in: currentGroup, at: currentIndex)
    }

    var currentIndex: Int {
        switch currentGroup {
        case .regular: return regularCurrentIndex
        case .privateMode: return privateCurrentIndex
        }
    }

    var tabCount: Int {
        tabs(in: currentGroup).count
    }

    var canReopenClosedTab: Bool { !closedStack.isEmpty }

    var isCurrentTabProtected: Bool {
        let tabs = tabs(in: currentGroup)
        let index = currentIndex
        guard index >= 0, index < tabs.count else { return false }
        return tabs[index].isProtected
    }

    var tabStripItems: [TabStripItem] {
        let tabs = tabs(in: currentGroup)
        let selectedIndex = currentIndex

        return tabs.enumerated().map { index, tab in
            let resolvedURL = tab.webView.url ?? tab.lastKnownURL
            let fallbackTitle = resolvedURL?.host ?? resolvedURL?.absoluteString ?? "New Tab"
            let resolvedTitle = tab.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (resolvedTitle?.isEmpty == false) ? resolvedTitle! : fallbackTitle
            return TabStripItem(
                index: index,
                title: title,
                isActive: index == selectedIndex,
                isProtected: tab.isProtected,
                thumbnail: tab.thumbnail
            )
        }
    }

    func switchGroup(_ group: BrowserTabGroup) {
        performOnMain { [weak self] in
            guard let self else { return }
            self.switchGroupInternal(group, ensureTab: true)
            self.notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func group(for webView: WKWebView) -> BrowserTabGroup? {
        if regularTabs.contains(where: { $0.webView === webView }) { return .regular }
        if privateTabs.contains(where: { $0.webView === webView }) { return .privateMode }
        return nil
    }

    func newTab(url: URL?) {
        newTab(url: url, in: currentGroup)
    }

    func newTab(url: URL?, in group: BrowserTabGroup) {
        let webView = BrowserSession.makeConfiguredWebView(for: group)
        addTab(webView: webView, initialURL: url, shouldLoadInitialURL: true, group: group)
    }

    @discardableResult
    func addTab(
        webView: WKWebView,
        initialURL: URL?,
        shouldLoadInitialURL: Bool,
        group: BrowserTabGroup? = nil
    ) -> WKWebView {
        let work = { [weak self] in
            guard let self else { return }
            let targetGroup = group ?? self.currentGroup
            var tab = Tab(webView: webView, lastKnownURL: initialURL, thumbnail: nil, isProtected: false)
            self.appendTab(tab, in: targetGroup)
            let newIndex = self.tabs(in: targetGroup).count - 1
            self.setCurrentIndex(newIndex, in: targetGroup)

            if shouldLoadInitialURL, let targetURL = initialURL {
                webView.load(URLRequest(url: targetURL))
                tab.lastKnownURL = targetURL
                self.replaceTab(at: newIndex, in: targetGroup, with: tab)
            }

            self.switchGroupInternal(targetGroup, ensureTab: false)
            self.notifyCurrentGroupUpdated(selectCurrent: true)
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
        return webView
    }

    func selectTab(index: Int) {
        performOnMain { [weak self] in
            guard let self else { return }
            let tabs = self.tabs(in: self.currentGroup)
            guard index >= 0, index < tabs.count else { return }
            self.setCurrentIndex(index, in: self.currentGroup)
            self.delegate?.tabManager(self, didSelect: tabs[index].webView)
            self.delegate?.tabManager(self, didUpdateTabs: tabs.count)
        }
    }

    func selectNextTab() {
        performOnMain { [weak self] in
            guard let self else { return }
            let tabs = self.tabs(in: self.currentGroup)
            guard !tabs.isEmpty else { return }
            let next = self.currentIndex + 1
            guard next < tabs.count else { return }
            self.selectTab(index: next)
        }
    }

    func webView(at index: Int) -> WKWebView? {
        webView(in: currentGroup, at: index)
    }

    func selectPrevTab() {
        performOnMain { [weak self] in
            guard let self else { return }
            let tabs = self.tabs(in: self.currentGroup)
            guard !tabs.isEmpty else { return }
            let previous = self.currentIndex - 1
            guard previous >= 0 else { return }
            self.selectTab(index: previous)
        }
    }

    func closeCurrentTab() {
        performOnMain { [weak self] in
            guard let self else { return }
            var tabs = self.tabs(in: self.currentGroup)
            var selectedIndex = self.currentIndex
            guard selectedIndex >= 0, selectedIndex < tabs.count else { return }

            let removed = tabs.remove(at: selectedIndex)
            self.pushClosed(ClosedTabSnapshot(group: self.currentGroup, url: removed.webView.url ?? removed.lastKnownURL))
            self.setTabs(tabs, in: self.currentGroup)

            if tabs.isEmpty {
                self.ensureAtLeastOneTab(in: self.currentGroup)
                self.notifyCurrentGroupUpdated(selectCurrent: true)
                return
            }

            selectedIndex = min(selectedIndex, tabs.count - 1)
            self.setCurrentIndex(selectedIndex, in: self.currentGroup)
            self.notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func closeAllTabs() {
        performOnMain { [weak self] in
            guard let self else { return }

            let selectedWebView = self.currentWebView
            var tabs = self.tabs(in: self.currentGroup)
            var retained: [Tab] = []
            for tab in tabs {
                if tab.isProtected {
                    retained.append(tab)
                } else {
                    self.pushClosed(ClosedTabSnapshot(group: self.currentGroup, url: tab.webView.url ?? tab.lastKnownURL))
                }
            }
            tabs = retained
            self.setTabs(tabs, in: self.currentGroup)

            if tabs.isEmpty {
                self.ensureAtLeastOneTab(in: self.currentGroup)
                self.notifyCurrentGroupUpdated(selectCurrent: true)
                return
            }

            if let selectedWebView,
               let retainedIndex = tabs.firstIndex(where: { $0.webView === selectedWebView }) {
                self.setCurrentIndex(retainedIndex, in: self.currentGroup)
            } else {
                self.setCurrentIndex(0, in: self.currentGroup)
            }

            self.notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func toggleProtection(index: Int) {
        performOnMain { [weak self] in
            guard let self else { return }
            var tabs = self.tabs(in: self.currentGroup)
            guard index >= 0, index < tabs.count else { return }
            tabs[index].isProtected.toggle()
            self.setTabs(tabs, in: self.currentGroup)
            self.notifyCurrentGroupUpdated(selectCurrent: false)
        }
    }

    func moveTab(from fromIndex: Int, to toIndex: Int) {
        performOnMain { [weak self] in
            guard let self else { return }
            var tabs = self.tabs(in: self.currentGroup)
            var selectedIndex = self.currentIndex
            guard fromIndex >= 0, fromIndex < tabs.count else { return }
            guard toIndex >= 0, toIndex < tabs.count else { return }
            guard fromIndex != toIndex else { return }

            let moved = tabs.remove(at: fromIndex)
            tabs.insert(moved, at: toIndex)

            if selectedIndex == fromIndex {
                selectedIndex = toIndex
            } else if fromIndex < selectedIndex, toIndex >= selectedIndex {
                selectedIndex -= 1
            } else if fromIndex > selectedIndex, toIndex <= selectedIndex {
                selectedIndex += 1
            }

            self.setTabs(tabs, in: self.currentGroup)
            self.setCurrentIndex(selectedIndex, in: self.currentGroup)
            self.notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func reopenClosedTab() {
        performOnMain { [weak self] in
            guard let self, let snapshot = self.closedStack.popLast() else { return }
            self.switchGroupInternal(snapshot.group, ensureTab: false)
            self.newTab(url: snapshot.url, in: snapshot.group)
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
            for tab in self.tabs(in: self.currentGroup) {
                tab.webView.reload()
            }
        }
    }

    func reconfigureAllTabsForCurrentPreferences() {
        performOnMain { [weak self] in
            guard let self else { return }
            self.reconfigureTabs(in: .regular)
            self.reconfigureTabs(in: .privateMode)
            self.ensureAtLeastOneTab(in: self.currentGroup)
            self.notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func updateMetadata(for webView: WKWebView) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard let (group, index) = self.findTabIndex(for: webView) else { return }
            var tabs = self.tabs(in: group)
            tabs[index].lastKnownURL = webView.url
            self.setTabs(tabs, in: group)
            if group == self.currentGroup {
                self.notifyCurrentGroupUpdated(selectCurrent: false)
            }
        }
    }

    func updateThumbnail(for webView: WKWebView, image: NSImage?) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard let (group, index) = self.findTabIndex(for: webView) else { return }
            var tabs = self.tabs(in: group)
            tabs[index].thumbnail = image
            self.setTabs(tabs, in: group)
            if group == self.currentGroup {
                self.notifyCurrentGroupUpdated(selectCurrent: false)
            }
        }
    }

    private func reconfigureTabs(in group: BrowserTabGroup) {
        let currentTabs = tabs(in: group)
        guard !currentTabs.isEmpty else { return }

        let selectedIndex = currentIndex(in: group)
        let snapshots = currentTabs.map { tab in
            (
                url: tab.webView.url ?? tab.lastKnownURL,
                isProtected: tab.isProtected
            )
        }

        let rebuilt = snapshots.map { snapshot -> Tab in
            let webView = BrowserSession.makeConfiguredWebView(for: group)
            if let url = snapshot.url {
                webView.load(URLRequest(url: url))
            }
            return Tab(
                webView: webView,
                lastKnownURL: snapshot.url,
                thumbnail: nil,
                isProtected: snapshot.isProtected
            )
        }

        setTabs(rebuilt, in: group)
        setCurrentIndex(min(max(0, selectedIndex), rebuilt.count - 1), in: group)
    }

    private func pushClosed(_ snapshot: ClosedTabSnapshot) {
        closedStack.append(snapshot)
        if closedStack.count > 20 {
            closedStack.removeFirst(closedStack.count - 20)
        }
    }

    private func switchGroupInternal(_ group: BrowserTabGroup, ensureTab: Bool) {
        currentGroup = group
        if ensureTab {
            ensureAtLeastOneTab(in: group)
        }
    }

    private func ensureAtLeastOneTab(in group: BrowserTabGroup) {
        guard tabs(in: group).isEmpty else { return }
        newTab(url: BrowserSession.defaultHomeURL, in: group)
    }

    private func notifyCurrentGroupUpdated(selectCurrent: Bool) {
        let tabs = self.tabs(in: currentGroup)
        delegate?.tabManager(self, didUpdateTabs: tabs.count)
        if selectCurrent {
            delegate?.tabManager(self, didSelect: currentWebView)
        }
    }

    private func tabs(in group: BrowserTabGroup) -> [Tab] {
        switch group {
        case .regular: return regularTabs
        case .privateMode: return privateTabs
        }
    }

    private func setTabs(_ tabs: [Tab], in group: BrowserTabGroup) {
        switch group {
        case .regular: regularTabs = tabs
        case .privateMode: privateTabs = tabs
        }
    }

    private func appendTab(_ tab: Tab, in group: BrowserTabGroup) {
        switch group {
        case .regular: regularTabs.append(tab)
        case .privateMode: privateTabs.append(tab)
        }
    }

    private func replaceTab(at index: Int, in group: BrowserTabGroup, with tab: Tab) {
        switch group {
        case .regular: regularTabs[index] = tab
        case .privateMode: privateTabs[index] = tab
        }
    }

    private func currentIndex(in group: BrowserTabGroup) -> Int {
        switch group {
        case .regular: return regularCurrentIndex
        case .privateMode: return privateCurrentIndex
        }
    }

    private func setCurrentIndex(_ index: Int, in group: BrowserTabGroup) {
        switch group {
        case .regular: regularCurrentIndex = index
        case .privateMode: privateCurrentIndex = index
        }
    }

    private func webView(in group: BrowserTabGroup, at index: Int) -> WKWebView? {
        let tabs = tabs(in: group)
        guard index >= 0, index < tabs.count else { return nil }
        return tabs[index].webView
    }

    private func findTabIndex(for webView: WKWebView) -> (BrowserTabGroup, Int)? {
        if let index = regularTabs.firstIndex(where: { $0.webView === webView }) {
            return (.regular, index)
        }
        if let index = privateTabs.firstIndex(where: { $0.webView === webView }) {
            return (.privateMode, index)
        }
        return nil
    }

    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
