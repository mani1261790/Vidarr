import Foundation

struct BrowsingItem: Codable {
    let urlString: String
    var title: String
    var visitedAt: Date

    var url: URL? {
        URL(string: urlString)
    }
}

final class BrowsingHistoryStore {
    static let shared = BrowsingHistoryStore()

    private enum Key {
        static let historyItems = "history.items"
    }

    private let defaults: UserDefaults
    private var items: [BrowsingItem]
    private let maxItems = 250

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.historyItems),
           let decoded = try? JSONDecoder().decode([BrowsingItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func recordVisit(url: URL, title: String?) {
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

    func recent(limit: Int) -> [BrowsingItem] {
        Array(items.prefix(max(0, limit)))
    }

    func all() -> [BrowsingItem] {
        items
    }

    func remove(urlString: String) {
        items.removeAll { $0.urlString == urlString }
        persist()
    }

    func clear() {
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
    }
}

final class BookmarkStore {
    static let shared = BookmarkStore()
    static let didChangeNotification = Notification.Name("BookmarkStoreDidChange")

    private enum Key {
        static let bookmarkItems = "bookmarks.items"
    }

    private let defaults: UserDefaults
    private var items: [BrowsingItem]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.bookmarkItems),
           let decoded = try? JSONDecoder().decode([BrowsingItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func addOrUpdate(url: URL, title: String?) {
        let resolvedTitle = normalizedTitle(title, fallbackURL: url)
        let value = BrowsingItem(urlString: url.absoluteString, title: resolvedTitle, visitedAt: Date())
        if let index = items.firstIndex(where: { $0.urlString == value.urlString }) {
            items[index] = value
        } else {
            items.insert(value, at: 0)
        }
        persist()
    }

    func remove(url: URL) {
        items.removeAll { $0.urlString == url.absoluteString }
        persist()
    }

    func contains(url: URL) -> Bool {
        items.contains { $0.urlString == url.absoluteString }
    }

    func contains(urlString: String) -> Bool {
        items.contains { $0.urlString == urlString }
    }

    func all() -> [BrowsingItem] {
        items
    }

    func remove(urlString: String) {
        items.removeAll { $0.urlString == urlString }
        persist()
    }

    func clear() {
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
        defaults.set(data, forKey: Key.bookmarkItems)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
