import AppKit
import Foundation
import WebKit

enum BrowserTabGroup: String, CaseIterable {
    case regular
    case privateMode
    case work
    case research

    var displayName: String {
        switch self {
        case .regular:
            return "通常タブグループ"
        case .privateMode:
            return "プライベートタブグループ"
        case .work:
            return "ワークタブグループ"
        case .research:
            return "リサーチタブグループ"
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
    let isBookmarked: Bool
    let thumbnail: NSImage?
}

final class TabManager {
    weak var delegate: TabManagerDelegate?

    private struct Tab {
        let webView: WKWebView
        var lastKnownURL: URL?
        var thumbnail: NSImage?
        var isProtected: Bool
        var isBookmarked: Bool
    }

    private struct GroupState {
        var tabs: [Tab] = []
        var currentIndex: Int = -1
    }

    private struct ClosedTabSnapshot {
        let group: BrowserTabGroup
        let url: URL?
    }

    private var states: [BrowserTabGroup: GroupState]
    private var closedStack: [ClosedTabSnapshot] = []

    private(set) var currentGroup: BrowserTabGroup = .regular

    init() {
        var map: [BrowserTabGroup: GroupState] = [:]
        for group in BrowserTabGroup.allCases {
            map[group] = GroupState()
        }
        states = map
    }

    var currentWebView: WKWebView? {
        webView(in: currentGroup, at: currentIndex)
    }

    var currentIndex: Int {
        state(for: currentGroup).currentIndex
    }

    var tabCount: Int {
        state(for: currentGroup).tabs.count
    }

    var canReopenClosedTab: Bool { !closedStack.isEmpty }

    var isCurrentTabProtected: Bool {
        let state = state(for: currentGroup)
        guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return false }
        return state.tabs[state.currentIndex].isProtected
    }

    var isCurrentTabBookmarked: Bool {
        let state = state(for: currentGroup)
        guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return false }
        return state.tabs[state.currentIndex].isBookmarked
    }

    var tabStripItems: [TabStripItem] {
        let state = state(for: currentGroup)
        return state.tabs.enumerated().map { index, tab in
            let resolvedURL = tab.webView.url ?? tab.lastKnownURL
            let fallbackTitle = resolvedURL?.host ?? resolvedURL?.absoluteString ?? "New Tab"
            let resolvedTitle = tab.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (resolvedTitle?.isEmpty == false) ? resolvedTitle! : fallbackTitle
            return TabStripItem(
                index: index,
                title: title,
                isActive: index == state.currentIndex,
                isProtected: tab.isProtected,
                isBookmarked: tab.isBookmarked,
                thumbnail: tab.thumbnail
            )
        }
    }

