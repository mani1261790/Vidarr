import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

@MainActor
final class PadBrowserModel: NSObject, ObservableObject {
    private struct SessionTabSnapshot: Codable {
        let urlString: String?
        let title: String
        let historyURLStrings: [String]
        let historyIndex: Int
    }

    private struct SessionSnapshot: Codable {
        let selectedIndex: Int
        let tabs: [SessionTabSnapshot]
    }

    final class Tab: NSObject, Identifiable, ObservableObject {
        let id = UUID()
        let webView: WKWebView
        @Published var title: String = "New Tab"
        @Published var urlString: String = ""
        @Published var thumbnail: UIImage?
        var historyURLs: [URL] = []
        var historyIndex: Int = -1
        var pendingHistoryNavigationIndex: Int?

        init(webView: WKWebView) {
            self.webView = webView
            super.init()
        }
    }

    struct ClosedTabSnapshot {
        let url: URL?
        let title: String
        let historyURLs: [URL]
        let historyIndex: Int
    }

    @Published private(set) var tabs: [Tab] = []
    @Published var selectedIndex: Int = 0
    @Published var addressInput: String = ""
    @Published var navigationStateToken = UUID()
    @Published var selectedSidebarTabID: UUID?

    private var closedTabs: [ClosedTabSnapshot] = []

    override init() {
        super.init()
        restoreSessionIfAvailable()
        if tabs.isEmpty {
            newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
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

    func newTab(initialURL: URL? = nil, historyURLs: [URL] = [], historyIndex: Int = -1) {
        let webView = makeWebView()
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
        let resolvedHistory = historyURLs.isEmpty ? (initialURL.map { [$0] } ?? []) : historyURLs
        tab.historyURLs = resolvedHistory
        tab.historyIndex = min(max(historyIndex, resolvedHistory.isEmpty ? -1 : 0), max(resolvedHistory.count - 1, -1))
        tabs.append(tab)
        selectedIndex = tabs.count - 1
        selectedSidebarTabID = tab.id
        if let initialURL {
            webView.load(URLRequest(url: initialURL))
        } else {
            captureThumbnail(for: tab)
        }
        syncAddressBar()
        saveSessionSnapshot()
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        closedTabs.insert(
            ClosedTabSnapshot(
                url: URL(string: tab.urlString),
                title: tab.title,
                historyURLs: tab.historyURLs,
                historyIndex: tab.historyIndex
            ),
            at: 0
        )
        if closedTabs.count > 20 {
            closedTabs.removeLast(closedTabs.count - 20)
        }
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
            return
        }
        selectedIndex = min(selectedIndex, tabs.count - 1)
        if index <= selectedIndex {
            selectedIndex = max(0, selectedIndex - 1)
        }
        selectedSidebarTabID = selectedTab?.id
        syncAddressBar()
        saveSessionSnapshot()
    }

    func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
        selectedSidebarTabID = id
        syncAddressBar()
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
        tab.webView.load(URLRequest(url: tab.historyURLs[targetIndex]))
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
        tab.webView.load(URLRequest(url: tab.historyURLs[targetIndex]))
    }

    func reload() {
        selectedTab?.webView.reload()
    }

    func reloadAllTabs() {
        for tab in tabs {
            tab.webView.reload()
        }
    }

