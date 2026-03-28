import Combine
import Foundation
import SwiftUI
import UIKit
import WebKit

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
        let url: URL?
        let title: String
        let isProtected: Bool
        let historyURLs: [URL]
        let historyIndex: Int
    }

    @Published private(set) var tabs: [Tab] = []
    @Published var selectedIndex: Int = 0
    @Published var addressInput: String = ""
    @Published var navigationStateToken = UUID()
    @Published var selectedSidebarTabID: UUID?
    @Published var pendingHarmfulSitePrompt: HarmfulSitePrompt?
    @Published var lastFindResultSummary: String?
    private var closedTabs: [ClosedTabSnapshot] = []
    private let startPageBaseURL = URL(string: "https://vidarr.local/start")!

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

    func newTab(initialURL: URL? = PadBrowserPreferences.shared.homePageURL, historyURLs: [URL] = [], historyIndex: Int = -1, isProtected: Bool = false) {
        let webView = makeWebView()
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
        tab.isProtected = isProtected
        let resolvedHistory = historyURLs.isEmpty ? (initialURL.map { [$0] } ?? []) : historyURLs
        tab.historyURLs = resolvedHistory
        tab.historyIndex = min(max(historyIndex, resolvedHistory.isEmpty ? -1 : 0), max(resolvedHistory.count - 1, -1))
        tabs.append(tab)
        selectedIndex = tabs.count - 1
        selectedSidebarTabID = tab.id
        if let initialURL {
            load(initialURL, in: webView)
        } else {
            loadStartPage(in: webView)
            captureThumbnail(for: tab)
        }
        syncAddressBar()
        saveSessionSnapshot()
    }

    @discardableResult
    func addBackgroundTab(initialURL: URL? = PadBrowserPreferences.shared.homePageURL, historyURLs: [URL] = [], historyIndex: Int = -1, isProtected: Bool = false) -> Tab {
        let webView = makeWebView()
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
        tab.isProtected = isProtected
        let resolvedHistory = historyURLs.isEmpty ? (initialURL.map { [$0] } ?? []) : historyURLs
        tab.historyURLs = resolvedHistory
        tab.historyIndex = min(max(historyIndex, resolvedHistory.isEmpty ? -1 : 0), max(resolvedHistory.count - 1, -1))
        tabs.append(tab)
        if let initialURL {
            load(initialURL, in: webView)
        } else {
            loadStartPage(in: webView)
            captureThumbnail(for: tab)
        }
        saveSessionSnapshot()
        return tab
    }

    func discardTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
            return
        }
        if selectedIndex >= tabs.count {
            selectedIndex = max(0, tabs.count - 1)
        }
        selectedSidebarTabID = selectedTab?.id
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
                isProtected: tab.isProtected,
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
                load(url, in: webView)
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
        let selectedWebView = selectedTab?.webView
        var retained: [Tab] = []
        let snapshots = tabs.compactMap { tab -> ClosedTabSnapshot? in
            if tab.isProtected {
                retained.append(tab)
                return nil
            }
            return ClosedTabSnapshot(
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
        tabs = retained
        if tabs.isEmpty {
            newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
            return
        }
        if let selectedWebView,
           let retainedIndex = tabs.firstIndex(where: { $0.webView === selectedWebView }) {
            selectedIndex = retainedIndex
        } else {
            selectedIndex = 0
        }
        selectedSidebarTabID = selectedTab?.id
        syncAddressBar()
        saveSessionSnapshot()
    }

    func restoreClosedTab() {
        guard let snapshot = closedTabs.first else { return }
        closedTabs.removeFirst()
        let shouldRestoreHistory = PadBrowserPreferences.shared.restoreClosedTabPageHistory
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
              !snapshot.tabs.isEmpty else {
            return
        }

        for tabSnapshot in snapshot.tabs {
            let webView = makeWebView()
            let tab = Tab(webView: webView)
            tab.title = tabSnapshot.title
            tab.urlString = tabSnapshot.urlString ?? ""
            tab.isProtected = tabSnapshot.isProtected
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
                load(initialURL, in: webView)
            } else {
                loadStartPage(in: webView)
            }
        }

        selectedIndex = min(max(0, snapshot.selectedIndex), tabs.count - 1)
        syncAddressBar()
    }

    private func saveSessionSnapshot() {
        let defaults = PadBrowserPreferences.shared.userDefaultsForCurrentProfile()
        guard PadBrowserPreferences.shared.reopenTabsOnLaunch else {
            defaults.removeObject(forKey: "browser.session.snapshot")
            return
        }
        let snapshot = SessionSnapshot(
            selectedIndex: min(max(0, selectedIndex), max(tabs.count - 1, 0)),
            tabs: tabs.map { tab in
                SessionTabSnapshot(
                    urlString: tab.webView.url?.absoluteString ?? (tab.urlString.isEmpty ? nil : tab.urlString),
                    title: tab.title,
                    isProtected: tab.isProtected,
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
          --bg0: #eef3f9;
          --bg1: #dfe7f2;
          --glass: rgba(255,255,255,0.62);
          --stroke: rgba(255,255,255,0.54);
          --text: #0f172a;
          --subtle: rgba(15,23,42,0.58);
          --field: rgba(255,255,255,0.82);
          --fieldStroke: rgba(148,163,184,0.30);
          --strong: #0f172a;
          --strongText: #ffffff;
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
          padding: 26px;
        }
        .panel {
          width: min(700px, calc(100vw - 32px));
          padding: 34px 28px 28px;
          border-radius: 32px;
          background: var(--glass);
          border: 1px solid var(--stroke);
          backdrop-filter: blur(28px) saturate(1.25);
          box-shadow: 0 28px 80px var(--shadow);
        }
        .brand {
          margin: 0 0 22px;
          font-size: clamp(34px, 5vw, 52px);
          font-weight: 700;
          line-height: 0.98;
          letter-spacing: -0.05em;
        }
        form {
          display: flex;
          align-items: center;
          gap: 12px;
        }
        .search {
          flex: 1 1 auto;
          width: 100%;
          height: 64px;
          padding: 0 20px;
          border-radius: 22px;
          border: 1px solid var(--fieldStroke);
          background: var(--field);
          color: var(--text);
          font-size: 18px;
          outline: none;
        }
        .search::placeholder { color: color-mix(in srgb, var(--subtle) 78%, transparent); }
        .search:focus {
          border-color: rgba(96,165,250,0.42);
          box-shadow: 0 0 0 5px rgba(96,165,250,0.12);
        }
        button {
          width: 64px;
          height: 64px;
          flex: 0 0 64px;
          padding: 0;
          border-radius: 22px;
          border: 0;
          background: var(--strong);
          color: var(--strongText);
          font: 600 23px -apple-system, BlinkMacSystemFont, sans-serif;
        }
        @media (max-width: 640px) {
          .panel {
            width: min(100%, calc(100vw - 22px));
            padding: 28px 18px 18px;
            border-radius: 28px;
          }
          .brand { font-size: 34px; }
          .search, button {
            height: 58px;
            border-radius: 19px;
          }
          button {
            width: 58px;
            flex-basis: 58px;
            font-size: 21px;
          }
        }
        </style>
        <body>
          <div class="shell">
            <div class="panel">
              <div class="brand">Vidarr</div>
              <form id="searchForm">
                <input id="query" class="search" type="search" placeholder="検索語または URL を入力" autocomplete="off" spellcheck="false" />
                <button type="submit" aria-label="Open">↵</button>
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
        let webView = makeWebView()
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
        tabs.append(tab)
        selectedIndex = tabs.count - 1
        selectedSidebarTabID = tab.id
        loadStartPage(in: webView, initialQuery: initialQuery)
        captureThumbnail(for: tab)
        syncAddressBar()
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
            guard let self, let tab = self.tabs.first(where: { $0.webView === webView }) else { return }
            let isInternalBlankPage = webView.url?.host == self.startPageBaseURL.host
            tab.title = isInternalBlankPage
                ? "Vidarr Start"
                : (webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? (webView.title ?? "Vidarr Start")
                    : (webView.url?.host ?? webView.url?.absoluteString ?? "Vidarr Start"))
            tab.urlString = isInternalBlankPage ? "" : (webView.url?.absoluteString ?? "")
            if let url = webView.url, !isInternalBlankPage {
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

    static let harmfulHosts: Set<String> = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "adservice.google.co.jp", "amazon-adsystem.com", "connect.facebook.net", "bat.bing.com",
        "taboola.com", "outbrain.com", "adf.ly", "bit.ly", "tinyurl.com"
    ]

    static let harmfulTLDs: Set<String> = ["zip", "mov", "click", "country", "gq", "work", "download", "stream"]
}
