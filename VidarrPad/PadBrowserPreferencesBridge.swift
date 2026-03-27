import Foundation
import CoreGraphics

struct PadBrowserProfile: Codable, Hashable, Identifiable {
    let id: String
    var name: String

    static let `default` = PadBrowserProfile(id: "default", name: "Default")
}

enum PadGestureSensitivity: String, CaseIterable {
    case low
    case normal
    case high

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .low: return 0.85
        case .normal: return 1.0
        case .high: return 1.18
        }
    }
}

enum PadPreferredContentLanguage: String, CaseIterable {
    case system
    case japanese
    case english

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .japanese: return "Japanese"
        case .english: return "English"
        }
    }
}

enum PadCookiePolicy: String, CaseIterable {
    case standard
    case privateOnly

    var displayName: String {
        switch self {
        case .standard: return "通常"
        case .privateOnly: return "毎回プライベート"
        }
    }
}

enum PadBottomBarAutoHideDelay: String, CaseIterable {
    case short
    case normal
    case long

    var displayName: String {
        switch self {
        case .short: return "短め"
        case .normal: return "標準"
        case .long: return "長め"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .short: return 1.2
        case .normal: return 2.0
        case .long: return 3.2
        }
    }
}

final class PadBrowserPreferences {
    static let shared = PadBrowserPreferences()

    private enum Key {
        static let profiles = "profiles.items"
        static let currentProfileID = "profiles.currentID"
        static let homePageURL = "prefs.homePageURL"
        static let searchTemplate = "prefs.searchTemplate"
        static let preferredContentLanguage = "prefs.preferredContentLanguage"
        static let gestureSensitivity = "prefs.gestureSensitivity"
        static let restoreClosedTabPageHistory = "prefs.restoreClosedTabPageHistory"
        static let autoHideBottomBar = "prefs.autoHideBottomBar"
        static let bottomBarAutoHideDelay = "prefs.bottomBarAutoHideDelay"
        static let allowsJavaScript = "prefs.allowsJavaScript"
        static let stripTrackingParameters = "prefs.stripTrackingParameters"
        static let harmfulSiteWarningEnabled = "prefs.harmfulSiteWarningEnabled"
        static let preferHTTPS = "prefs.preferHTTPS"
        static let cookiePolicy = "prefs.cookiePolicy"
    }

    private var defaults: UserDefaults {
        userDefaultsForCurrentProfile()
    }

    var currentProfile: PadBrowserProfile {
        let registryDefaults = UserDefaults.standard
        let currentID = registryDefaults.string(forKey: Key.currentProfileID) ?? PadBrowserProfile.default.id
        return allProfiles().first(where: { $0.id == currentID }) ?? .default
    }

    func allProfiles() -> [PadBrowserProfile] {
        let registryDefaults = UserDefaults.standard
        guard let data = registryDefaults.data(forKey: Key.profiles),
              let decoded = try? JSONDecoder().decode([PadBrowserProfile].self, from: data),
              !decoded.isEmpty else {
            return [.default]
        }
        if decoded.contains(where: { $0.id == PadBrowserProfile.default.id }) {
            return decoded
        }
        return [.default] + decoded
    }

