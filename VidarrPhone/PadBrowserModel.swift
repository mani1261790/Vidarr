import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

enum PadBrowserTabGroup: String, CaseIterable, Codable, Identifiable {
    case regular
    case privateMode
    case work
    case research

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regular: return "通常"
        case .privateMode: return "プライベート"
        case .work: return "ワーク"
        case .research: return "リサーチ"
        }
    }

    var systemImage: String {
        switch self {
        case .regular: return "square.grid.3x3"
        case .privateMode: return "hand.raised.fill"
        case .work: return "briefcase.fill"
        case .research: return "book.closed.fill"
        }
    }

    var accentColor: UIColor {
        switch self {
        case .regular:
            return .systemBlue
        case .privateMode:
            return UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1)
        case .work:
            return UIColor(red: 0.07, green: 0.67, blue: 0.53, alpha: 1)
        case .research:
            return UIColor(red: 0.15, green: 0.55, blue: 0.98, alpha: 1)
        }
    }
}

@MainActor
final class PadBrowserModel: NSObject, ObservableObject {
    struct HarmfulSitePrompt: Identifiable {
        let id = UUID()
        let url: URL
        let host: String
        let title: String
        let message: String
    }

    private struct SessionTabSnapshot: Codable {
        let urlString: String?
        let title: String
        let isProtected: Bool
        let historyURLStrings: [String]
        let historyIndex: Int
    }

    private struct GroupSessionSnapshot: Codable {
        let group: PadBrowserTabGroup
        let selectedIndex: Int
        let tabs: [SessionTabSnapshot]
    }

    private struct SessionSnapshot: Codable {
        let currentGroup: PadBrowserTabGroup
        let groups: [GroupSessionSnapshot]
    }

    final class Tab: NSObject, Identifiable, ObservableObject {
        let id = UUID()
        let webView: WKWebView
        @Published var title: String = "New Tab"
        @Published var urlString: String = ""
        @Published var thumbnail: UIImage?
        @Published var isProtected: Bool = false
        var historyURLs: [URL] = []
        var historyIndex: Int = -1
        var pendingHistoryNavigationIndex: Int?

        init(webView: WKWebView) {
            self.webView = webView
            super.init()
        }
    }

    struct ClosedTabSnapshot {
        let group: PadBrowserTabGroup
        let url: URL?
        let title: String
        let isProtected: Bool
        let historyURLs: [URL]
        let historyIndex: Int
    }

    private struct GroupState {
        var tabs: [Tab] = []
        var selectedIndex: Int = 0
    }

    @Published private(set) var currentGroup: PadBrowserTabGroup = .regular
    @Published private(set) var tabs: [Tab] = []
    @Published private(set) var selectedIndex: Int = 0
    @Published var addressInput: String = ""
    @Published var navigationStateToken = UUID()
    @Published private(set) var groupStateRevision = UUID()
    @Published var selectedSidebarTabID: UUID?
    @Published var pendingHarmfulSitePrompt: HarmfulSitePrompt?
    @Published var lastFindResultSummary: String?
    private var states: [PadBrowserTabGroup: GroupState] = [:]
    private var closedTabs: [ClosedTabSnapshot] = []
    private let privateWebsiteDataStore = WKWebsiteDataStore.nonPersistent()
    private let startPageBaseURL = URL(string: "https://vidarr.local/start")!

    override init() {
        super.init()
        PadBrowserTabGroup.allCases.forEach { states[$0] = GroupState() }
        restoreSessionIfAvailable()
        if tabs.isEmpty {
            ensureAtLeastOneTab(in: currentGroup)
        }
        selectedSidebarTabID = selectedTab?.id
    }

    var selectedTab: Tab? {
        guard selectedIndex >= 0, selectedIndex < tabs.count else { return nil }
        return tabs[selectedIndex]
    }

    func tabIndex(for id: UUID) -> Int? {
        tabs.firstIndex(where: { $0.id == id })
    }

    var availableGroups: [PadBrowserTabGroup] { PadBrowserTabGroup.allCases }

    func tabs(in group: PadBrowserTabGroup) -> [Tab] {
        state(for: group).tabs
    }

    func selectedTabID(in group: PadBrowserTabGroup) -> UUID? {
        let state = state(for: group)
        guard state.selectedIndex >= 0, state.selectedIndex < state.tabs.count else { return nil }
        return state.tabs[state.selectedIndex].id
    }

    func switchGroup(_ group: PadBrowserTabGroup) {
        currentGroup = group
        ensureAtLeastOneTab(in: group)
        syncPublishedState()
        navigationStateToken = UUID()
    }

    func selectTab(in group: PadBrowserTabGroup, id: UUID) {
        currentGroup = group
        var state = state(for: group)
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else {
            ensureAtLeastOneTab(in: group)
            return
        }
        state.selectedIndex = index
        setState(state, for: group)
        syncPublishedState()
        navigationStateToken = UUID()
        saveSessionSnapshot()
    }

