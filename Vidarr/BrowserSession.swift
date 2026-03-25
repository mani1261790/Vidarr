import Foundation
import WebKit

/// 現在タブの WKWebView 操作と共通設定を提供するセッション層。
final class BrowserSession {
    static var defaultHomeURL: URL {
        BrowserPreferences.shared.homePageURL
    }

    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    var currentWebView: WKWebView? {
        tabManager.currentWebView
    }

    static func makeConfiguredWebView(for group: BrowserTabGroup = .regular) -> WKWebView {
        let prefs = BrowserPreferences.shared
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = !prefs.popupBlockingEnabled
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let useEphemeralStore = (group == .privateMode) || prefs.ephemeralModeEnabled
        config.websiteDataStore = useEphemeralStore ? .nonPersistent() : .default()

        if prefs.sendDoNotTrack {
            let source = """
            Object.defineProperty(navigator, 'doNotTrack', { get: () => '1' });
            Object.defineProperty(navigator, 'globalPrivacyControl', { get: () => true });
            """
            let script = WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
        }

        if let language = prefs.preferredContentLanguage.navigatorLanguage {
            let primaryLanguage = language.components(separatedBy: "-").first ?? language
            let source = """
            Object.defineProperty(navigator, 'language', { get: () => '\(language)' });
            Object.defineProperty(navigator, 'languages', { get: () => ['\(language)', '\(primaryLanguage)'] });
            try { document.documentElement.setAttribute('lang', '\(primaryLanguage)'); } catch (_) {}
            """
            let script = WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(script)
        }

        WebContentBlocker.shared.configure(userContentController: config.userContentController)

        let webView = WKWebView(frame: .zero, configuration: config)
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }

    // MARK: - Navigation
    func goBack() {
        performOnMain { [weak self] in
            guard let webView = self?.currentWebView, webView.canGoBack else { return }
            webView.goBack()
        }
    }

    func goForward() {
        performOnMain { [weak self] in
            guard let webView = self?.currentWebView, webView.canGoForward else { return }
            webView.goForward()
        }
    }

    func reload() {
        performOnMain { [weak self] in
            self?.currentWebView?.reload()
        }
    }

    func load(url: URL) {
        performOnMain { [weak self] in
            guard let webView = self?.currentWebView else { return }
            Self.load(url: url, in: webView)
        }
    }

    static func load(url: URL, in webView: WKWebView) {
        if url.isFileURL {
            let readAccessURL: URL
            if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
               resourceValues.isDirectory == true {
                readAccessURL = url
            } else {
                readAccessURL = url.deletingLastPathComponent()
            }
            webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
            return
        }

        webView.load(URLRequest(url: url))
    }

    // MARK: - Helpers
    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
