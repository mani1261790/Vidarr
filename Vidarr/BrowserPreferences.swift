import Foundation

final class BrowserPreferences {
    static let shared = BrowserPreferences()
    static let didChangeNotification = Notification.Name("BrowserPreferencesDidChange")

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
        static let gestureSensitivity = "prefs.gestureSensitivity"
        static let antiTrackingEnabled = "prefs.antiTrackingEnabled"
        static let contentBlockingEnabled = "prefs.contentBlockingEnabled"
        static let harmfulSiteWarningEnabled = "prefs.harmfulSiteWarningEnabled"
        static let ephemeralModeEnabled = "prefs.ephemeralModeEnabled"
        static let sendDoNotTrack = "prefs.sendDoNotTrack"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.homePageURL: "https://search.fenrir-inc.com/",
            Key.searchTemplate: "https://search.fenrir-inc.com/?q={query}",
            Key.updatesEnabled: true,
            Key.gestureSensitivity: GestureSensitivity.normal.rawValue,
            Key.antiTrackingEnabled: true,
            Key.contentBlockingEnabled: true,
            Key.harmfulSiteWarningEnabled: true,
            Key.ephemeralModeEnabled: false,
            Key.sendDoNotTrack: true
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
        homePageURLString = "https://search.fenrir-inc.com/"
        searchTemplate = "https://search.fenrir-inc.com/?q={query}"
        updatesEnabled = true
        gestureSensitivity = .normal
        antiTrackingEnabled = true
        contentBlockingEnabled = true
        harmfulSiteWarningEnabled = true
        ephemeralModeEnabled = false
        sendDoNotTrack = true
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
