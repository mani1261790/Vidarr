import AppKit
import Foundation
import WebKit

enum BrowserTabGroup: String, CaseIterable, Codable {
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

struct TabSessionSnapshot: Codable {
    let urlString: String?
    let isProtected: Bool
    let isBookmarked: Bool
    let pageZoom: Double
    let historyURLStrings: [String]
    let historyIndex: Int

    private enum CodingKeys: String, CodingKey {
        case urlString
        case isProtected
        case isBookmarked
        case pageZoom
        case historyURLStrings
        case historyIndex
    }

    init(
        urlString: String?,
        isProtected: Bool,
        isBookmarked: Bool,
        pageZoom: Double,
        historyURLStrings: [String],
        historyIndex: Int
    ) {
        self.urlString = urlString
        self.isProtected = isProtected
        self.isBookmarked = isBookmarked
        self.pageZoom = pageZoom
        self.historyURLStrings = historyURLStrings
        self.historyIndex = historyIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        isProtected = try container.decode(Bool.self, forKey: .isProtected)
        isBookmarked = try container.decode(Bool.self, forKey: .isBookmarked)
        pageZoom = try container.decode(Double.self, forKey: .pageZoom)
        historyURLStrings = try container.decodeIfPresent([String].self, forKey: .historyURLStrings) ?? []
        historyIndex = try container.decodeIfPresent(Int.self, forKey: .historyIndex) ?? -1
    }
}

struct TabGroupSessionSnapshot: Codable {
    let group: BrowserTabGroup
    let currentIndex: Int
    let tabs: [TabSessionSnapshot]
}

struct BrowserSessionSnapshot: Codable {
    let currentGroup: BrowserTabGroup
    let groups: [TabGroupSessionSnapshot]
}

final class TabManager {
    weak var delegate: TabManagerDelegate?

    private struct Tab {
        let webView: WKWebView
        var lastKnownURL: URL?
        var thumbnail: NSImage?
        var isProtected: Bool
        var isBookmarked: Bool
        var pageZoom: Double
        var historyURLs: [URL]
        var historyIndex: Int
        var pendingHistoryIndex: Int?
    }

    private struct GroupState {
        var tabs: [Tab] = []
        var currentIndex: Int = -1
    }