    var homePageURLString: String {
        get { defaults.string(forKey: Key.homePageURL) ?? "https://search.fenrir-inc.com/" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.homePageURL) }
    }

    var searchTemplate: String {
        get { defaults.string(forKey: Key.searchTemplate) ?? "https://search.fenrir-inc.com/?q={query}" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.searchTemplate) }
    }

    var preferredContentLanguage: PadPreferredContentLanguage {
        get {
            let raw = defaults.string(forKey: Key.preferredContentLanguage) ?? PadPreferredContentLanguage.system.rawValue
            return PadPreferredContentLanguage(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.preferredContentLanguage)
        }
    }

    var gestureSensitivity: PadGestureSensitivity {
        get {
            let raw = defaults.string(forKey: Key.gestureSensitivity) ?? PadGestureSensitivity.normal.rawValue
            return PadGestureSensitivity(rawValue: raw) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.gestureSensitivity)
        }
    }

    var restoreClosedTabPageHistory: Bool {
        get {
            if defaults.object(forKey: Key.restoreClosedTabPageHistory) == nil {
                return true
            }
            return defaults.bool(forKey: Key.restoreClosedTabPageHistory)
        }
        set {
            defaults.set(newValue, forKey: Key.restoreClosedTabPageHistory)
        }
    }

    var autoHideBottomBar: Bool {
        get {
            if defaults.object(forKey: Key.autoHideBottomBar) == nil {
                return true
            }
            return defaults.bool(forKey: Key.autoHideBottomBar)
        }
        set {
            defaults.set(newValue, forKey: Key.autoHideBottomBar)
        }
    }

    var bottomBarAutoHideDelay: PadBottomBarAutoHideDelay {
        get {
            let raw = defaults.string(forKey: Key.bottomBarAutoHideDelay) ?? PadBottomBarAutoHideDelay.normal.rawValue
            return PadBottomBarAutoHideDelay(rawValue: raw) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.bottomBarAutoHideDelay)
        }
    }

    var allowsJavaScript: Bool {
        get {
            if defaults.object(forKey: Key.allowsJavaScript) == nil {
                return true
            }
            return defaults.bool(forKey: Key.allowsJavaScript)
        }
        set {
            defaults.set(newValue, forKey: Key.allowsJavaScript)
        }
    }

    var stripTrackingParameters: Bool {
        get {
            if defaults.object(forKey: Key.stripTrackingParameters) == nil {
                return true
            }
            return defaults.bool(forKey: Key.stripTrackingParameters)
        }
        set {
            defaults.set(newValue, forKey: Key.stripTrackingParameters)
        }
    }

    var harmfulSiteWarningEnabled: Bool {
        get {
            if defaults.object(forKey: Key.harmfulSiteWarningEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Key.harmfulSiteWarningEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.harmfulSiteWarningEnabled)
        }
    }

    var preferHTTPS: Bool {
        get {
            if defaults.object(forKey: Key.preferHTTPS) == nil {
                return true
            }
            return defaults.bool(forKey: Key.preferHTTPS)
        }
        set {
            defaults.set(newValue, forKey: Key.preferHTTPS)
        }
    }

    var cookiePolicy: PadCookiePolicy {
        get {
            let raw = defaults.string(forKey: Key.cookiePolicy) ?? PadCookiePolicy.standard.rawValue
            return PadCookiePolicy(rawValue: raw) ?? .standard
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.cookiePolicy)
        }
    }

    var homePageURL: URL {
        if let url = URL(string: homePageURLString), url.scheme != nil {
            return url
        }
        return URL(string: "https://search.fenrir-inc.com/")!
    }

    func searchURL(for query: String) -> URL {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let rawURL = searchTemplate.contains("{query}")
            ? searchTemplate.replacingOccurrences(of: "{query}", with: encodedQuery)
            : "\(searchTemplate)\(encodedQuery)"
        return URL(string: rawURL) ?? URL(string: "https://search.fenrir-inc.com/?q=\(encodedQuery)")!
    }

    func normalizedNavigableURL(from url: URL) -> URL {
        var normalized = url
        if preferHTTPS,
           normalized.scheme?.lowercased() == "http",
           var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let httpsURL = components.url {
                normalized = httpsURL
            }
        }

        if stripTrackingParameters,
           let scheme = normalized.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false),
           let items = components.queryItems,
           !items.isEmpty {
            let filtered = items.filter { !Self.trackingQueryKeys.contains($0.name.lowercased()) }
            if filtered.count != items.count {
                components.queryItems = filtered.isEmpty ? nil : filtered
                if let filteredURL = components.url {
                    normalized = filteredURL
                }
            }
        }

        return normalized
    }

    private static let trackingQueryKeys: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "mkt_tok",
        "igshid", "yclid", "_openstat", "vero_conv", "vero_id", "wickedid",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id"
    ]

    func userDefaultsForCurrentProfile() -> UserDefaults {
        let profile = currentProfile
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "dev.mani.VidarrPad"
        let suiteName = "\(bundleIdentifier).profile.\(profile.id)"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}

struct PadBrowsingItem: Codable, Identifiable {
    var id: String { urlString }
    let urlString: String
    var title: String
    var visitedAt: Date
}

final class PadBrowsingHistoryStore {
    static let shared = PadBrowsingHistoryStore()

    private enum Key {
        static let historyItems = "history.items"
    }

    private var defaults: UserDefaults {
        PadBrowserPreferences.shared.userDefaultsForCurrentProfile()
    }

    func all() -> [PadBrowsingItem] {
        guard let data = defaults.data(forKey: Key.historyItems),
              let decoded = try? JSONDecoder().decode([PadBrowsingItem].self, from: data) else {
            return []
        }
        return decoded
    }

    func recordVisit(url: URL, title: String?) {
        var items = all()
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (title ?? "") : (url.host ?? url.absoluteString)
        let item = PadBrowsingItem(urlString: url.absoluteString, title: resolvedTitle, visitedAt: Date())
        items.removeAll { $0.urlString == item.urlString }
        items.insert(item, at: 0)
        if items.count > 250 {
            items.removeLast(items.count - 250)
        }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Key.historyItems)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Key.historyItems)
    }
}

final class PadBookmarkStore {
    static let shared = PadBookmarkStore()

    private enum Key {
        static let bookmarkItems = "bookmarks.items"
    }

    private var defaults: UserDefaults {
        PadBrowserPreferences.shared.userDefaultsForCurrentProfile()
    }

    func all() -> [PadBrowsingItem] {
        guard let data = defaults.data(forKey: Key.bookmarkItems),
              let decoded = try? JSONDecoder().decode([PadBrowsingItem].self, from: data) else {
            return []
        }
        return decoded
    }

    func toggle(url: URL, title: String?) {
        var items = all()
        if items.contains(where: { $0.urlString == url.absoluteString }) {
            items.removeAll { $0.urlString == url.absoluteString }
        } else {
            let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (title ?? "") : (url.host ?? url.absoluteString)
            items.insert(PadBrowsingItem(urlString: url.absoluteString, title: resolvedTitle, visitedAt: Date()), at: 0)
        }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Key.bookmarkItems)
        }
    }

    func contains(url: URL?) -> Bool {
        guard let url else { return false }
        return all().contains { $0.urlString == url.absoluteString }
    }

    func clear() {
        defaults.removeObject(forKey: Key.bookmarkItems)
    }
}