    func newTab(initialURL: URL? = PadBrowserPreferences.shared.homePageURL, historyURLs: [URL] = [], historyIndex: Int = -1, isProtected: Bool = false) {
        let group = currentGroup
        let webView = makeWebView(for: group)
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
        tab.isProtected = isProtected
        let resolvedHistory = historyURLs.isEmpty ? (initialURL.map { [$0] } ?? []) : historyURLs
        tab.historyURLs = resolvedHistory
        tab.historyIndex = min(max(historyIndex, resolvedHistory.isEmpty ? -1 : 0), max(resolvedHistory.count - 1, -1))
        var state = state(for: group)
        state.tabs.append(tab)
        state.selectedIndex = max(0, state.tabs.count - 1)
        setState(state, for: group)
        selectedSidebarTabID = tab.id
        if let initialURL {
            load(initialURL, in: webView)
        } else {
            loadStartPage(in: webView)
            captureThumbnail(for: tab)
        }
        syncPublishedState()
        saveSessionSnapshot()
    }

    @discardableResult
    func addBackgroundTab(initialURL: URL? = PadBrowserPreferences.shared.homePageURL, historyURLs: [URL] = [], historyIndex: Int = -1, isProtected: Bool = false, in group: PadBrowserTabGroup? = nil) -> Tab {
        let targetGroup = group ?? currentGroup
        let webView = makeWebView(for: targetGroup)
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
        tab.isProtected = isProtected
        let resolvedHistory = historyURLs.isEmpty ? (initialURL.map { [$0] } ?? []) : historyURLs
        tab.historyURLs = resolvedHistory
        tab.historyIndex = min(max(historyIndex, resolvedHistory.isEmpty ? -1 : 0), max(resolvedHistory.count - 1, -1))
        var state = state(for: targetGroup)
        state.tabs.append(tab)
        setState(state, for: targetGroup)
        if let initialURL {
            load(initialURL, in: webView)
        } else {
            loadStartPage(in: webView)
            captureThumbnail(for: tab)
        }
        if targetGroup == currentGroup {
            syncPublishedState()
        }
        saveSessionSnapshot()
        return tab
    }

    func discardTab(id: UUID) {
        var state = state(for: currentGroup)
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.tabs.remove(at: index)
        setState(state, for: currentGroup)
        if state.tabs.isEmpty {
            ensureAtLeastOneTab(in: currentGroup)
            return
        }
        let clamped = min(max(0, state.selectedIndex), state.tabs.count - 1)
        state.selectedIndex = clamped
        setState(state, for: currentGroup)
        selectedSidebarTabID = selectedTab?.id
        syncPublishedState()
        saveSessionSnapshot()
    }

    func closeTab(id: UUID) {
        var state = state(for: currentGroup)
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = state.tabs[index]
        closedTabs.insert(
            ClosedTabSnapshot(
                group: currentGroup,
                url: URL(string: tab.urlString),
                title: tab.title,
                isProtected: tab.isProtected,
                historyURLs: tab.historyURLs,
                historyIndex: tab.historyIndex
            ),
            at: 0
        )
        if closedTabs.count > 20 {
            closedTabs.removeLast(closedTabs.count - 20)
        }
        state.tabs.remove(at: index)
        if state.tabs.isEmpty {
            setState(state, for: currentGroup)
            ensureAtLeastOneTab(in: currentGroup)
            return
        }
        state.selectedIndex = min(state.selectedIndex, state.tabs.count - 1)
        if index <= state.selectedIndex {
            state.selectedIndex = max(0, state.selectedIndex - 1)
        }
        setState(state, for: currentGroup)
        selectedSidebarTabID = selectedTab?.id
        syncPublishedState()
        saveSessionSnapshot()
    }

    func selectTab(id: UUID) {
        var state = state(for: currentGroup)
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.selectedIndex = index
        setState(state, for: currentGroup)
        selectedSidebarTabID = id
        syncPublishedState()
        saveSessionSnapshot()
    }

    func goBack() {
        guard let tab = selectedTab else { return }
        if tab.webView.canGoBack {
            tab.webView.goBack()
            return
        }
        guard tab.historyIndex > 0 else { return }
        let targetIndex = tab.historyIndex - 1
        tab.pendingHistoryNavigationIndex = targetIndex
        load(tab.historyURLs[targetIndex], in: tab.webView)
    }

    func goForward() {
        guard let tab = selectedTab else { return }
        if tab.webView.canGoForward {
            tab.webView.goForward()
            return
        }
        guard tab.historyIndex >= 0, tab.historyIndex < tab.historyURLs.count - 1 else { return }
        let targetIndex = tab.historyIndex + 1
        tab.pendingHistoryNavigationIndex = targetIndex
        load(tab.historyURLs[targetIndex], in: tab.webView)
    }