    private struct ClosedTabSnapshot {
        let group: BrowserTabGroup
        let url: URL?
        let isProtected: Bool
        let isBookmarked: Bool
        let pageZoom: Double
        let historyURLs: [URL]
        let historyIndex: Int
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
        activate: Bool = true,
        isProtected: Bool = false,
        isBookmarked: Bool = false,
        pageZoom: Double = 1.0,
        historyURLs: [URL]? = nil,
        historyIndex: Int? = nil
    ) -> WKWebView {
        let work = { [weak self] in
            guard let self else { return }
            let targetGroup = group ?? self.currentGroup
            var state = self.state(for: targetGroup)
            let resolvedHistory = ((historyURLs?.isEmpty == false) ? historyURLs : nil) ?? initialURL.map { [$0] } ?? []
            let resolvedHistoryIndex = min(
                max(historyIndex ?? (resolvedHistory.isEmpty ? -1 : resolvedHistory.count - 1), -1),
                max(resolvedHistory.count - 1, -1)
            )
            var tab = Tab(
                webView: webView,
                lastKnownURL: initialURL,
                thumbnail: nil,
                isProtected: isProtected,
                isBookmarked: isBookmarked,
                pageZoom: pageZoom,
                historyURLs: resolvedHistory,
                historyIndex: resolvedHistoryIndex,
                pendingHistoryIndex: nil
            )
            state.tabs.append(tab)
            let insertedIndex = state.tabs.count - 1
            if activate || state.currentIndex < 0 {
                state.currentIndex = insertedIndex
            }

            webView.pageZoom = pageZoom

            if shouldLoadInitialURL, let targetURL = initialURL {
                BrowserSession.load(url: targetURL, in: webView)
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
            pushClosed(
                ClosedTabSnapshot(
                    group: currentGroup,
                    url: removed.webView.url ?? removed.lastKnownURL,
                    isProtected: removed.isProtected,
                    isBookmarked: removed.isBookmarked,
                    pageZoom: removed.pageZoom,
                    historyURLs: BrowserPreferences.shared.restoreClosedTabPageHistory ? removed.historyURLs : [],
                    historyIndex: BrowserPreferences.shared.restoreClosedTabPageHistory ? removed.historyIndex : -1
                )
            )

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
                    pushClosed(
                        ClosedTabSnapshot(
                            group: currentGroup,
                            url: tab.webView.url ?? tab.lastKnownURL,
                            isProtected: tab.isProtected,
                            isBookmarked: tab.isBookmarked,
                            pageZoom: tab.pageZoom,
                            historyURLs: BrowserPreferences.shared.restoreClosedTabPageHistory ? tab.historyURLs : [],
                            historyIndex: BrowserPreferences.shared.restoreClosedTabPageHistory ? tab.historyIndex : -1
                        )
                    )
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

    func syncBookmarkedStates(bookmarkedURLStrings: Set<String>) {
        performOnMain { [weak self] in
            guard let self else { return }
            var didChangeCurrentGroup = false

            for group in BrowserTabGroup.allCases {
                var state = state(for: group)
                var didChangeGroup = false

                for index in state.tabs.indices {
                    let currentURLString = (state.tabs[index].webView.url ?? state.tabs[index].lastKnownURL)?.absoluteString
                    let shouldBeBookmarked = currentURLString.map { bookmarkedURLStrings.contains($0) } ?? false
                    if state.tabs[index].isBookmarked != shouldBeBookmarked {
                        state.tabs[index].isBookmarked = shouldBeBookmarked
                        didChangeGroup = true
                    }
                }

                if didChangeGroup {
                    setState(state, for: group)
                    if group == currentGroup {
                        didChangeCurrentGroup = true
                    }
                }
            }

            if didChangeCurrentGroup {
                notifyCurrentGroupUpdated(selectCurrent: false)
            }
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
            let webView = BrowserSession.makeConfiguredWebView(for: snapshot.group)
            _ = addTab(
                webView: webView,
                initialURL: snapshot.url,
                shouldLoadInitialURL: true,
                group: snapshot.group,
                activate: true,
                isProtected: snapshot.isProtected,
                isBookmarked: snapshot.isBookmarked,
                pageZoom: snapshot.pageZoom,
                historyURLs: snapshot.historyURLs,
                historyIndex: snapshot.historyIndex
            )
        }
    }

    func reloadCurrentTab() {
        performOnMain { [weak self] in
            self?.currentWebView?.reload()
        }
    }

    var canCurrentTabGoBack: Bool {
        let state = state(for: currentGroup)
        guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return false }
        let tab = state.tabs[state.currentIndex]
        return tab.webView.canGoBack || tab.historyIndex > 0
    }

    var canCurrentTabGoForward: Bool {
        let state = state(for: currentGroup)
        guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return false }
        let tab = state.tabs[state.currentIndex]
        return tab.webView.canGoForward || tab.historyIndex >= 0 && tab.historyIndex < tab.historyURLs.count - 1
    }

    func navigateCurrentHistoryBack() {
        performOnMain { [weak self] in
            guard let self else { return }
            guard var state = optionalStateForCurrentIndex() else { return }
            let index = state.currentIndex
            guard state.tabs[index].historyIndex > 0 else { return }
            let targetIndex = state.tabs[index].historyIndex - 1
            let url = state.tabs[index].historyURLs[targetIndex]
            state.tabs[index].pendingHistoryIndex = targetIndex
            setState(state, for: currentGroup)
            BrowserSession.load(url: url, in: state.tabs[index].webView)
        }
    }

    func navigateCurrentHistoryForward() {
        performOnMain { [weak self] in
            guard let self else { return }
            guard var state = optionalStateForCurrentIndex() else { return }
            let index = state.currentIndex
            guard state.tabs[index].historyIndex >= 0, state.tabs[index].historyIndex < state.tabs[index].historyURLs.count - 1 else { return }
            let targetIndex = state.tabs[index].historyIndex + 1
            let url = state.tabs[index].historyURLs[targetIndex]
            state.tabs[index].pendingHistoryIndex = targetIndex
            setState(state, for: currentGroup)
            BrowserSession.load(url: url, in: state.tabs[index].webView)
        }
    }

    func reloadAllTabs() {
        performOnMain { [weak self] in
            guard let self else { return }
            for group in BrowserTabGroup.allCases {
                let state = state(for: group)
                for tab in state.tabs {
                    if let url = tab.webView.url ?? tab.lastKnownURL {
                        BrowserSession.load(url: url, in: tab.webView)
                    } else {
                        tab.webView.reload()
                    }
                }
            }
        }
    }

    var currentPageZoom: Double {
        let state = state(for: currentGroup)
        guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return 1.0 }
        return state.tabs[state.currentIndex].pageZoom
    }

    func setCurrentPageZoom(_ zoom: Double) {
        performOnMain { [weak self] in
            guard let self else { return }
            var state = state(for: currentGroup)
            guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return }
            let clamped = min(3.0, max(0.5, zoom))
            state.tabs[state.currentIndex].pageZoom = clamped
            state.tabs[state.currentIndex].webView.pageZoom = clamped
            setState(state, for: currentGroup)
        }
    }

    func sessionSnapshot() -> BrowserSessionSnapshot {
        let groups = BrowserTabGroup.allCases.compactMap { group -> TabGroupSessionSnapshot? in
            guard group != .privateMode else { return nil }
            let state = state(for: group)
            return TabGroupSessionSnapshot(
                group: group,
                currentIndex: state.currentIndex,
                tabs: state.tabs.map { tab in
                    TabSessionSnapshot(
                        urlString: (tab.webView.url ?? tab.lastKnownURL)?.absoluteString,
                        isProtected: tab.isProtected,
                        isBookmarked: tab.isBookmarked,
                        pageZoom: tab.pageZoom,
                        historyURLStrings: tab.historyURLs.map(\.absoluteString),
                        historyIndex: tab.historyIndex
                    )
                }
            )
        }
        let persistedCurrentGroup: BrowserTabGroup = currentGroup == .privateMode ? .regular : currentGroup
        return BrowserSessionSnapshot(currentGroup: persistedCurrentGroup, groups: groups)
    }

