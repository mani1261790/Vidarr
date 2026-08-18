import Foundation
import VidarrCore
import WebKit

final class BrowserProfileManager {
    static let shared = BrowserProfileManager()
    static let didChangeNotification = Notification.Name("BrowserProfileManagerDidChange")

    private enum Key {
        static let profiles = "profiles.items"
        static let currentProfileID = "profiles.currentID"
        static let websiteDataStoreIdentifiers = "profiles.websiteDataStoreIdentifiers"
        static let routeRules = "profiles.routeRules"
        static let tabGroupWebsiteDataStoreIdentifiers = "tabGroups.websiteDataStoreIdentifiers"
        static let tabGroupRouteRules = "tabGroups.routeRules"
    }

    private let defaults: UserDefaults
    private let bundleIdentifier: String
    private var websiteDataStores: [String: WKWebsiteDataStore] = [:]

    init(defaults: UserDefaults = .standard, bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.mani.Vidarr") {
        self.defaults = defaults
        self.bundleIdentifier = bundleIdentifier
        ensureDefaultProfileExists()
        migrateLegacyRoutesIfNeeded()
    }

    var profiles: [BrowserProfile] {
        get {
            guard let data = defaults.data(forKey: Key.profiles),
                  let decoded = try? JSONDecoder().decode([BrowserProfile].self, from: data),
                  !decoded.isEmpty else {
                return [.default]
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.profiles)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    var currentProfile: BrowserProfile {
        let currentID = defaults.string(forKey: Key.currentProfileID) ?? BrowserProfile.default.id
        return profiles.first(where: { $0.id == currentID }) ?? .default
    }

    var routeRules: [String: String] {
        get { defaults.dictionary(forKey: Key.routeRules) as? [String: String] ?? [:] }
        set {
            defaults.set(newValue, forKey: Key.routeRules)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    var tabGroupRouteRules: [String: String] {
        get { defaults.dictionary(forKey: Key.tabGroupRouteRules) as? [String: String] ?? [:] }
        set {
            defaults.set(newValue, forKey: Key.tabGroupRouteRules)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    func applyCurrentProfile() {
        let suiteDefaults = BrowserProfileStorage.userDefaults(for: currentProfile, bundleIdentifier: bundleIdentifier)
        BrowserPreferences.useSharedDefaults(suiteDefaults)
        BrowsingHistoryStore.useSharedDefaults(suiteDefaults)
        BookmarkStore.useSharedDefaults(suiteDefaults, syncIdentifier: currentProfile.id)
        DownloadStore.useSharedDefaults(suiteDefaults)
        BrowserSessionStore.useSharedDefaults(suiteDefaults)
        TabGroupStore.useSharedDefaults(suiteDefaults)
        MediaPermissionStore.useSharedDefaults(suiteDefaults)
        PrivacyReportStore.useSharedDefaults(suiteDefaults)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func websiteDataStore(for profile: BrowserProfile? = nil) -> WKWebsiteDataStore {
        let profile = profile ?? currentProfile
        guard profile.id != BrowserProfile.default.id else {
            return .default()
        }
        if let cached = websiteDataStores[profile.id] {
            return cached
        }

        let identifier = websiteDataStoreIdentifier(for: profile)
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        websiteDataStores[profile.id] = store
        return store
    }

    func websiteDataStore(for tabGroup: BrowserTabGroup) -> WKWebsiteDataStore {
        if tabGroup == .regular {
            return .default()
        }
        if tabGroup == .privateMode {
            return .nonPersistent()
        }

        let cacheKey = "tab-group:\(tabGroup.id)"
        if let cached = websiteDataStores[cacheKey] {
            return cached
        }

        var identifiers = defaults.dictionary(forKey: Key.tabGroupWebsiteDataStoreIdentifiers) as? [String: String] ?? [:]
        let identifier: UUID
        if let rawValue = identifiers[tabGroup.id], let savedIdentifier = UUID(uuidString: rawValue) {
            identifier = savedIdentifier
        } else {
            identifier = UUID()
            identifiers[tabGroup.id] = identifier.uuidString.lowercased()
            defaults.set(identifiers, forKey: Key.tabGroupWebsiteDataStoreIdentifiers)
        }

        let store = WKWebsiteDataStore(forIdentifier: identifier)
        websiteDataStores[cacheKey] = store
        return store
    }

    func websiteDataStoreIdentifier(for profile: BrowserProfile) -> UUID {
        if let identifier = UUID(uuidString: profile.id) {
            return identifier
        }

        var identifiers = defaults.dictionary(forKey: Key.websiteDataStoreIdentifiers) as? [String: String] ?? [:]
        if let rawValue = identifiers[profile.id], let identifier = UUID(uuidString: rawValue) {
            return identifier
        }

        let identifier = UUID()
        identifiers[profile.id] = identifier.uuidString.lowercased()
        defaults.set(identifiers, forKey: Key.websiteDataStoreIdentifiers)
        return identifier
    }

    @discardableResult
    func setRoute(domain rawDomain: String, profileID: String) -> Bool {
        guard profiles.contains(where: { $0.id == profileID }),
              let domain = normalizedDomain(rawDomain) else { return false }
        var rules = routeRules
        rules[domain] = profileID
        routeRules = rules
        return true
    }

    func removeRoute(domain rawDomain: String) {
        guard let domain = normalizedDomain(rawDomain) else { return }
        var rules = routeRules
        rules.removeValue(forKey: domain)
        routeRules = rules
    }

    func routedProfile(for url: URL) -> BrowserProfile? {
        guard let profileID = routedProfileID(for: url, rules: routeRules) else { return nil }
        return profiles.first(where: { $0.id == profileID })
    }

    func routedProfileID(for url: URL, rules: [String: String]) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let matchingDomain = rules.keys
            .filter { host == $0 || host.hasSuffix(".\($0)") }
            .max(by: { $0.count < $1.count })
        guard let matchingDomain else { return nil }
        return rules[matchingDomain]
    }

    @discardableResult
    func setRoute(domain rawDomain: String, tabGroupID: String) -> Bool {
        guard TabGroupStore.shared.groups.contains(where: { $0.id == tabGroupID }),
              let domain = normalizedDomain(rawDomain) else { return false }
        var rules = tabGroupRouteRules
        rules[domain] = tabGroupID
        tabGroupRouteRules = rules
        return true
    }

    func removeTabGroupRoute(domain rawDomain: String) {
        guard let domain = normalizedDomain(rawDomain) else { return }
        var rules = tabGroupRouteRules
        rules.removeValue(forKey: domain)
        tabGroupRouteRules = rules
    }

    func routedTabGroup(for url: URL) -> BrowserTabGroup? {
        guard let groupID = routedProfileID(for: url, rules: tabGroupRouteRules) else { return nil }
        return TabGroupStore.shared.groups.first(where: { $0.id == groupID })
    }

    private func normalizedDomain(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URL(string: candidate)?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    @discardableResult
    func createProfile(named rawName: String) -> BrowserProfile {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Profile \(profiles.count + 1)" : trimmed
        let existingNames = Set(profiles.map(\.name))
        var finalName = baseName
        var suffix = 2
        while existingNames.contains(finalName) {
            finalName = "\(baseName) \(suffix)"
            suffix += 1
        }

        let profile = BrowserProfile(id: UUID().uuidString.lowercased(), name: finalName)
        profiles.append(profile)
        return profile
    }

    @discardableResult
    func switchToProfile(id: String) -> BrowserProfile? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return nil }
        defaults.set(profile.id, forKey: Key.currentProfileID)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        return profile
    }

    private func ensureDefaultProfileExists() {
        var existing = profiles
        if !existing.contains(where: { $0.id == BrowserProfile.default.id }) {
            existing.insert(.default, at: 0)
            profiles = existing
        }
        if defaults.string(forKey: Key.currentProfileID) == nil {
            defaults.set(BrowserProfile.default.id, forKey: Key.currentProfileID)
        }
    }

    private func migrateLegacyRoutesIfNeeded() {
        guard defaults.object(forKey: Key.tabGroupRouteRules) == nil else { return }
        let legacyRules = defaults.dictionary(forKey: Key.routeRules) as? [String: String] ?? [:]
        let validGroupIDs = Set(BrowserTabGroup.builtIns.map(\.id))
        let migrated = legacyRules.reduce(into: [String: String]()) { result, entry in
            if entry.value == BrowserProfile.default.id {
                result[entry.key] = BrowserTabGroup.regular.id
            } else if validGroupIDs.contains(entry.value) {
                result[entry.key] = entry.value
            }
        }
        if !migrated.isEmpty {
            defaults.set(migrated, forKey: Key.tabGroupRouteRules)
        }
    }
}