    func reload() {
        guard let tab = selectedTab else { return }
        if let url = tab.webView.url ?? URL(string: tab.urlString) {
            load(url, in: tab.webView)
        } else {
            loadStartPage(in: tab.webView)
        }
    }

    func reloadAllTabs() {
        for tab in tabs {
            if let url = tab.webView.url ?? URL(string: tab.urlString) {
                load(url, in: tab.webView)
            } else {
                loadStartPage(in: tab.webView)
            }
        }
    }

    func commitAddressBar() {
        let trimmed = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = resolvedURL(from: trimmed)
        if let webView = selectedTab?.webView {
            load(url, in: webView)
        }
    }

    func syncAddressBar() {
        addressInput = selectedTab?.urlString.isEmpty == false ? (selectedTab?.urlString ?? "") : (selectedTab?.webView.url?.absoluteString ?? "")
    }

    private func resolvedURL(from raw: String) -> URL {
        if let directURL = URL(string: raw), let scheme = directURL.scheme, ["http", "https"].contains(scheme.lowercased()) {
            return PadBrowserPreferences.shared.normalizedNavigableURL(from: directURL)
        }
        if raw.contains("."), let httpsURL = URL(string: "https://\(raw)") {
            return PadBrowserPreferences.shared.normalizedNavigableURL(from: httpsURL)
        }
        return PadBrowserPreferences.shared.normalizedNavigableURL(from: PadBrowserPreferences.shared.searchURL(for: raw))
    }

    func refreshPreferences() {
        let currentURL = selectedTab?.webView.url
        let currentTabID = selectedTab?.id
        for group in PadBrowserTabGroup.allCases {
            var state = state(for: group)
            let currentThumbnails = Dictionary(uniqueKeysWithValues: state.tabs.map { ($0.id, $0.thumbnail) })
            state.tabs = state.tabs.map { oldTab in
                let webView = makeWebView(for: group)
                let newTab = Tab(webView: webView)
                newTab.title = oldTab.title
                newTab.urlString = oldTab.urlString
                newTab.thumbnail = currentThumbnails[oldTab.id] ?? nil
                newTab.isProtected = oldTab.isProtected
                newTab.historyURLs = oldTab.historyURLs
                newTab.historyIndex = oldTab.historyIndex
                webView.navigationDelegate = self
                if let url = currentTabID == oldTab.id ? currentURL : URL(string: oldTab.urlString) {
                    load(url, in: webView)
                } else {
                    loadStartPage(in: webView)
                }
                return newTab
            }
            if state.tabs.isEmpty {
                setState(state, for: group)
                if group == currentGroup {
                    ensureAtLeastOneTab(in: group)
                }
            } else {
                state.selectedIndex = min(state.selectedIndex, max(state.tabs.count - 1, 0))
                setState(state, for: group)
            }
        }
        syncPublishedState()
        saveSessionSnapshot()
    }

    func closeAllTabs() {
        let selectedWebView = selectedTab?.webView
        var state = state(for: currentGroup)
        var retained: [Tab] = []
        let snapshots = state.tabs.compactMap { tab -> ClosedTabSnapshot? in
            if tab.isProtected {
                retained.append(tab)
                return nil
            }
            return ClosedTabSnapshot(
                group: currentGroup,
                url: URL(string: tab.urlString),
                title: tab.title,
                isProtected: tab.isProtected,
                historyURLs: tab.historyURLs,
                historyIndex: tab.historyIndex
            )
        }
        closedTabs.insert(contentsOf: snapshots.reversed(), at: 0)
        if closedTabs.count > 20 {
            closedTabs.removeLast(closedTabs.count - 20)
        }
        state.tabs = retained
        if state.tabs.isEmpty {
            setState(state, for: currentGroup)
            ensureAtLeastOneTab(in: currentGroup)
            return
        }
        if let selectedWebView,
           let retainedIndex = state.tabs.firstIndex(where: { $0.webView === selectedWebView }) {
            state.selectedIndex = retainedIndex
        } else {
            state.selectedIndex = 0
        }
        setState(state, for: currentGroup)
        selectedSidebarTabID = selectedTab?.id
        syncPublishedState()
        saveSessionSnapshot()
    }