    func restoreSession(from snapshot: BrowserSessionSnapshot) {
        performOnMain { [weak self] in
            guard let self else { return }

            var rebuilt: [BrowserTabGroup: GroupState] = [:]
            for group in BrowserTabGroup.allCases {
                rebuilt[group] = GroupState()
            }

            for groupSnapshot in snapshot.groups where groupSnapshot.group != .privateMode {
                var state = GroupState()
                state.tabs = groupSnapshot.tabs.map { snapshot in
                    let webView = BrowserSession.makeConfiguredWebView(for: groupSnapshot.group)
                    let resolvedURL = snapshot.urlString.flatMap(URL.init(string:))
                    if let resolvedURL {
                        BrowserSession.load(url: resolvedURL, in: webView)
                    }
                    webView.pageZoom = snapshot.pageZoom
                    return Tab(
                        webView: webView,
                        lastKnownURL: resolvedURL,
                        thumbnail: nil,
                        isProtected: snapshot.isProtected,
                        isBookmarked: snapshot.isBookmarked,
                        pageZoom: snapshot.pageZoom,
                        historyURLs: snapshot.historyURLStrings.compactMap(URL.init(string:)),
                        historyIndex: min(
                            max(-1, snapshot.historyIndex),
                            max(snapshot.historyURLStrings.count - 1, -1)
                        ),
                        pendingHistoryIndex: nil
                    )
                }
                if state.tabs.isEmpty {
                    state.currentIndex = -1
                } else {
                    state.currentIndex = min(max(0, groupSnapshot.currentIndex), state.tabs.count - 1)
                }
                rebuilt[groupSnapshot.group] = state
            }

            states = rebuilt
            let safeGroup = snapshot.currentGroup == .privateMode ? .regular : snapshot.currentGroup
            switchGroupInternal(safeGroup, ensureTab: true)
            notifyCurrentGroupUpdated(selectCurrent: true)
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
            if let url = webView.url {
                if let pendingIndex = state.tabs[index].pendingHistoryIndex,
                   pendingIndex >= 0,
                   pendingIndex < state.tabs[index].historyURLs.count,
                   state.tabs[index].historyURLs[pendingIndex] == url {
                    state.tabs[index].historyIndex = pendingIndex
                    state.tabs[index].pendingHistoryIndex = nil
                } else {
                    let currentIndex = state.tabs[index].historyIndex
                    let history = state.tabs[index].historyURLs
                    if currentIndex >= 0, currentIndex < history.count, history[currentIndex] == url {
                        state.tabs[index].pendingHistoryIndex = nil
                    } else if currentIndex > 0, history[currentIndex - 1] == url {
                        state.tabs[index].historyIndex = currentIndex - 1
                        state.tabs[index].pendingHistoryIndex = nil
                    } else if currentIndex >= 0, currentIndex + 1 < history.count, history[currentIndex + 1] == url {
                        state.tabs[index].historyIndex = currentIndex + 1
                        state.tabs[index].pendingHistoryIndex = nil
                    } else {
                        var nextHistory = history
                        let nextIndex = max(currentIndex, -1)
                        if nextIndex + 1 < nextHistory.count {
                            nextHistory.removeSubrange((nextIndex + 1)..<nextHistory.count)
                        }
                        if nextHistory.last != url {
                            nextHistory.append(url)
                        }
                        state.tabs[index].historyURLs = Array(nextHistory.suffix(50))
                        state.tabs[index].historyIndex = state.tabs[index].historyURLs.count - 1
                        state.tabs[index].pendingHistoryIndex = nil
                    }
                }
            }
            if let urlString = (webView.url ?? state.tabs[index].lastKnownURL)?.absoluteString {
                state.tabs[index].isBookmarked = BookmarkStore.shared.contains(urlString: urlString)
            } else {
                state.tabs[index].isBookmarked = false
            }
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
                isBookmarked: tab.isBookmarked,
                pageZoom: tab.pageZoom,
                historyURLs: tab.historyURLs,
                historyIndex: tab.historyIndex
            )
        }

        state.tabs = snapshots.map { snapshot in
            let webView = BrowserSession.makeConfiguredWebView(for: group)
            if let url = snapshot.url {
                BrowserSession.load(url: url, in: webView)
            }
            webView.pageZoom = snapshot.pageZoom
            return Tab(
                webView: webView,
                lastKnownURL: snapshot.url,
                thumbnail: nil,
                isProtected: snapshot.isProtected,
                isBookmarked: snapshot.isBookmarked,
                pageZoom: snapshot.pageZoom,
                historyURLs: snapshot.historyURLs,
                historyIndex: snapshot.historyIndex,
                pendingHistoryIndex: nil
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

    private func optionalStateForCurrentIndex() -> GroupState? {
        let state = state(for: currentGroup)
        guard state.currentIndex >= 0, state.currentIndex < state.tabs.count else { return nil }
        return state
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
