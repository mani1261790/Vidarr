import Foundation
import VidarrCore

final class BrowserProfileManager {
    static let shared = BrowserProfileManager()
    static let didChangeNotification = Notification.Name("BrowserProfileManagerDidChange")

    private enum Key {
        static let profiles = "profiles.items"
        static let currentProfileID = "profiles.currentID"
    }

    private let defaults: UserDefaults
    private let bundleIdentifier: String

    private init(defaults: UserDefaults = .standard, bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.mani.Vidarr") {
        self.defaults = defaults
        self.bundleIdentifier = bundleIdentifier
        ensureDefaultProfileExists()
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

    func applyCurrentProfile() {
        let suiteDefaults = BrowserProfileStorage.userDefaults(for: currentProfile, bundleIdentifier: bundleIdentifier)
        BrowserPreferences.useSharedDefaults(suiteDefaults)
        BrowsingHistoryStore.useSharedDefaults(suiteDefaults)
        BookmarkStore.useSharedDefaults(suiteDefaults)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
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
}