    func closeAllTabs(in group: PadBrowserTabGroup) {
        let selectedWebView = group == currentGroup ? selectedTab?.webView : nil
        var state = state(for: group)
        var retained: [Tab] = []
        let snapshots = state.tabs.compactMap { tab -> ClosedTabSnapshot? in
            if tab.isProtected {
                retained.append(tab)
                return nil
            }
            return ClosedTabSnapshot(
                group: group,
                url: URL(string: tab.urlString),
                title: tab.title,
                isProtected: tab.isProtected,
                historyURLs: tab.historyURLs,
                historyIndex: tab.historyIndex
            )
        }
        closedTabs.insert(contentsOf: snapshots.reversed(), at: 0)
        if closedTabs.count > 20 {
            closedTabs.removeLast(closedTabs.count - 20)
        }
        state.tabs = retained

        if state.tabs.isEmpty {
            setState(state, for: group)
            if group == currentGroup {
                ensureAtLeastOneTab(in: group)
            } else {
                saveSessionSnapshot()
            }
            return
        }

        if let selectedWebView,
           let retainedIndex = state.tabs.firstIndex(where: { $0.webView === selectedWebView }) {
            state.selectedIndex = retainedIndex
        } else {
            state.selectedIndex = 0
        }
        setState(state, for: group)
        if group == currentGroup {
            selectedSidebarTabID = selectedTab?.id
        }
        syncPublishedState()
        saveSessionSnapshot()
    }

    func restoreClosedTab() {
        guard let snapshot = closedTabs.first else { return }
        closedTabs.removeFirst()
        let shouldRestoreHistory = PadBrowserPreferences.shared.restoreClosedTabPageHistory
        currentGroup = snapshot.group
        newTab(
            initialURL: snapshot.url ?? PadBrowserPreferences.shared.homePageURL,
            historyURLs: shouldRestoreHistory ? snapshot.historyURLs : [],
            historyIndex: shouldRestoreHistory ? snapshot.historyIndex : -1,
            isProtected: snapshot.isProtected
        )
        selectedTab?.title = snapshot.title
        selectedTab?.urlString = snapshot.url?.absoluteString ?? ""
        saveSessionSnapshot()
    }

    func toggleProtectionForSelectedTab() {
        guard let tab = selectedTab else { return }
        tab.isProtected.toggle()
        navigationStateToken = UUID()
        saveSessionSnapshot()
    }

    func selectNextTab() {
        var state = state(for: currentGroup)
        guard state.tabs.count > 1 else { return }
        state.selectedIndex = min(state.selectedIndex + 1, state.tabs.count - 1)
        setState(state, for: currentGroup)
        selectedSidebarTabID = selectedTab?.id
        syncPublishedState()
        saveSessionSnapshot()
    }

    func selectPreviousTab() {
        var state = state(for: currentGroup)
        guard state.tabs.count > 1 else { return }
        state.selectedIndex = max(state.selectedIndex - 1, 0)
        setState(state, for: currentGroup)
        selectedSidebarTabID = selectedTab?.id
        syncPublishedState()
        saveSessionSnapshot()
    }

    var canRestoreClosedTab: Bool {
        !closedTabs.isEmpty
    }

    func canGoBack() -> Bool {
        guard let tab = selectedTab else { return false }
        return tab.webView.canGoBack || tab.historyIndex > 0
    }

    func canGoForward() -> Bool {
        guard let tab = selectedTab else { return false }
        return tab.webView.canGoForward || (tab.historyIndex >= 0 && tab.historyIndex < tab.historyURLs.count - 1)
    }

    func isBookmarked(_ tab: Tab) -> Bool {
        PadBookmarkStore.shared.contains(url: URL(string: tab.urlString))
    }

    func toggleBookmarkForSelectedTab() {
        guard let tab = selectedTab, let url = URL(string: tab.urlString) else { return }
        PadBookmarkStore.shared.toggle(url: url, title: tab.title)
        navigationStateToken = UUID()
    }

    func isDangerousSiteAllowed(for tab: Tab) -> Bool {
        guard let host = URL(string: tab.urlString)?.host?.lowercased() else { return false }
        return PadBrowserPreferences.shared.harmfulSiteAllowedHosts.contains(host)
    }

    func toggleDangerousSiteAllowedForSelectedTab() {
        guard let host = selectedTab.flatMap({ URL(string: $0.urlString)?.host?.lowercased() }) else { return }
        let allowed = PadBrowserPreferences.shared.harmfulSiteAllowedHosts.contains(host)
        PadBrowserPreferences.shared.setHarmfulSiteAllowed(!allowed, for: host)
    }

    func loadSelectedTab(with input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = resolvedURL(from: trimmed)
        if let webView = selectedTab?.webView {
            load(url, in: webView)
        }
    }

    func recentHistory(limit: Int = 8) -> [PadBrowsingItem] {
        Array(PadBrowsingHistoryStore.shared.all().prefix(limit))
    }

    func allHistory() -> [PadBrowsingItem] {
        PadBrowsingHistoryStore.shared.all()
    }

    func allBookmarks() -> [PadBrowsingItem] {
        PadBookmarkStore.shared.all()
    }

    func allDownloads() -> [PadDownloadItem] {
        PadDownloadStore.shared.all()
    }

    func openHistoryItem(_ item: PadBrowsingItem) {
        guard let url = URL(string: item.urlString) else { return }
        if let webView = selectedTab?.webView {
            load(url, in: webView)
        }
    }