    func switchGroup(_ group: BrowserTabGroup) {
        performOnMain { [weak self] in
            guard let self else { return }
            switchGroupInternal(group, ensureTab: true)
            notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func group(for webView: WKWebView) -> BrowserTabGroup? {
        for group in BrowserTabGroup.allCases {
            let tabs = state(for: group).tabs
            if tabs.contains(where: { $0.webView === webView }) {
                return group
            }
        }
        return nil
    }

    func newTab(url: URL?) {
        newTab(url: url, in: currentGroup)
    }

    func newTab(url: URL?, in group: BrowserTabGroup) {
        let webView = BrowserSession.makeConfiguredWebView(for: group)
        addTab(
            webView: webView,
            initialURL: url,
            shouldLoadInitialURL: true,
            group: group,
            activate: true
        )
    }

    func openBackgroundTab(url: URL?, in group: BrowserTabGroup? = nil) {
        let targetGroup = group ?? currentGroup
        let webView = BrowserSession.makeConfiguredWebView(for: targetGroup)
        addTab(
            webView: webView,
            initialURL: url,
            shouldLoadInitialURL: true,
            group: targetGroup,
            activate: false
        )
    }

    @discardableResult
    func addTab(
        webView: WKWebView,
        initialURL: URL?,
        shouldLoadInitialURL: Bool,
        group: BrowserTabGroup? = nil,
        activate: Bool = true
    ) -> WKWebView {
        let work = { [weak self] in
            guard let self else { return }
            let targetGroup = group ?? self.currentGroup
            var state = self.state(for: targetGroup)
            var tab = Tab(
                webView: webView,
                lastKnownURL: initialURL,
                thumbnail: nil,
                isProtected: false,
                isBookmarked: false
            )
            state.tabs.append(tab)
            let insertedIndex = state.tabs.count - 1
            if activate || state.currentIndex < 0 {
                state.currentIndex = insertedIndex
            }

            if shouldLoadInitialURL, let targetURL = initialURL {
                webView.load(URLRequest(url: targetURL))
                tab.lastKnownURL = targetURL
                state.tabs[insertedIndex] = tab
            }

            self.setState(state, for: targetGroup)
            if activate {
                self.switchGroupInternal(targetGroup, ensureTab: false)
                self.notifyCurrentGroupUpdated(selectCurrent: true)
            } else if targetGroup == self.currentGroup {
                self.delegate?.tabManager(self, didUpdateTabs: state.tabs.count)
            }
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
            var state = state(for: currentGroup)
            guard index >= 0, index < state.tabs.count else { return }
            state.currentIndex = index
            setState(state, for: currentGroup)
            delegate?.tabManager(self, didSelect: state.tabs[index].webView)
            delegate?.tabManager(self, didUpdateTabs: state.tabs.count)
        }
    }

    func selectNextTab() {
        performOnMain { [weak self] in
            guard let self else { return }
            let state = state(for: currentGroup)
            guard !state.tabs.isEmpty else { return }
            let next = state.currentIndex + 1
            guard next < state.tabs.count else { return }
            selectTab(index: next)
        }
    }

    func webView(at index: Int) -> WKWebView? {
        webView(in: currentGroup, at: index)
    }

    func selectPrevTab() {
        performOnMain { [weak self] in
            guard let self else { return }
            let state = state(for: currentGroup)
            guard !state.tabs.isEmpty else { return }
            let previous = state.currentIndex - 1
            guard previous >= 0 else { return }
            selectTab(index: previous)
        }
    }

    func closeCurrentTab() {
        performOnMain { [weak self] in
            guard let self else { return }
            var state = state(for: currentGroup)
            guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return }

            let removed = state.tabs.remove(at: state.currentIndex)
            pushClosed(ClosedTabSnapshot(group: currentGroup, url: removed.webView.url ?? removed.lastKnownURL))

            if state.tabs.isEmpty {
                state.currentIndex = -1
                setState(state, for: currentGroup)
                ensureAtLeastOneTab(in: currentGroup)
                return
            }

            state.currentIndex = min(state.currentIndex, state.tabs.count - 1)
            setState(state, for: currentGroup)
            notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func closeAllTabs() {
        performOnMain { [weak self] in
            guard let self else { return }
            var state = state(for: currentGroup)
            let selectedWebView = currentWebView

            var retained: [Tab] = []
            for tab in state.tabs {
                if tab.isProtected {
                    retained.append(tab)
                } else {
                    pushClosed(ClosedTabSnapshot(group: currentGroup, url: tab.webView.url ?? tab.lastKnownURL))
                }
            }

            state.tabs = retained
            if state.tabs.isEmpty {
                state.currentIndex = -1
                setState(state, for: currentGroup)
                ensureAtLeastOneTab(in: currentGroup)
                return
            }

            if let selectedWebView,
               let retainedIndex = state.tabs.firstIndex(where: { $0.webView === selectedWebView }) {
                state.currentIndex = retainedIndex
            } else {
                state.currentIndex = 0
            }

            setState(state, for: currentGroup)
            notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func toggleProtection(index: Int) {
        performOnMain { [weak self] in
            guard let self else { return }
            var state = state(for: currentGroup)
            guard index >= 0, index < state.tabs.count else { return }
            state.tabs[index].isProtected.toggle()
            setState(state, for: currentGroup)
            notifyCurrentGroupUpdated(selectCurrent: false)
        }
    }

    func toggleCurrentTabBookmark() {
        performOnMain { [weak self] in
            guard let self else { return }
            var state = state(for: currentGroup)
            guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return }
            state.tabs[state.currentIndex].isBookmarked.toggle()
            setState(state, for: currentGroup)
            notifyCurrentGroupUpdated(selectCurrent: false)
        }
    }

    func moveTab(from fromIndex: Int, to toIndex: Int) {
        performOnMain { [weak self] in
            guard let self else { return }
            var state = state(for: currentGroup)
            guard fromIndex >= 0, fromIndex < state.tabs.count else { return }
            guard toIndex >= 0, toIndex < state.tabs.count else { return }
            guard fromIndex != toIndex else { return }

            let moved = state.tabs.remove(at: fromIndex)
            state.tabs.insert(moved, at: toIndex)

            if state.currentIndex == fromIndex {
                state.currentIndex = toIndex
            } else if fromIndex < state.currentIndex, toIndex >= state.currentIndex {
                state.currentIndex -= 1
            } else if fromIndex > state.currentIndex, toIndex <= state.currentIndex {
                state.currentIndex += 1
            }

            setState(state, for: currentGroup)
            notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func reopenClosedTab() {
        performOnMain { [weak self] in
            guard let self, let snapshot = closedStack.popLast() else { return }
            switchGroupInternal(snapshot.group, ensureTab: false)
            newTab(url: snapshot.url, in: snapshot.group)
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
            let state = state(for: currentGroup)
            for tab in state.tabs {
                tab.webView.reload()
            }
        }
    }

    func reconfigureAllTabsForCurrentPreferences() {
        performOnMain { [weak self] in
            guard let self else { return }
            for group in BrowserTabGroup.allCases {
                reconfigureTabs(in: group)
            }
            ensureAtLeastOneTab(in: currentGroup)
            notifyCurrentGroupUpdated(selectCurrent: true)
        }
    }

    func updateMetadata(for webView: WKWebView) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard let (group, index) = findTabIndex(for: webView) else { return }
            var state = state(for: group)
            state.tabs[index].lastKnownURL = webView.url
            setState(state, for: group)
            if group == currentGroup {
                notifyCurrentGroupUpdated(selectCurrent: false)
            }
        }
    }

    func updateThumbnail(for webView: WKWebView, image: NSImage?) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard let (group, index) = findTabIndex(for: webView) else { return }
            var state = state(for: group)
            state.tabs[index].thumbnail = image
            setState(state, for: group)
            if group == currentGroup {
                notifyCurrentGroupUpdated(selectCurrent: false)
            }
        }
    }

    private func reconfigureTabs(in group: BrowserTabGroup) {
        var state = state(for: group)
        guard !state.tabs.isEmpty else { return }

        let selectedIndex = state.currentIndex
        let snapshots = state.tabs.map { tab in
            (
                url: tab.webView.url ?? tab.lastKnownURL,
                isProtected: tab.isProtected,
                isBookmarked: tab.isBookmarked
            )
        }

        state.tabs = snapshots.map { snapshot in
            let webView = BrowserSession.makeConfiguredWebView(for: group)
            if let url = snapshot.url {
                webView.load(URLRequest(url: url))
            }
            return Tab(
                webView: webView,
                lastKnownURL: snapshot.url,
                thumbnail: nil,
                isProtected: snapshot.isProtected,
                isBookmarked: snapshot.isBookmarked
            )
        }
        state.currentIndex = min(max(0, selectedIndex), state.tabs.count - 1)
        setState(state, for: group)
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
        let state = state(for: group)
        guard state.tabs.isEmpty else { return }
        newTab(url: BrowserSession.defaultHomeURL, in: group)
    }

    private func notifyCurrentGroupUpdated(selectCurrent: Bool) {
        let state = state(for: currentGroup)
        delegate?.tabManager(self, didUpdateTabs: state.tabs.count)
        if selectCurrent {
            delegate?.tabManager(self, didSelect: currentWebView)
        }
    }

    private func state(for group: BrowserTabGroup) -> GroupState {
        states[group] ?? GroupState()
    }

    private func setState(_ state: GroupState, for group: BrowserTabGroup) {
        states[group] = state
    }

    private func webView(in group: BrowserTabGroup, at index: Int) -> WKWebView? {
        let state = state(for: group)
        guard index >= 0, index < state.tabs.count else { return nil }
        return state.tabs[index].webView
    }

    private func findTabIndex(for webView: WKWebView) -> (BrowserTabGroup, Int)? {
        for group in BrowserTabGroup.allCases {
            let tabs = state(for: group).tabs
            if let index = tabs.firstIndex(where: { $0.webView === webView }) {
                return (group, index)
            }
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
