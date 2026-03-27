import Foundation

#if canImport(VidarrCore)
import VidarrCore
typealias PadBrowserPreferences = BrowserPreferences
typealias PadPreferredContentLanguage = BrowserPreferences.PreferredContentLanguage
#else
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

final class PadBrowserPreferences {
    static let shared = PadBrowserPreferences()

    private enum Key {
        static let homePageURL = "prefs.homePageURL"
        static let searchTemplate = "prefs.searchTemplate"
        static let preferredContentLanguage = "prefs.preferredContentLanguage"
    }

    private let defaults = UserDefaults.standard

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
}
#endif