    func commitAddressBar() {
        let trimmed = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = resolvedURL(from: trimmed)
        selectedTab?.webView.load(URLRequest(url: url))
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
        let currentIndex = selectedIndex
        let currentThumbnails = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.thumbnail) })

        tabs = tabs.map { oldTab in
            let webView = makeWebView()
            let newTab = Tab(webView: webView)
            newTab.title = oldTab.title
            newTab.urlString = oldTab.urlString
            newTab.thumbnail = currentThumbnails[oldTab.id] ?? nil
            newTab.historyURLs = oldTab.historyURLs
            newTab.historyIndex = oldTab.historyIndex
            webView.navigationDelegate = self
            if let url = currentTabID == oldTab.id ? currentURL : URL(string: oldTab.urlString) {
                webView.load(URLRequest(url: PadBrowserPreferences.shared.normalizedNavigableURL(from: url)))
            }
            return newTab
        }

        if tabs.isEmpty {
            newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
        } else {
            selectedIndex = min(currentIndex, max(tabs.count - 1, 0))
            syncAddressBar()
            saveSessionSnapshot()
        }
    }

    func closeAllTabs() {
        let snapshots = tabs.map {
            ClosedTabSnapshot(
                url: URL(string: $0.urlString),
                title: $0.title,
                historyURLs: $0.historyURLs,
                historyIndex: $0.historyIndex
            )
        }
        closedTabs.insert(contentsOf: snapshots.reversed(), at: 0)
        if closedTabs.count > 20 {
            closedTabs.removeLast(closedTabs.count - 20)
        }
        tabs.removeAll()
        newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
    }

    func restoreClosedTab() {
        guard let snapshot = closedTabs.first else { return }
        closedTabs.removeFirst()
        let shouldRestoreHistory = PadBrowserPreferences.shared.restoreClosedTabPageHistory
        newTab(
            initialURL: snapshot.url ?? PadBrowserPreferences.shared.homePageURL,
            historyURLs: shouldRestoreHistory ? snapshot.historyURLs : [],
            historyIndex: shouldRestoreHistory ? snapshot.historyIndex : -1
        )
        selectedTab?.title = snapshot.title
        selectedTab?.urlString = snapshot.url?.absoluteString ?? ""
        saveSessionSnapshot()
    }

    func selectNextTab() {
        guard tabs.count > 1 else { return }
        selectedIndex = min(selectedIndex + 1, tabs.count - 1)
        selectedSidebarTabID = selectedTab?.id
        syncAddressBar()
        saveSessionSnapshot()
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        selectedIndex = max(selectedIndex - 1, 0)
        selectedSidebarTabID = selectedTab?.id
        syncAddressBar()
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

    func loadSelectedTab(with input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = resolvedURL(from: trimmed)
        selectedTab?.webView.load(URLRequest(url: url))
    }

    func recentHistory(limit: Int = 8) -> [PadBrowsingItem] {
        Array(PadBrowsingHistoryStore.shared.all().prefix(limit))
    }

    private func restoreSessionIfAvailable() {
        let defaults = PadBrowserPreferences.shared.userDefaultsForCurrentProfile()
        guard let data = defaults.data(forKey: "browser.session.snapshot"),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
              !snapshot.tabs.isEmpty else {
            return
        }

        for tabSnapshot in snapshot.tabs {
            let webView = makeWebView()
            let tab = Tab(webView: webView)
            tab.title = tabSnapshot.title
            tab.urlString = tabSnapshot.urlString ?? ""
            tab.historyURLs = tabSnapshot.historyURLStrings.compactMap(URL.init(string:))
            tab.historyIndex = min(max(tabSnapshot.historyIndex, -1), max(tab.historyURLs.count - 1, -1))
            webView.navigationDelegate = self
            tabs.append(tab)
            let initialURL: URL?
            if tab.historyIndex >= 0, tab.historyIndex < tab.historyURLs.count {
                initialURL = tab.historyURLs[tab.historyIndex]
            } else if let urlString = tabSnapshot.urlString, let url = URL(string: urlString) {
                initialURL = url
            } else {
                initialURL = nil
            }
            if let initialURL {
                webView.load(URLRequest(url: PadBrowserPreferences.shared.normalizedNavigableURL(from: initialURL)))
            }
        }

        selectedIndex = min(max(0, snapshot.selectedIndex), tabs.count - 1)
        syncAddressBar()
    }

    private func saveSessionSnapshot() {
        let defaults = PadBrowserPreferences.shared.userDefaultsForCurrentProfile()
        let snapshot = SessionSnapshot(
            selectedIndex: min(max(0, selectedIndex), max(tabs.count - 1, 0)),
            tabs: tabs.map { tab in
                SessionTabSnapshot(
                    urlString: tab.webView.url?.absoluteString ?? (tab.urlString.isEmpty ? nil : tab.urlString),
                    title: tab.title,
                    historyURLStrings: tab.historyURLs.map(\.absoluteString),
                    historyIndex: tab.historyIndex
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

    private func makeWebView() -> WKWebView {
        let prefs = PadBrowserPreferences.shared
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = prefs.allowsJavaScript
        if prefs.cookiePolicy == .privateOnly {
            configuration.websiteDataStore = .nonPersistent()
        }
        return WKWebView(frame: .zero, configuration: configuration)
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
        let normalized = PadBrowserPreferences.shared.normalizedNavigableURL(from: url)
        if normalized != url {
            webView.load(URLRequest(url: normalized))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, let tab = self.tabs.first(where: { $0.webView === webView }) else { return }
            tab.title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (webView.title ?? "New Tab")
                : (webView.url?.host ?? webView.url?.absoluteString ?? "New Tab")
            tab.urlString = webView.url?.absoluteString ?? ""
            if let url = webView.url {
                self.syncTabHistory(for: tab, currentURL: url)
                PadBrowsingHistoryStore.shared.recordVisit(url: url, title: tab.title)
            }
            self.captureThumbnail(for: tab)
            if self.selectedTab === tab {
                self.syncAddressBar()
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
