import Foundation

public struct BrowserProfile: Codable, Hashable, Identifiable {
    public let id: String
    public var name: String

    public init(id: String = UUID().uuidString.lowercased(), name: String) {
        self.id = id
        self.name = name
    }

    public static let `default` = BrowserProfile(id: "default", name: "Default")
}

public enum BrowserProfileStorage {
    public static func userDefaults(for profile: BrowserProfile, bundleIdentifier: String = "dev.mani.Vidarr") -> UserDefaults {
        let suiteName = "\(bundleIdentifier).profile.\(profile.id)"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
