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
        @Published var showsNativeStartPage = false
        @Published var startPageQuery: String = ""
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
    private var scriptHandlerBoxes: [ObjectIdentifier: PadWeakScriptMessageHandler] = [:]
    private static let longPressOpenMessageName = "vidarrLongPressOpen"

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
        let preferredInitialURL = resolvedInitialURL(from: initialURL)
        let resolvedHistory = historyURLs.isEmpty ? (preferredInitialURL.map { [$0] } ?? []) : historyURLs
        tab.historyURLs = resolvedHistory
        tab.historyIndex = min(max(historyIndex, resolvedHistory.isEmpty ? -1 : 0), max(resolvedHistory.count - 1, -1))
        var state = state(for: group)
        state.tabs.append(tab)
        state.selectedIndex = max(0, state.tabs.count - 1)
        setState(state, for: group)
        selectedSidebarTabID = tab.id
        if let preferredInitialURL {
            load(preferredInitialURL, in: webView)
        } else {
            showNativeStartPage(in: webView)
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
        let preferredInitialURL = resolvedInitialURL(from: initialURL)
        let resolvedHistory = historyURLs.isEmpty ? (preferredInitialURL.map { [$0] } ?? []) : historyURLs
        tab.historyURLs = resolvedHistory
        tab.historyIndex = min(max(historyIndex, resolvedHistory.isEmpty ? -1 : 0), max(resolvedHistory.count - 1, -1))
        var state = state(for: targetGroup)
        state.tabs.append(tab)
        setState(state, for: targetGroup)
        if let preferredInitialURL {
            load(preferredInitialURL, in: webView)
        } else {
            showNativeStartPage(in: webView)
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
            loadDefaultNewTabPage(in: tab.webView)
        }
    }

    func reloadAllTabs() {
        for tab in tabs {
            if let url = tab.webView.url ?? URL(string: tab.urlString) {
                load(url, in: tab.webView)
            } else {
                loadDefaultNewTabPage(in: tab.webView)
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
                    showNativeStartPage(in: webView)
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
                    initialURL = resolvedInitialURL(from: tab.historyURLs[tab.historyIndex])
                } else if let urlString = tabSnapshot.urlString, let url = URL(string: urlString) {
                    initialURL = resolvedInitialURL(from: url)
                } else {
                    initialURL = nil
                }
                if let initialURL {
                    load(initialURL, in: webView)
                } else {
                    loadDefaultNewTabPage(in: webView)
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
        installLongPressOpenInBackgroundIfNeeded(on: configuration.userContentController)
        let webView = PadInteractiveWebView(frame: .zero, configuration: configuration)
        webView.onSearchSelection = { [weak self] text in
            self?.openSelectionSearch(text)
        }
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        return webView
    }

    private func installLongPressOpenInBackgroundIfNeeded(on contentController: WKUserContentController) {
        let controllerID = ObjectIdentifier(contentController)
        guard scriptHandlerBoxes[controllerID] == nil else { return }

        let handlerBox = PadWeakScriptMessageHandler(target: self)
        scriptHandlerBoxes[controllerID] = handlerBox
        contentController.removeScriptMessageHandler(forName: Self.longPressOpenMessageName)
        contentController.add(handlerBox, name: Self.longPressOpenMessageName)

        let source = """
        (() => {
            if (window.__vidarrLongPressInstalled) { return; }
            window.__vidarrLongPressInstalled = true;

            const HOLD_MS = 360;
            const MOVE_TOLERANCE = 14;
            let timer = null;
            const origin = { x: 0, y: 0 };
            const active = { href: null };
            const suppressTap = { value: false };
            const indicator = document.createElement('div');
            indicator.style.position = 'fixed';
            indicator.style.width = '40px';
            indicator.style.height = '40px';
            indicator.style.marginLeft = '-20px';
            indicator.style.marginTop = '-20px';
            indicator.style.display = 'none';
            indicator.style.alignItems = 'center';
            indicator.style.justifyContent = 'center';
            indicator.style.pointerEvents = 'none';
            indicator.style.zIndex = '2147483647';
            indicator.style.opacity = '0';
            indicator.style.transition = 'opacity 120ms ease, transform 140ms ease';
            indicator.style.transform = 'scale(0.92)';
            indicator.innerHTML = `
                <svg width="40" height="40" viewBox="0 0 40 40" fill="none" aria-hidden="true">
                    <circle cx="20" cy="20" r="15.5" stroke="rgba(10,132,255,0.22)" stroke-width="3"></circle>
                    <circle id="vidarrRing" cx="20" cy="20" r="15.5" stroke="rgba(10,132,255,0.98)" stroke-width="3" stroke-linecap="round" stroke-dasharray="97.39" stroke-dashoffset="97.39"></circle>
                </svg>
            `;
            const ring = indicator.querySelector('#vidarrRing');
            document.documentElement.appendChild(indicator);

            function resetTimer() {
                if (timer !== null) {
                    clearTimeout(timer);
                    timer = null;
                }
            }

            function hideIndicator(committed = false) {
                resetTimer();
                indicator.style.opacity = '0';
                indicator.style.transform = committed ? 'scale(1.08)' : 'scale(0.94)';
                ring.style.transition = 'none';
                ring.style.strokeDashoffset = '97.39';
                setTimeout(() => {
                    indicator.style.display = 'none';
                    indicator.style.transform = 'scale(0.92)';
                }, committed ? 120 : 80);
            }

            function showIndicator(x, y) {
                indicator.style.left = `${x}px`;
                indicator.style.top = `${y}px`;
                indicator.style.display = 'flex';
                indicator.style.opacity = '1';
                indicator.style.transform = 'scale(1)';
                ring.style.transition = 'none';
                ring.style.strokeDashoffset = '97.39';
                requestAnimationFrame(() => {
                    ring.style.transition = `stroke-dashoffset ${HOLD_MS}ms linear`;
                    ring.style.strokeDashoffset = '0';
                });
            }

            function isStandaloneImageDocument() {
                const body = document.body;
                if (!body) { return false; }
                const children = Array.from(body.children || []);
                if (children.length !== 1) { return false; }
                const only = children[0];
                if (!only || only.tagName.toLowerCase() !== 'img') { return false; }
                return true;
            }

            const calloutStyle = document.createElement('style');
            calloutStyle.textContent = `
                a[href], img[src] {
                    -webkit-touch-callout: none !important;
                }
                body > img:only-child {
                    -webkit-touch-callout: default !important;
                }
            `;
            (document.head || document.documentElement).appendChild(calloutStyle);

            function payloadFromEvent(event) {
                const path = event.composedPath ? event.composedPath() : [];
                for (const node of path) {
                    if (!node || !node.tagName) { continue; }
                    const tag = node.tagName.toLowerCase();
                    if (tag === 'a' && node.href) { return { href: node.href, kind: 'link' }; }
                    if (tag === 'img' && node.src) {
                        if (isStandaloneImageDocument()) { return null; }
                        return { href: node.src, kind: 'image' };
                    }
                }
                if (event.target && event.target.closest) {
                    const anchor = event.target.closest('a[href]');
                    if (anchor && anchor.href) { return { href: anchor.href, kind: 'link' }; }
                    const image = event.target.closest('img[src]');
                    if (image && image.src) {
                        if (isStandaloneImageDocument()) { return null; }
                        return { href: image.src, kind: 'image' };
                    }
                }
                return null;
            }

            function resetState() {
                active.href = null;
                hideIndicator(false);
            }

            document.addEventListener('touchstart', (event) => {
                if (event.touches.length !== 1) {
                    resetState();
                    return;
                }
                const payload = payloadFromEvent(event);
                if (!payload || !payload.href) {
                    resetState();
                    return;
                }
                active.href = payload.href;
                origin.x = event.touches[0].clientX;
                origin.y = event.touches[0].clientY;
                showIndicator(origin.x, origin.y);
                resetTimer();
                timer = setTimeout(() => {
                    if (!active.href) { return; }
                    suppressTap.value = true;
                    window.webkit.messageHandlers.\(Self.longPressOpenMessageName).postMessage({ href: active.href });
                    active.href = null;
                    hideIndicator(true);
                }, HOLD_MS);
            }, { capture: true, passive: true });

            document.addEventListener('touchmove', (event) => {
                if (!active.href || event.touches.length !== 1) { return; }
                const dx = event.touches[0].clientX - origin.x;
                const dy = event.touches[0].clientY - origin.y;
                if (Math.hypot(dx, dy) > MOVE_TOLERANCE) {
                    resetState();
                }
            }, { capture: true, passive: true });

            ['touchend', 'touchcancel', 'scroll', 'dragstart'].forEach((name) => {
                document.addEventListener(name, () => {
                    if (active.href) {
                        resetState();
                    } else {
                        hideIndicator(false);
                    }
                }, { capture: true, passive: true });
            });

            document.addEventListener('contextmenu', (event) => {
                const payload = payloadFromEvent(event);
                if (!payload || !payload.href) { return; }
                event.preventDefault();
                event.stopPropagation();
            }, true);

            document.addEventListener('click', (event) => {
                if (!suppressTap.value) { return; }
                suppressTap.value = false;
                event.preventDefault();
                event.stopPropagation();
            }, true);
        })();
        """

        contentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
    }

    private func load(_ url: URL, in webView: WKWebView) {
        let normalized = PadBrowserPreferences.shared.normalizedNavigableURL(from: url)
        if normalized.absoluteString == "about:blank" {
            loadDefaultNewTabPage(in: webView)
            return
        }
        if let tab = tab(for: webView) {
            tab.showsNativeStartPage = false
            tab.startPageQuery = ""
        }
        webView.load(URLRequest(url: normalized))
    }

    private func showNativeStartPage(in webView: WKWebView, initialQuery: String? = nil) {
        if let tab = tab(for: webView) {
            tab.showsNativeStartPage = true
            tab.startPageQuery = initialQuery ?? ""
            tab.title = "Vidarr Start"
            tab.urlString = ""
        }
        webView.loadHTMLString("", baseURL: nil)
    }

    func openQuickSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if let webView = selectedTab?.webView {
                showNativeStartPage(in: webView)
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
        showNativeStartPage(in: webView, initialQuery: initialQuery)
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

extension PadBrowserModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.longPressOpenMessageName,
              let body = message.body as? [String: Any],
              let href = body["href"] as? String,
              let url = URL(string: href) else {
            return
        }

        let normalized = PadBrowserPreferences.shared.normalizedNavigableURL(from: url)
        let targetGroup = message.webView.flatMap { self.group(for: $0) } ?? currentGroup
        addBackgroundTab(initialURL: normalized, in: targetGroup)
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
            let isNativeStartPage = tab.showsNativeStartPage && (webView.url == nil || webView.url?.absoluteString == "about:blank")
            if isNativeStartPage {
                tab.title = "Vidarr Start"
                tab.urlString = ""
            } else {
                tab.showsNativeStartPage = false
                tab.title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (webView.title ?? "Vidarr Start")
                    : (webView.url?.host ?? webView.url?.absoluteString ?? "Vidarr Start")
                tab.urlString = webView.url?.absoluteString ?? ""
            }
            if let url = webView.url, !isNativeStartPage {
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

    private func resolvedInitialURL(from candidate: URL?) -> URL? {
        if let candidate, candidate.absoluteString != "about:blank" {
            return PadBrowserPreferences.shared.normalizedNavigableURL(from: candidate)
        }
        return PadBrowserPreferences.shared.homePageURL
            .map { PadBrowserPreferences.shared.normalizedNavigableURL(from: $0) }
    }

    private func loadDefaultNewTabPage(in webView: WKWebView) {
        if let url = resolvedInitialURL(from: nil) {
            webView.load(URLRequest(url: url))
        } else {
            showNativeStartPage(in: webView)
        }
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
        newTab(initialURL: resolvedInitialURL(from: nil))
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

    private func tab(for webView: WKWebView) -> Tab? {
        for group in PadBrowserTabGroup.allCases {
            if let tab = state(for: group).tabs.first(where: { $0.webView === webView }) {
                return tab
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

private final class PadWeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
