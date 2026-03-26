import Foundation

final class BrowserPreferences {
    static let shared = BrowserPreferences()
    static let didChangeNotification = Notification.Name("BrowserPreferencesDidChange")

    enum PreferredContentLanguage: String, CaseIterable {
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

        var navigatorLanguage: String? {
            switch self {
            case .system: return nil
            case .japanese: return "ja-JP"
            case .english: return "en-US"
            }
        }
    }

    enum GestureSensitivity: String, CaseIterable {
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

        // >1.0 makes gesture capture easier, <1.0 makes stricter.
        var multiplier: CGFloat {
            switch self {
            case .low: return 0.85
            case .normal: return 1.0
            case .high: return 1.18
            }
        }
    }

    private enum Key {
        static let homePageURL = "prefs.homePageURL"
        static let searchTemplate = "prefs.searchTemplate"
        static let updatesEnabled = "prefs.updatesEnabled"
        static let preferredContentLanguage = "prefs.preferredContentLanguage"
        static let preferredDownloadDirectoryBookmark = "prefs.preferredDownloadDirectoryBookmark"
        static let preferredDownloadDirectoryPath = "prefs.preferredDownloadDirectoryPath"
        static let gestureSensitivity = "prefs.gestureSensitivity"
        static let antiTrackingEnabled = "prefs.antiTrackingEnabled"
        static let contentBlockingEnabled = "prefs.contentBlockingEnabled"
        static let contentBlockingDisabledHosts = "prefs.contentBlockingDisabledHosts"
        static let harmfulSiteAllowedHosts = "prefs.harmfulSiteAllowedHosts"
        static let popupBlockingEnabled = "prefs.popupBlockingEnabled"
        static let harmfulSiteWarningEnabled = "prefs.harmfulSiteWarningEnabled"
        static let ephemeralModeEnabled = "prefs.ephemeralModeEnabled"
        static let sendDoNotTrack = "prefs.sendDoNotTrack"
        static let restoreClosedTabPageHistory = "prefs.restoreClosedTabPageHistory"
    }

