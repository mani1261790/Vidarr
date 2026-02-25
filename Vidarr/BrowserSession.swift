import Foundation
import WebKit

/// 現在表示中の WKWebView を操作する薄いセッション層。
/// TabManager に依存し、常に現在のタブの WebView を対象に操作します。
final class BrowserSession {
    private unowned let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    /// 現在表示中の WebView（存在しない場合は nil）
    var currentWebView: WKWebView? { tabManager.currentWebView }

    // MARK: - Navigation
    public func goBack() {
        performOnMain { [weak self] in
            guard let webView = self?.currentWebView, webView.canGoBack else { return }
            webView.goBack()
        }
    }

    public func goForward() {
        performOnMain { [weak self] in
            guard let webView = self?.currentWebView, webView.canGoForward else { return }
            webView.goForward()
        }
    }

    public func reload() {
        performOnMain { [weak self] in
            self?.currentWebView?.reload()
        }
    }

    public func load(url: URL) {
        performOnMain { [weak self] in
            guard let webView = self?.currentWebView else { return }
            let req = URLRequest(url: url)
            webView.load(req)
        }
    }

    // MARK: - Helpers
    private func performOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async { work() }
        }
    }
}
