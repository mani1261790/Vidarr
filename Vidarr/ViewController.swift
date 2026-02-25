//
//  ViewController.swift
//  Vidarr
//
//  Created by 中川誠星 on 2026/02/25.
//

import Cocoa
import WebKit

final class ViewController: NSViewController, TabManagerDelegate {
    private let tabManager = TabManager()
    private let session: BrowserSession

    private let webContainer = NSView()

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        self.session = BrowserSession(tabManager: tabManager)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        self.session = BrowserSession(tabManager: tabManager)
        super.init(coder: coder)
    }

    override func loadView() {
        // ルートビュー
        self.view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // コンテナ追加と制約
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webContainer)
        NSLayoutConstraint.activate([
            webContainer.topAnchor.constraint(equalTo: view.topAnchor),
            webContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // TabManager 配線
        tabManager.delegate = self

        // 最初のタブ作成
        tabManager.newTab(url: URL(string: "https://www.google.com"))
        tabManager.selectTab(index: 0)
    }

    // MARK: - TabManagerDelegate
    func tabManager(_ manager: TabManager, didSelect webView: WKWebView?) {
        // 既存 subviews をクリアして新しい WebView を全面に配置
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let webView = webView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webContainer.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)
        ])
    }

    func tabManager(_ manager: TabManager, didUpdateTabs count: Int) {
        // UI 未実装のためログのみ
        print("Tab count: \(count)")
    }
}