    func openBookmarkItem(_ item: PadBrowsingItem) {
        openHistoryItem(item)
    }

    func removeHistoryItems(_ ids: Set<String>) {
        let remaining = PadBrowsingHistoryStore.shared.all().filter { !ids.contains($0.id) }
        if let data = try? JSONEncoder().encode(remaining) {
            PadBrowserPreferences.shared.userDefaultsForCurrentProfile().set(data, forKey: "history.items")
        }
    }

    func removeBookmarkItems(_ ids: Set<String>) {
        let remaining = PadBookmarkStore.shared.all().filter { !ids.contains($0.id) }
        if let data = try? JSONEncoder().encode(remaining) {
            PadBrowserPreferences.shared.userDefaultsForCurrentProfile().set(data, forKey: "bookmarks.items")
        }
        navigationStateToken = UUID()
    }

    private func restoreSessionIfAvailable() {
        let defaults = PadBrowserPreferences.shared.userDefaultsForCurrentProfile()
        guard PadBrowserPreferences.shared.reopenTabsOnLaunch else {
            defaults.removeObject(forKey: "browser.session.snapshot")
            return
        }
        guard let data = defaults.data(forKey: "browser.session.snapshot"),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
              !snapshot.groups.isEmpty else {
            return
        }

        for groupSnapshot in snapshot.groups where groupSnapshot.group != .privateMode {
            var state = GroupState()
            for tabSnapshot in groupSnapshot.tabs {
                let webView = makeWebView(for: groupSnapshot.group)
                let tab = Tab(webView: webView)
                tab.title = tabSnapshot.title
                tab.urlString = tabSnapshot.urlString ?? ""
                tab.isProtected = tabSnapshot.isProtected
                tab.historyURLs = tabSnapshot.historyURLStrings.compactMap(URL.init(string:))
                tab.historyIndex = min(max(tabSnapshot.historyIndex, -1), max(tab.historyURLs.count - 1, -1))
                webView.navigationDelegate = self
                state.tabs.append(tab)
                let initialURL: URL?
                if tab.historyIndex >= 0, tab.historyIndex < tab.historyURLs.count {
                    initialURL = tab.historyURLs[tab.historyIndex]
                } else if let urlString = tabSnapshot.urlString, let url = URL(string: urlString) {
                    initialURL = url
                } else {
                    initialURL = nil
                }
                if let initialURL {
                    load(initialURL, in: webView)
                } else {
                    loadStartPage(in: webView)
                }
            }
            state.selectedIndex = min(max(0, groupSnapshot.selectedIndex), max(state.tabs.count - 1, 0))
            setState(state, for: groupSnapshot.group)
        }
        currentGroup = snapshot.currentGroup == .privateMode ? .regular : snapshot.currentGroup
        ensureAtLeastOneTab(in: currentGroup)
        syncPublishedState()
    }

