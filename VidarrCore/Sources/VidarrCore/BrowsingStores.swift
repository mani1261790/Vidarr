import Foundation

public struct BrowsingItem: Codable {
    public let urlString: String
    public var title: String
    public var visitedAt: Date

    public var url: URL? {
        URL(string: urlString)
    }

    public init(urlString: String, title: String, visitedAt: Date) {
        self.urlString = urlString
        self.title = title
        self.visitedAt = visitedAt
    }
}

public final class BrowsingHistoryStore {
    public static var shared = BrowsingHistoryStore()
    public static let didChangeNotification = Notification.Name("BrowsingHistoryStoreDidChange")

    private enum Key {
        static let historyItems = "history.items"
    }

    private let defaults: UserDefaults
    private var items: [BrowsingItem]
    private let maxItems = 250

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.historyItems),
           let decoded = try? JSONDecoder().decode([BrowsingItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    public static func useSharedDefaults(_ defaults: UserDefaults) {
        shared = BrowsingHistoryStore(defaults: defaults)
        NotificationCenter.default.post(name: didChangeNotification, object: shared)
    }

    public func recordVisit(url: URL, title: String?) {
        let resolvedTitle = normalizedTitle(title, fallbackURL: url)
        let value = BrowsingItem(urlString: url.absoluteString, title: resolvedTitle, visitedAt: Date())
        if let existingIndex = items.firstIndex(where: { $0.urlString == value.urlString }) {
            items.remove(at: existingIndex)
        }
        items.insert(value, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        persist()
    }

    public func recent(limit: Int) -> [BrowsingItem] {
        Array(items.prefix(max(0, limit)))
    }

    public func all() -> [BrowsingItem] {
        items
    }

    public func remove(urlString: String) {
        items.removeAll { $0.urlString == urlString }
        persist()
    }

    public func clear() {
        items.removeAll()
        persist()
    }

    private func normalizedTitle(_ title: String?, fallbackURL: URL) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return fallbackURL.host ?? fallbackURL.absoluteString
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Key.historyItems)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

public final class BookmarkStore {
    public static var shared = BookmarkStore()
    public static let didChangeNotification = Notification.Name("BookmarkStoreDidChange")

    private enum Key {
        static let bookmarkItems = "bookmarks.items"
        static let bookmarkCloudUpdatedAt = "bookmarks.cloudUpdatedAt"
    }

    private struct CloudSnapshot: Codable {
        let updatedAt: Date
        let items: [BrowsingItem]
    }

    private let defaults: UserDefaults
    private var items: [BrowsingItem]
    private let syncIdentifier: String
    private let cloudStore = NSUbiquitousKeyValueStore.default
    private var cloudObserver: NSObjectProtocol?
    private var cloudKey: String { "vidarr.bookmarks.\(syncIdentifier)" }

    public init(defaults: UserDefaults = .standard, syncIdentifier: String = "default") {
        self.defaults = defaults
        self.syncIdentifier = syncIdentifier
        if let data = defaults.data(forKey: Key.bookmarkItems),
           let decoded = try? JSONDecoder().decode([BrowsingItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] note in
            self?.handleCloudChange(note)
        }
        cloudStore.synchronize()
        mergeFromCloudIfNeeded(force: false)
    }

    deinit {
        if let cloudObserver {
            NotificationCenter.default.removeObserver(cloudObserver)
        }
    }

    public static func useSharedDefaults(_ defaults: UserDefaults, syncIdentifier: String = "default") {
        shared = BookmarkStore(defaults: defaults, syncIdentifier: syncIdentifier)
        NotificationCenter.default.post(name: didChangeNotification, object: shared)
    }

    public func addOrUpdate(url: URL, title: String?) {
        let resolvedTitle = normalizedTitle(title, fallbackURL: url)
        let value = BrowsingItem(urlString: url.absoluteString, title: resolvedTitle, visitedAt: Date())
        if let index = items.firstIndex(where: { $0.urlString == value.urlString }) {
            items[index] = value
        } else {
            items.insert(value, at: 0)
        }
        persist()
    }

    public func remove(url: URL) {
        items.removeAll { $0.urlString == url.absoluteString }
        persist()
    }

    public func contains(url: URL) -> Bool {
        items.contains { $0.urlString == url.absoluteString }
    }

    public func contains(urlString: String) -> Bool {
        items.contains { $0.urlString == urlString }
    }

    public func all() -> [BrowsingItem] {
        items
    }

    public func remove(urlString: String) {
        items.removeAll { $0.urlString == urlString }
        persist()
    }

    public func clear() {
        items.removeAll()
        persist()
    }

    public var isCloudSyncAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    public func forceSynchronize() {
        cloudStore.synchronize()
        mergeFromCloudIfNeeded(force: true)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func normalizedTitle(_ title: String?, fallbackURL: URL) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return fallbackURL.host ?? fallbackURL.absoluteString
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Key.bookmarkItems)
        let now = Date()
        defaults.set(now, forKey: Key.bookmarkCloudUpdatedAt)
        if let cloudData = try? JSONEncoder().encode(CloudSnapshot(updatedAt: now, items: items)) {
            cloudStore.set(cloudData, forKey: cloudKey)
            cloudStore.synchronize()
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func handleCloudChange(_ note: Notification) {
        guard let changedKeys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
              changedKeys.contains(cloudKey) else {
            return
        }
        mergeFromCloudIfNeeded(force: true)
    }

    private func mergeFromCloudIfNeeded(force: Bool) {
        guard let data = cloudStore.data(forKey: cloudKey),
              let snapshot = try? JSONDecoder().decode(CloudSnapshot.self, from: data) else {
            return
        }
        let localUpdatedAt = defaults.object(forKey: Key.bookmarkCloudUpdatedAt) as? Date ?? .distantPast
        guard force || snapshot.updatedAt > localUpdatedAt else { return }
        items = snapshot.items
        if let localData = try? JSONEncoder().encode(items) {
            defaults.set(localData, forKey: Key.bookmarkItems)
        }
        defaults.set(snapshot.updatedAt, forKey: Key.bookmarkCloudUpdatedAt)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
