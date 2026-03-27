import Foundation
import CoreGraphics

public final class BrowserPreferences {
    public static var shared = BrowserPreferences()
    public static let didChangeNotification = Notification.Name("BrowserPreferencesDidChange")

    public enum PreferredContentLanguage: String, CaseIterable {
        case system
        case japanese
        case english

        public var displayName: String {
            switch self {
            case .system: return "System Default"
            case .japanese: return "Japanese"
            case .english: return "English"
            }
        }

        public var navigatorLanguage: String? {
            switch self {
            case .system: return nil
            case .japanese: return "ja-JP"
            case .english: return "en-US"
            }
        }
    }

    public enum GestureSensitivity: String, CaseIterable {
        case low
        case normal
        case high

        public var displayName: String {
            switch self {
            case .low: return "Low"
            case .normal: return "Normal"
            case .high: return "High"
            }
        }

        // >1.0 makes gesture capture easier, <1.0 makes stricter.
        public var multiplier: CGFloat {
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
        static let reopenTabsOnLaunch = "prefs.reopenTabsOnLaunch"
    }

    private let defaults: UserDefaults
    private var isBatchUpdating = false
    private var needsNotifyChanged = false

    public init(defaults: UserDefaults = .standard) {
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
            Key.restoreClosedTabPageHistory: true,
            Key.reopenTabsOnLaunch: true
        ])
    }

    public static func useSharedDefaults(_ defaults: UserDefaults) {
        shared = BrowserPreferences(defaults: defaults)
        NotificationCenter.default.post(name: didChangeNotification, object: shared)
    }

    public var homePageURLString: String {
        get { defaults.string(forKey: Key.homePageURL) ?? "https://search.fenrir-inc.com/" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? "https://search.fenrir-inc.com/" : trimmed, forKey: Key.homePageURL)
            notifyChanged()
        }
    }

    public var searchTemplate: String {
        get { defaults.string(forKey: Key.searchTemplate) ?? "https://search.fenrir-inc.com/?q={query}" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(trimmed.isEmpty ? "https://search.fenrir-inc.com/?q={query}" : trimmed, forKey: Key.searchTemplate)
            notifyChanged()
        }
    }

    public var updatesEnabled: Bool {
        get { defaults.bool(forKey: Key.updatesEnabled) }
        set {
            defaults.set(newValue, forKey: Key.updatesEnabled)
            notifyChanged()
        }
    }

    public var preferredContentLanguage: PreferredContentLanguage {
        get {
            let raw = defaults.string(forKey: Key.preferredContentLanguage) ?? PreferredContentLanguage.system.rawValue
            return PreferredContentLanguage(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.preferredContentLanguage)
            notifyChanged()
        }
    }

    public var preferredDownloadDirectoryPath: String? {
        defaults.string(forKey: Key.preferredDownloadDirectoryPath)
    }

    public func preferredDownloadDirectoryURL() -> URL? {
        guard let data = defaults.data(forKey: Key.preferredDownloadDirectoryBookmark) else { return nil }
        var isStale = false
#if os(macOS)
        let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
        let resolutionOptions: URL.BookmarkResolutionOptions = []
#endif
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: resolutionOptions,
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
    public func setPreferredDownloadDirectory(_ url: URL?) throws -> URL? {
        if let url {
#if os(macOS)
            let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
#else
            let bookmarkOptions: URL.BookmarkCreationOptions = []
#endif
            let bookmark = try url.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
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

    public var gestureSensitivity: GestureSensitivity {
        get {
            let raw = defaults.string(forKey: Key.gestureSensitivity) ?? GestureSensitivity.normal.rawValue
            return GestureSensitivity(rawValue: raw) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.gestureSensitivity)
            notifyChanged()
        }
    }

    public var antiTrackingEnabled: Bool {
        get { defaults.bool(forKey: Key.antiTrackingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.antiTrackingEnabled)
            notifyChanged()
        }
    }

    public var contentBlockingEnabled: Bool {
        get { defaults.bool(forKey: Key.contentBlockingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.contentBlockingEnabled)
            notifyChanged()
        }
    }

    public var popupBlockingEnabled: Bool {
        get { defaults.bool(forKey: Key.popupBlockingEnabled) }
        set {
            defaults.set(newValue, forKey: Key.popupBlockingEnabled)
            notifyChanged()
        }
    }

    public var contentBlockingDisabledHosts: Set<String> {
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

    public var harmfulSiteAllowedHosts: Set<String> {
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

    public var harmfulSiteWarningEnabled: Bool {
        get { defaults.bool(forKey: Key.harmfulSiteWarningEnabled) }
        set {
            defaults.set(newValue, forKey: Key.harmfulSiteWarningEnabled)
            notifyChanged()
        }
    }

    public var ephemeralModeEnabled: Bool {
        get { defaults.bool(forKey: Key.ephemeralModeEnabled) }
        set {
            defaults.set(newValue, forKey: Key.ephemeralModeEnabled)
            notifyChanged()
        }
    }

    public var sendDoNotTrack: Bool {
        get { defaults.bool(forKey: Key.sendDoNotTrack) }
        set {
            defaults.set(newValue, forKey: Key.sendDoNotTrack)
            notifyChanged()
        }
    }

    public var restoreClosedTabPageHistory: Bool {
        get { defaults.bool(forKey: Key.restoreClosedTabPageHistory) }
        set {
            defaults.set(newValue, forKey: Key.restoreClosedTabPageHistory)
            notifyChanged()
        }
    }

    public var reopenTabsOnLaunch: Bool {
        get { defaults.bool(forKey: Key.reopenTabsOnLaunch) }
        set {
            defaults.set(newValue, forKey: Key.reopenTabsOnLaunch)
            notifyChanged()
        }
    }

    public var homePageURL: URL {
        if let url = URL(string: homePageURLString), url.scheme != nil {
            return url
        }
        return URL(string: "https://search.fenrir-inc.com/")!
    }

    public func searchURL(for query: String) -> URL {
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

    public func resetDefaults() {
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
            defaults.set(true, forKey: Key.reopenTabsOnLaunch)
        }
    }

    public func isContentBlockingDisabled(for host: String) -> Bool {
        guard let normalized = Self.normalizeHost(host) else { return false }
        return contentBlockingDisabledHosts.contains(normalized)
    }

    public func setContentBlockingDisabled(_ disabled: Bool, for host: String) {
        guard let normalized = Self.normalizeHost(host) else { return }
        var hosts = contentBlockingDisabledHosts
        if disabled {
            hosts.insert(normalized)
        } else {
            hosts.remove(normalized)
        }
        contentBlockingDisabledHosts = hosts
    }

    public var contentBlockingExceptionSignature: String {
        contentBlockingDisabledHosts.sorted().joined(separator: "|")
    }

    public func isHarmfulSiteAllowed(for host: String) -> Bool {
        guard let normalized = Self.normalizeHost(host) else { return false }
        return harmfulSiteAllowedHosts.contains(normalized)
    }

    public func setHarmfulSiteAllowed(_ allowed: Bool, for host: String) {
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
