import Foundation
import VidarrCore
import WebKit

final class WebContentBlocker {
    static let shared = WebContentBlocker()

    private let ruleListIdentifier = "VidarrContentBlockRules"
    private var cachedRuleList: WKContentRuleList?
    private var cachedRuleSource: String?
    private var isCompiling = false
    private var pending: [(WKContentRuleList?) -> Void] = []

    private init() {}

    func configure(userContentController controller: WKUserContentController) {
        installPrivacyScripts(on: controller)
        applyContentRulesIfNeeded(to: controller)
    }

    private func applyContentRulesIfNeeded(to controller: WKUserContentController) {
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

    private func installPrivacyScripts(on controller: WKUserContentController) {
        if BrowserPreferences.shared.popupBlockingEnabled {
            controller.addUserScript(
                WKUserScript(
                    source: Self.popupProtectionScriptSource,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
            )
        }
    }

    private func loadRuleList(completion: @escaping (WKContentRuleList?) -> Void) {
        let encodedRules = Self.makeEncodedRules(disabledHosts: BrowserPreferences.shared.contentBlockingDisabledHosts)
        if let cachedRuleList, cachedRuleSource == encodedRules {
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
            encodedContentRuleList: encodedRules
        ) { [weak self] list, _ in
            guard let self else { return }
            self.cachedRuleList = list
            self.cachedRuleSource = encodedRules
            self.isCompiling = false
            let callbacks = self.pending
            self.pending.removeAll()
            callbacks.forEach { $0(list) }
        }
    }

    private static let popupProtectionScriptSource = """
    (() => {
      if (window.__vidarrPopupGuardInstalled) return;
      Object.defineProperty(window, '__vidarrPopupGuardInstalled', {
        value: true,
        configurable: false,
        enumerable: false,
        writable: false
      });

      const nativeOpen = window.open.bind(window);
      let lastTrustedUserEventAt = 0;
      const markUserGesture = () => { lastTrustedUserEventAt = Date.now(); };
      const activationWindowMs = 1400;

      ['pointerdown', 'mousedown', 'mouseup', 'touchstart', 'touchend', 'keydown', 'click'].forEach((name) => {
        window.addEventListener(name, markUserGesture, true);
        document.addEventListener(name, markUserGesture, true);
      });

      const hasUserActivation = () => {
        try {
          if (navigator.userActivation && navigator.userActivation.isActive) return true;
        } catch (_) {}
        try {
          if (document.hasTransientActivation) return true;
        } catch (_) {}
        return (Date.now() - lastTrustedUserEventAt) <= activationWindowMs;
      };

      window.open = function(...args) {
        if (!hasUserActivation()) {
          return null;
        }
        return nativeOpen(...args);
      };
    })();
    """

    private static let blockedDomains: [String] = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adservice.google.com",
        "adservice.google.co.jp",
        "googletagmanager.com",
        "google-analytics.com",
        "analytics.google.com",
        "googletagservices.com",
        "adnxs.com",
        "adsrvr.org",
        "advertising.com",
        "amazon-adsystem.com",
        "criteo.com",
        "criteo.net",
        "taboola.com",
        "outbrain.com",
        "openx.net",
        "pubmatic.com",
        "rubiconproject.com",
        "moatads.com",
        "scorecardresearch.com",
        "quantserve.com",
        "zedo.com",
        "yieldmo.com",
        "casalemedia.com",
        "lijit.com",
        "sharethrough.com",
        "smartadserver.com",
        "adsystem.com",
        "serving-sys.com",
        "sitescout.com",
        "hotjar.com",
        "segment.io",
        "segment.com",
        "mixpanel.com",
        "newrelic.com",
        "facebook.net",
        "connect.facebook.net",
        "bat.bing.com",
        "branch.io",
        "appsflyer.com",
        "amplitude.com",
        "mouseflow.com",
        "clarity.ms",
        "omtrdc.net",
        "demdex.net"
    ]

    private static let adScriptPatterns: [String] = [
        "https?://[^/]*google-analytics\\.com/.*",
        "https?://[^/]*googletagmanager\\.com/.*",
        "https?://[^/]*doubleclick\\.net/.*",
        "https?://[^/]*googlesyndication\\.com/.*",
        "https?://[^/]*googleadservices\\.com/.*",
        "https?://[^/]*amazon-adsystem\\.com/.*",
        "https?://[^/]*facebook\\.net/.*",
        "https?://[^/]*connect\\.facebook\\.net/.*",
        "https?://[^/]*bat\\.bing\\.com/.*",
        "https?://[^/]*hotjar\\.com/.*",
        "https?://[^/]*clarity\\.ms/.*",
        "https?://[^/]*(analytics|tracking|telemetry|metrics|beacon|ads)[^/]*\\..*"
    ]

    private static let hideSelectors = [
        "[id^='google_ads']",
        "[id^='div-gpt-ad']",
        "[id^='taboola-']",
        "[id^='outbrain']",
        "[class*='advert']",
        "[class*='ad-slot']",
        "[class*='adsbygoogle']",
        "[class*='sponsored']",
        "[data-ad]",
        "[data-ad-container]",
        "[data-testid='ad']",
        "iframe[src*='doubleclick.net']",
        "iframe[src*='googlesyndication.com']",
        "iframe[id^='google_ads_iframe']"
    ].joined(separator: ", ")

    private static func makeEncodedRules(disabledHosts: Set<String>) -> String {
        var rules: [[String: Any]] = []
        let excludedHosts = disabledHosts.sorted()

        rules.append([
            "trigger": makeTrigger([
                "url-filter": ".*",
                "if-domain": blockedDomains
            ], excludedHosts: excludedHosts),
            "action": ["type": "block"]
        ])

        for pattern in adScriptPatterns {
            rules.append([
                "trigger": makeTrigger([
                    "url-filter": pattern
                ], excludedHosts: excludedHosts),
                "action": ["type": "block"]
            ])
        }

        rules.append([
            "trigger": makeTrigger([
                "url-filter": "https?://.*(adservice|doubleclick|googlesyndication|analytics|tracking|telemetry|metrics|beacon|pixel|sponsor|affiliate|promo).*",
                "resource-type": ["script", "raw", "image", "style-sheet"],
                "load-type": ["third-party"],
                "url-filter-is-case-sensitive": false
            ], excludedHosts: excludedHosts),
            "action": ["type": "block"]
        ])

        rules.append([
            "trigger": makeTrigger([
                "url-filter": ".*",
                "resource-type": ["popup"]
            ], excludedHosts: excludedHosts),
            "action": ["type": "block"]
        ])

        rules.append([
            "trigger": makeTrigger([
                "url-filter": ".*"
            ], excludedHosts: excludedHosts),
            "action": [
                "type": "css-display-none",
                "selector": hideSelectors
            ]
        ])

        let data = try? JSONSerialization.data(withJSONObject: rules, options: [])
        return String(data: data ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    private static func makeTrigger(_ base: [String: Any], excludedHosts: [String]) -> [String: Any] {
        guard !excludedHosts.isEmpty else { return base }
        var trigger = base
        trigger["unless-domain"] = excludedHosts
        return trigger
    }
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