    private let defaults: UserDefaults
    private var isBatchUpdating = false
    private var needsNotifyChanged = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.homePageURL: "https://search.fenrir-inc.com/",
            Key.searchTemplate: "https://search.fenrir-inc.com/?q={query}",
            Key.updatesEnabled: true,
            Key.preferredContentLanguage: PreferredContentLanguage.system.rawValue,
            Key.gestureSensitivity: GestureSensitivity.normal.rawValue,
            Key.antiTrackingEnabled: true,
            Key.contentBlockingEnabled: true,
            Key.contentBlockingDisabledHosts: [],
            Key.harmfulSiteAllowedHosts: [],
            Key.popupBlockingEnabled: true,
            Key.harmfulSiteWarningEnabled: true,
            Key.ephemeralModeEnabled: false,
            Key.sendDoNotTrack: true,
            Key.restoreClosedTabPageHistory: true
        ])
    }

    var homePageURLString: String {
        get { defaults.string(forKey: Key.homePageURL) ?? "https://search.fenrir-inc.com/" }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.homePageURL)
            notifyChanged()
        }
    }

    var searchTemplate: String {
        get { defaults.string(forKey: Key.searchTemplate) ?? "https://search.fenrir-inc.com/?q={query}" }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.searchTemplate)
            notifyChanged()
        }
    }

    var updatesEnabled: Bool {
        get { defaults.bool(forKey: Key.updatesEnabled) }
        set {
            defaults.set(newValue, forKey: Key.updatesEnabled)
            notifyChanged()
        }
    }

    var preferredContentLanguage: PreferredContentLanguage {
        get {
            let raw = defaults.string(forKey: Key.preferredContentLanguage) ?? PreferredContentLanguage.system.rawValue
            return PreferredContentLanguage(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.preferredContentLanguage)
            notifyChanged()
        }
    }

    var preferredDownloadDirectoryPath: String? {
        defaults.string(forKey: Key.preferredDownloadDirectoryPath)
    }

    func preferredDownloadDirectoryURL() -> URL? {
        guard let data = defaults.data(forKey: Key.preferredDownloadDirectoryBookmark) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            _ = try? setPreferredDownloadDirectory(url)
        }
        return url
    }

    @discardableResult
    func setPreferredDownloadDirectory(_ url: URL?) throws -> URL? {
        if let url {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Key.preferredDownloadDirectoryBookmark)
            defaults.set(url.path, forKey: Key.preferredDownloadDirectoryPath)
            notifyChanged()
            return url
        } else {
            defaults.removeObject(forKey: Key.preferredDownloadDirectoryBookmark)
            defaults.removeObject(forKey: Key.preferredDownloadDirectoryPath)
            notifyChanged()
            return nil
        }
    }

    var gestureSensitivity: GestureSensitivity {
        get {
            let raw = defaults.string(forKey: Key.gestureSensitivity) ?? GestureSensitivity.normal.rawValue
            return GestureSensitivity(rawValue: raw) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.gestureSensitivity)
            notifyChanged()
        }
    }

    var antiTrackingEnabled: Bool {
        get { defaults.bool(forKey: Key.antiTrackingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.antiTrackingEnabled)
            notifyChanged()
        }
    }

    var contentBlockingEnabled: Bool {
        get { defaults.bool(forKey: Key.contentBlockingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.contentBlockingEnabled)
            notifyChanged()
        }
    }

    var popupBlockingEnabled: Bool {
        get { defaults.bool(forKey: Key.popupBlockingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.popupBlockingEnabled)
            notifyChanged()
        }
    }

    var contentBlockingDisabledHosts: Set<String> {
        get {
            let values = defaults.array(forKey: Key.contentBlockingDisabledHosts) as? [String] ?? []
            return Set(values.compactMap(Self.normalizeHost(_:)))
        }
        set {
            let normalized = newValue.compactMap(Self.normalizeHost(_:)).sorted()
            defaults.set(normalized, forKey: Key.contentBlockingDisabledHosts)
            notifyChanged()
        }
    }

    var harmfulSiteAllowedHosts: Set<String> {
        get {
            let values = defaults.array(forKey: Key.harmfulSiteAllowedHosts) as? [String] ?? []
            return Set(values.compactMap(Self.normalizeHost(_:)))
        }
        set {
            let normalized = newValue.compactMap(Self.normalizeHost(_:)).sorted()
            defaults.set(normalized, forKey: Key.harmfulSiteAllowedHosts)
            notifyChanged()
        }
    }

    var harmfulSiteWarningEnabled: Bool {
        get { defaults.bool(forKey: Key.harmfulSiteWarningEnabled) }
        set {
            defaults.set(newValue, forKey: Key.harmfulSiteWarningEnabled)
            notifyChanged()
        }
    }

    var ephemeralModeEnabled: Bool {
        get { defaults.bool(forKey: Key.ephemeralModeEnabled) }
        set {
            defaults.set(newValue, forKey: Key.ephemeralModeEnabled)
            notifyChanged()
        }
    }

    var sendDoNotTrack: Bool {
        get { defaults.bool(forKey: Key.sendDoNotTrack) }
        set {
            defaults.set(newValue, forKey: Key.sendDoNotTrack)
            notifyChanged()
        }
    }

    var restoreClosedTabPageHistory: Bool {
        get { defaults.bool(forKey: Key.restoreClosedTabPageHistory) }
        set {
            defaults.set(newValue, forKey: Key.restoreClosedTabPageHistory)
            notifyChanged()
        }
    }

    var homePageURL: URL {
        if let url = URL(string: homePageURLString), url.scheme != nil {
            return url
        }
        return URL(string: "https://search.fenrir-inc.com/")!
    }

    func searchURL(for query: String) -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedQuery = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let template = searchTemplate.isEmpty ? "https://search.fenrir-inc.com/?q={query}" : searchTemplate

        if template.contains("{query}") {
            let resolved = template.replacingOccurrences(of: "{query}", with: encodedQuery)
            if let url = URL(string: resolved), url.scheme != nil {
                return url
            }
        } else if let url = URL(string: template), url.scheme != nil {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var items = components.queryItems ?? []
                items.append(URLQueryItem(name: "q", value: trimmed))
                components.queryItems = items
                if let resolved = components.url {
                    return resolved
                }
            }
        }

        var fallback = URLComponents(string: "https://search.fenrir-inc.com/")!
        fallback.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return fallback.url!
    }

    func resetDefaults() {
        performBatchUpdate {
            defaults.set("https://search.fenrir-inc.com/", forKey: Key.homePageURL)
            defaults.set("https://search.fenrir-inc.com/?q={query}", forKey: Key.searchTemplate)
            defaults.set(true, forKey: Key.updatesEnabled)
            defaults.set(PreferredContentLanguage.system.rawValue, forKey: Key.preferredContentLanguage)
            defaults.removeObject(forKey: Key.preferredDownloadDirectoryBookmark)
            defaults.removeObject(forKey: Key.preferredDownloadDirectoryPath)
            defaults.set(GestureSensitivity.normal.rawValue, forKey: Key.gestureSensitivity)
            defaults.set(true, forKey: Key.antiTrackingEnabled)
            defaults.set(true, forKey: Key.contentBlockingEnabled)
            defaults.set([], forKey: Key.contentBlockingDisabledHosts)
            defaults.set([], forKey: Key.harmfulSiteAllowedHosts)
            defaults.set(true, forKey: Key.popupBlockingEnabled)
            defaults.set(true, forKey: Key.harmfulSiteWarningEnabled)
            defaults.set(false, forKey: Key.ephemeralModeEnabled)
            defaults.set(true, forKey: Key.sendDoNotTrack)
            defaults.set(true, forKey: Key.restoreClosedTabPageHistory)
        }
    }

    func isContentBlockingDisabled(for host: String) -> Bool {
        guard let normalized = Self.normalizeHost(host) else { return false }
        return contentBlockingDisabledHosts.contains(normalized)
    }

    func setContentBlockingDisabled(_ disabled: Bool, for host: String) {
        guard let normalized = Self.normalizeHost(host) else { return }
        var hosts = contentBlockingDisabledHosts
        if disabled {
            hosts.insert(normalized)
        } else {
            hosts.remove(normalized)
        }
        contentBlockingDisabledHosts = hosts
    }

    var contentBlockingExceptionSignature: String {
        contentBlockingDisabledHosts.sorted().joined(separator: "|")
    }

    func isHarmfulSiteAllowed(for host: String) -> Bool {
        guard let normalized = Self.normalizeHost(host) else { return false }
        return harmfulSiteAllowedHosts.contains(normalized)
    }

    func setHarmfulSiteAllowed(_ allowed: Bool, for host: String) {
        guard let normalized = Self.normalizeHost(host) else { return }
        var hosts = harmfulSiteAllowedHosts
        if allowed {
            hosts.insert(normalized)
        } else {
            hosts.remove(normalized)
        }
        harmfulSiteAllowedHosts = hosts
    }

    nonisolated private static func normalizeHost(_ host: String) -> String? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func notifyChanged() {
        if isBatchUpdating {
            needsNotifyChanged = true
            return
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func performBatchUpdate(_ updates: () -> Void) {
        isBatchUpdating = true
        updates()
        isBatchUpdating = false

        if needsNotifyChanged {
            needsNotifyChanged = false
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}
