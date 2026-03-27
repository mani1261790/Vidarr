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

        init(webView: WKWebView) {
            self.webView = webView
            super.init()
        }
    }

    struct ClosedTabSnapshot {
        let url: URL?
        let title: String
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

    func newTab(initialURL: URL? = nil) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(webView: webView)
        webView.navigationDelegate = self
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
        closedTabs.insert(ClosedTabSnapshot(url: URL(string: tab.urlString), title: tab.title), at: 0)
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
        selectedTab?.webView.goBack()
    }

    func goForward() {
        selectedTab?.webView.goForward()
    }

    func reload() {
        selectedTab?.webView.reload()
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
            return directURL
        }
        if raw.contains("."), let httpsURL = URL(string: "https://\(raw)") {
            return httpsURL
        }
        return PadBrowserPreferences.shared.searchURL(for: raw)
    }

    func refreshPreferences() {
        if tabs.isEmpty {
            newTab(initialURL: PadBrowserPreferences.shared.homePageURL)
        } else {
            saveSessionSnapshot()
        }
    }

    func closeAllTabs() {
        let snapshots = tabs.map { ClosedTabSnapshot(url: URL(string: $0.urlString), title: $0.title) }
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
        newTab(initialURL: snapshot.url ?? PadBrowserPreferences.shared.homePageURL)
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
        selectedTab?.webView.canGoBack ?? false
    }

    func canGoForward() -> Bool {
        selectedTab?.webView.canGoForward ?? false
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
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            let webView = WKWebView(frame: .zero, configuration: configuration)
            let tab = Tab(webView: webView)
            tab.title = tabSnapshot.title
            tab.urlString = tabSnapshot.urlString ?? ""
            webView.navigationDelegate = self
            tabs.append(tab)
            if let urlString = tabSnapshot.urlString, let url = URL(string: urlString) {
                webView.load(URLRequest(url: url))
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
                    title: tab.title
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
}

extension PadBrowserModel: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, let tab = self.tabs.first(where: { $0.webView === webView }) else { return }
            tab.title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (webView.title ?? "New Tab")
                : (webView.url?.host ?? webView.url?.absoluteString ?? "New Tab")
            tab.urlString = webView.url?.absoluteString ?? ""
            if let url = webView.url {
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
