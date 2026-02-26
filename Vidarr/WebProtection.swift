import Foundation
import WebKit

final class WebContentBlocker {
    static let shared = WebContentBlocker()

    private let ruleListIdentifier = "VidarrContentBlockRules"
    private var cachedRuleList: WKContentRuleList?
    private var isCompiling = false
    private var pending: [(WKContentRuleList?) -> Void] = []

    private init() {}

    func applyIfEnabled(to controller: WKUserContentController) {
        guard BrowserPreferences.shared.contentBlockingEnabled else {
            controller.removeAllContentRuleLists()
            return
        }

        loadRuleList { ruleList in
            guard let ruleList else { return }
            controller.removeAllContentRuleLists()
            controller.add(ruleList)
        }
    }

    private func loadRuleList(completion: @escaping (WKContentRuleList?) -> Void) {
        if let cachedRuleList {
            completion(cachedRuleList)
            return
        }

        pending.append(completion)
        guard !isCompiling else { return }
        isCompiling = true

        guard let store = WKContentRuleListStore.default() else {
            isCompiling = false
            let callbacks = pending
            pending.removeAll()
            callbacks.forEach { $0(nil) }
            return
        }
        store.compileContentRuleList(
            forIdentifier: ruleListIdentifier,
            encodedContentRuleList: Self.encodedRules
        ) { [weak self] list, _ in
            guard let self else { return }
            self.cachedRuleList = list
            self.isCompiling = false
            let callbacks = self.pending
            self.pending.removeAll()
            callbacks.forEach { $0(list) }
        }
    }

    private static let encodedRules = """
    [
      {
        "trigger": {
          "url-filter": ".*",
          "if-domain": [
            "doubleclick.net",
            "googlesyndication.com",
            "googleadservices.com",
            "adservice.google.com",
            "adnxs.com",
            "taboola.com",
            "outbrain.com",
            "criteo.com",
            "scorecardresearch.com",
            "zedo.com",
            "pubmatic.com",
            "openx.net",
            "adsrvr.org",
            "tracking-protection.cdn.mozilla.net",
            "amazon-adsystem.com",
            "facebook.net",
            "connect.facebook.net",
            "analytics.yahoo.com",
            "bat.bing.com",
            "hotjar.com",
            "segment.io"
          ]
        },
        "action": { "type": "block" }
      },
      {
        "trigger": {
          "url-filter": ".*",
          "resource-type": ["image"],
          "load-type": ["third-party"],
          "url-filter-is-case-sensitive": false,
          "unless-domain": ["youtube.com", "www.youtube.com"]
        },
        "action": { "type": "block" }
      },
      {
        "trigger": {
          "url-filter": "https?://([a-z0-9-]+\\.)?(google-analytics\\.com|googletagmanager\\.com|stats\\.g\\.doubleclick\\.net)/.*"
        },
        "action": { "type": "block" }
      },
      {
        "trigger": {
          "url-filter": ".*",
          "resource-type": ["script"],
          "if-domain": [
            "google-analytics.com",
            "googletagmanager.com",
            "connect.facebook.net",
            "bat.bing.com",
            "static.hotjar.com"
          ]
        },
        "action": { "type": "block" }
      },
      {
        "trigger": {
          "url-filter": ".*",
          "resource-type": ["style-sheet"],
          "if-domain": ["googlesyndication.com", "doubleclick.net"]
        },
        "action": { "type": "block" }
      }
    ]
    """
}

struct HarmfulSiteWarning {
    let title: String
    let message: String
}

enum HarmfulSiteGuard {
    private static let blockedHosts: Set<String> = [
        "malware.testing.google.test",
        "testsafebrowsing.appspot.com",
        "phishing.testcategory.com"
    ]

    private static let suspiciousTLDs: Set<String> = [
        "zip", "mov", "top", "click", "country", "gq", "work", "download", "stream"
    ]

    private static let suspiciousKeywords: [String] = [
        "login", "verify", "secure", "wallet", "account", "bank", "support", "recovery", "password"
    ]

    static func warning(for url: URL) -> HarmfulSiteWarning? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }

        if blockedHosts.contains(host) {
            return HarmfulSiteWarning(
                title: "危険な可能性のあるサイト",
                message: "このURLは既知の危険ドメインに一致しました。\n\n\(url.absoluteString)"
            )
        }

        let labels = host.split(separator: ".")
        let tld = labels.last.map(String.init) ?? ""
        let hasPunycode = host.contains("xn--")
        let hasKeyword = suspiciousKeywords.contains { host.contains($0) }
        let tooManyLabels = labels.count >= 5

        if suspiciousTLDs.contains(tld), (hasPunycode || hasKeyword || tooManyLabels) {
            return HarmfulSiteWarning(
                title: "注意が必要なサイト",
                message: "フィッシングに使われやすい特徴を検出しました。\n\n\(url.absoluteString)\n\n続行する場合は自己責任でアクセスしてください。"
            )
        }

        return nil
    }
}
