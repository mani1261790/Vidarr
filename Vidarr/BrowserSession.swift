import Foundation
import WebKit

/// 現在タブの WKWebView 操作と共通設定を提供するセッション層。
final class BrowserSession {
    static let defaultHomeURL = URL(string: "https://search.fenrir-inc.com/")!

    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    var currentWebView: WKWebView? {
        tabManager.currentWebView
    }

    static func makeConfiguredWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
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
            webView.load(URLRequest(url: url))
        }
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