    private func saveSessionSnapshot() {
        let defaults = PadBrowserPreferences.shared.userDefaultsForCurrentProfile()
        guard PadBrowserPreferences.shared.reopenTabsOnLaunch else {
            defaults.removeObject(forKey: "browser.session.snapshot")
            return
        }
        let snapshot = SessionSnapshot(
            currentGroup: currentGroup == .privateMode ? .regular : currentGroup,
            groups: PadBrowserTabGroup.allCases.compactMap { group in
                guard group != .privateMode else { return nil }
                let state = state(for: group)
                guard !state.tabs.isEmpty else { return nil }
                return GroupSessionSnapshot(
                    group: group,
                    selectedIndex: min(max(0, state.selectedIndex), max(state.tabs.count - 1, 0)),
                    tabs: state.tabs.map { tab in
                        SessionTabSnapshot(
                            urlString: tab.webView.url?.absoluteString ?? (tab.urlString.isEmpty ? nil : tab.urlString),
                            title: tab.title,
                            isProtected: tab.isProtected,
                            historyURLStrings: tab.historyURLs.map(\.absoluteString),
                            historyIndex: tab.historyIndex
                        )
                    }
                )
            }
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: "browser.session.snapshot")
        }
    }

    private func captureThumbnail(for tab: Tab) {
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        configuration.snapshotWidth = 280
        tab.webView.takeSnapshot(with: configuration) { image, _ in
            Task { @MainActor in
                tab.thumbnail = image
            }
        }
    }

    private func makeWebView(for group: PadBrowserTabGroup) -> WKWebView {
        let prefs = PadBrowserPreferences.shared
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = prefs.allowsJavaScript
        if group == .privateMode {
            configuration.websiteDataStore = privateWebsiteDataStore
        } else if prefs.cookiePolicy == .privateOnly {
            configuration.websiteDataStore = .nonPersistent()
        }
        let webView = PadInteractiveWebView(frame: .zero, configuration: configuration)
        webView.onSearchSelection = { [weak self] text in
            self?.openSelectionSearch(text)
        }
        return webView
    }

    private func load(_ url: URL, in webView: WKWebView) {
        let normalized = PadBrowserPreferences.shared.normalizedNavigableURL(from: url)
        if normalized.absoluteString == "about:blank" {
            loadStartPage(in: webView)
            return
        }
        webView.load(URLRequest(url: normalized))
    }

    private func loadStartPage(in webView: WKWebView, initialQuery: String? = nil) {
        let searchTemplate = PadBrowserPreferences.shared.searchTemplate
        let escapedQuery = String(reflecting: initialQuery ?? "")
        let html = """
        <!doctype html>
        <html lang="ja">
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Vidarr Start</title>
        <style>
        :root {
          color-scheme: light dark;
          --bg0: #edf3fb;
          --bg1: #dde6f4;
          --glass: rgba(255,255,255,0.58);
          --stroke: rgba(255,255,255,0.46);
          --text: #0f172a;
          --subtle: rgba(15,23,42,0.58);
          --field: rgba(255,255,255,0.84);
          --fieldStroke: rgba(148,163,184,0.30);
          --shadow: rgba(15,23,42,0.14);
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg0: #07111d;
            --bg1: #0b1726;
            --glass: rgba(10,14,22,0.60);
            --stroke: rgba(255,255,255,0.10);
            --text: #f8fafc;
            --subtle: rgba(248,250,252,0.58);
            --field: rgba(255,255,255,0.08);
            --fieldStroke: rgba(255,255,255,0.10);
            --strong: #f8fafc;
            --strongText: #111827;
            --shadow: rgba(0,0,0,0.32);
          }
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          min-height: 100vh;
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          color: var(--text);
          background:
            radial-gradient(circle at 18% 12%, rgba(72, 139, 255, 0.20), transparent 34%),
            radial-gradient(circle at 82% 16%, rgba(108, 92, 231, 0.08), transparent 24%),
            linear-gradient(180deg, var(--bg0) 0%, var(--bg1) 100%);
        }
        .shell {
          min-height: 100vh;
          display: grid;
          place-items: center;
          padding: 18px;
        }
        .panel {
          width: min(560px, calc(100vw - 20px));
          padding: 22px 18px 18px;
          border-radius: 26px;
          background: var(--glass);
          border: 1px solid var(--stroke);
          backdrop-filter: blur(28px) saturate(1.22);
          box-shadow: 0 24px 60px var(--shadow);
        }
        .brand {
          margin: 0 0 14px;
          font-size: clamp(28px, 7vw, 42px);
          font-weight: 700;
          line-height: 0.98;
          letter-spacing: -0.05em;
          font-family: "Snell Roundhand", "Apple Chancery", "Savoye LET", cursive;
          font-weight: 600;
          letter-spacing: -0.02em;
        }
        form {
          display: flex;
          align-items: center;
          gap: 10px;
        }
        .search {
          flex: 1 1 auto;
          width: 100%;
          height: 52px;
          padding: 0 18px;
          border-radius: 18px;
          border: 1px solid var(--fieldStroke);
          background: var(--field);
          color: var(--text);
          font-size: 16px;
          outline: none;
        }
        .search::placeholder { color: color-mix(in srgb, var(--subtle) 78%, transparent); }
        .search:focus {
          border-color: rgba(96,165,250,0.42);
          box-shadow: 0 0 0 5px rgba(96,165,250,0.12);
        }
        button {
          width: 46px;
          height: 46px;
          flex: 0 0 46px;
          padding: 0;
          border-radius: 999px;
          border: 1px solid color-mix(in srgb, var(--stroke) 82%, transparent);
          background:
            linear-gradient(180deg, color-mix(in srgb, var(--field) 88%, white 12%) 0%, color-mix(in srgb, var(--field) 68%, transparent) 100%);
          color: var(--text);
          font: 600 18px -apple-system, BlinkMacSystemFont, sans-serif;
          box-shadow:
            inset 0 1px 0 rgba(255,255,255,0.34),
            0 10px 24px rgba(15,23,42,0.14);
          backdrop-filter: blur(20px) saturate(1.2);
          transition: transform 120ms ease, box-shadow 120ms ease, background 120ms ease;
          cursor: pointer;
        }
        button:active {
          transform: scale(0.96);
          box-shadow:
            inset 0 1px 0 rgba(255,255,255,0.20),
            0 6px 16px rgba(15,23,42,0.12);
        }
        @media (max-width: 640px) {
          .panel {
            width: min(100%, calc(100vw - 14px));
            padding: 18px 14px 14px;
            border-radius: 22px;
          }
          .brand { font-size: 30px; margin-bottom: 12px; }
          .search, button {
            height: 48px;
            border-radius: 16px;
          }
          button {
            width: 44px;
            flex-basis: 44px;
            border-radius: 999px;
            font-size: 17px;
          }
        }
        </style>
        <body>
          <div class="shell">
            <div class="panel">
              <div class="brand">Vidarr</div>
              <form id="searchForm">
                <input id="query" class="search" type="search" placeholder="検索語または URL を入力" autocomplete="off" spellcheck="false" />
                <button type="submit" aria-label="Open">→</button>
              </form>
            </div>
          </div>
          <script>
            const template = \(String(reflecting: searchTemplate));
            const initialQuery = \(escapedQuery);
            const input = document.getElementById('query');
            input.value = initialQuery;
            document.getElementById('searchForm').addEventListener('submit', function(event) {
              event.preventDefault();
              const raw = input.value.trim();
              if (!raw) {
                input.focus();
                return;
              }
              const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(raw);
              const looksLikeHost = raw.includes('.') && !raw.includes(' ');
              if (hasScheme) {
                window.location.href = raw;
                return;
              }
              if (looksLikeHost) {
                window.location.href = 'https://' + raw;
                return;
              }
              window.location.href = template.replace('{query}', encodeURIComponent(raw));
            });
            input.focus();
            if (initialQuery) {
              requestAnimationFrame(() => input.setSelectionRange(0, input.value.length));
            }
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: startPageBaseURL)
    }

    func openQuickSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if let webView = selectedTab?.webView {
                loadStartPage(in: webView)
            }
            return
        }
        loadSelectedTab(with: trimmed)
    }

    func openSearchPageInNewTab(initialQuery: String? = nil) {
        let group = currentGroup
        let webView = makeWebView(for: group)
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
        var state = state(for: group)
        state.tabs.append(tab)
        state.selectedIndex = max(0, state.tabs.count - 1)
        setState(state, for: group)
        selectedSidebarTabID = tab.id
        loadStartPage(in: webView, initialQuery: initialQuery)
        captureThumbnail(for: tab)
        syncPublishedState()
        saveSessionSnapshot()
    }

    func openSelectionSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newTab(initialURL: PadBrowserPreferences.shared.searchURL(for: trimmed))
    }

    func copySelectionText(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
    }

    func handleSelectionAction(_ action: String, query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch action {
        case "copy":
            copySelectionText(trimmed)
        case "search":
            openSelectionSearch(trimmed)
        default:
            break
        }
    }

    func findInSelectedPage(_ query: String, completion: @escaping (String?) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let webView = selectedTab?.webView else {
            completion(nil)
            return
        }

        let configuration = WKFindConfiguration()
        configuration.backwards = false
        configuration.wraps = true
        configuration.caseSensitive = false
        webView.find(trimmed, configuration: configuration) { [weak self] result in
            Task { @MainActor in
                let summary = result.matchFound ? "見つかりました" : "見つかりませんでした"
                self?.lastFindResultSummary = summary
                completion(summary)
            }
        }
    }

    private func syncTabHistory(for tab: Tab, currentURL: URL) {
        if let pendingIndex = tab.pendingHistoryNavigationIndex,
           pendingIndex >= 0,
           pendingIndex < tab.historyURLs.count,
           tab.historyURLs[pendingIndex] == currentURL {
            tab.historyIndex = pendingIndex
            tab.pendingHistoryNavigationIndex = nil
            return
        }

        tab.pendingHistoryNavigationIndex = nil

        let history = tab.historyURLs
        let currentIndex = tab.historyIndex
        if currentIndex >= 0, currentIndex < history.count, history[currentIndex] == currentURL {
            return
        }
        if currentIndex > 0, history[currentIndex - 1] == currentURL {
            tab.historyIndex = currentIndex - 1
            return
        }
        if currentIndex >= 0, currentIndex + 1 < history.count, history[currentIndex + 1] == currentURL {
            tab.historyIndex = currentIndex + 1
            return
        }

        var nextHistory = currentIndex >= 0 && currentIndex < history.count
            ? Array(history.prefix(currentIndex + 1))
            : history
        nextHistory.append(currentURL)
        if nextHistory.count > 50 {
            nextHistory = Array(nextHistory.suffix(50))
        }
        tab.historyURLs = nextHistory
        tab.historyIndex = nextHistory.count - 1
    }
}

extension PadBrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if let warning = harmfulSiteWarning(for: url),
           PadBrowserPreferences.shared.harmfulSiteAllowedHosts.contains(warning.host) == false {
            pendingHarmfulSitePrompt = warning
            decisionHandler(.cancel)
            return
        }

        let normalized = PadBrowserPreferences.shared.normalizedNavigableURL(from: url)
        if normalized != url {
            webView.load(URLRequest(url: normalized))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType {
            if let sourceURL = navigationResponse.response.url {
                startDownload(for: sourceURL)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self,
                  let group = self.group(for: webView) else { return }
            var state = self.state(for: group)
            guard let index = state.tabs.firstIndex(where: { $0.webView === webView }) else { return }
            let tab = state.tabs[index]
            let isInternalBlankPage = webView.url?.host == self.startPageBaseURL.host
            tab.title = isInternalBlankPage
                ? "Vidarr Start"
                : (webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (webView.title ?? "Vidarr Start")
                    : (webView.url?.host ?? webView.url?.absoluteString ?? "Vidarr Start"))
            tab.urlString = isInternalBlankPage ? "" : (webView.url?.absoluteString ?? "")
            if let url = webView.url, !isInternalBlankPage {
                self.syncTabHistory(for: tab, currentURL: url)
                if !self.isPrivateGroup(group) {
                    PadBrowsingHistoryStore.shared.recordVisit(url: url, title: tab.title)
                }
            }
            state.tabs[index] = tab
            self.setState(state, for: group)
            self.captureThumbnail(for: tab)
            if group == self.currentGroup {
                self.syncPublishedState()
            }
            self.navigationStateToken = UUID()
            self.saveSessionSnapshot()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.navigationStateToken = UUID()
        }
    }
}

extension PadBrowserModel {
    func harmfulSiteWarning(for url: URL) -> HarmfulSitePrompt? {
        guard PadBrowserPreferences.shared.harmfulSiteWarningEnabled,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return nil
        }

        if Self.harmfulHosts.contains(host) || Self.harmfulTLDs.contains(where: { host.hasSuffix(".\($0)") }) {
            return HarmfulSitePrompt(
                url: url,
                host: host,
                title: "注意が必要なサイトの可能性があります",
                message: "\(host) は危険な配布や追跡に使われやすい傾向があります。"
            )
        }
        return nil
    }

    func continueToHarmfulSite(permanentlyAllow: Bool) {
        guard let prompt = pendingHarmfulSitePrompt else { return }
        if permanentlyAllow {
            PadBrowserPreferences.shared.setHarmfulSiteAllowed(true, for: prompt.host)
        }
        pendingHarmfulSitePrompt = nil
        selectedTab?.webView.load(URLRequest(url: prompt.url))
    }

    func dismissHarmfulSitePrompt() {
        pendingHarmfulSitePrompt = nil
    }

    func startDownload(for url: URL) {
        let fileManager = FileManager.default
        let downloadsRoot = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Downloads", isDirectory: true)
        guard let directory = downloadsRoot else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let suggestedName = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let destination = availableDestinationURL(in: directory, suggestedFilename: suggestedName)
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, _ in
            guard let tempURL else { return }
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: destination)
            do {
                try fileManager.moveItem(at: tempURL, to: destination)
                Task { @MainActor in
                    PadDownloadStore.shared.add(sourceURL: url, destinationURL: destination)
                }
            } catch {
                return
            }
        }
        task.resume()
    }

    func availableDestinationURL(in directory: URL, suggestedFilename: String) -> URL {
        let fileManager = FileManager.default
        let baseName = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(suggestedFilename)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let filename = ext.isEmpty ? "\(baseName) \(suffix)" : "\(baseName) \(suffix).\(ext)"
            candidate = directory.appendingPathComponent(filename)
            suffix += 1
        }
        return candidate
    }

    private func state(for group: PadBrowserTabGroup) -> GroupState {
        states[group] ?? GroupState()
    }

    private func setState(_ state: GroupState, for group: PadBrowserTabGroup) {
        states[group] = state
        groupStateRevision = UUID()
    }

    private func ensureAtLeastOneTab(in group: PadBrowserTabGroup) {
        let state = state(for: group)
        guard state.tabs.isEmpty else {
            if group == currentGroup {
                syncPublishedState()
            }
            return
        }
        currentGroup = group
        newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
        currentGroup = group
        syncPublishedState()
    }

    private func syncPublishedState() {
        let state = state(for: currentGroup)
        tabs = state.tabs
        selectedIndex = min(max(0, state.selectedIndex), max(state.tabs.count - 1, 0))
        selectedSidebarTabID = selectedTab?.id
        syncAddressBar()
    }

    private func group(for webView: WKWebView) -> PadBrowserTabGroup? {
        for group in PadBrowserTabGroup.allCases {
            if state(for: group).tabs.contains(where: { $0.webView === webView }) {
                return group
            }
        }
        return nil
    }

    private func isPrivateGroup(_ group: PadBrowserTabGroup) -> Bool {
        group == .privateMode
    }

    static let harmfulHosts: Set<String> = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "adservice.google.co.jp", "amazon-adsystem.com", "connect.facebook.net", "bat.bing.com",
        "taboola.com", "outbrain.com", "adf.ly", "bit.ly", "tinyurl.com"
    ]

    static let harmfulTLDs: Set<String> = ["zip", "mov", "click", "country", "gq", "work", "download", "stream"]
}
