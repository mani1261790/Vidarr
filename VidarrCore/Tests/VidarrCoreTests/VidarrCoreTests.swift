import XCTest
@testable import VidarrCore

final class VidarrCoreTests: XCTestCase {
    func testGestureRecognizerRecognizesLeftStroke() {
        let recognizer = GestureRecognizer(matchScoreThreshold: 0.60, minPathLength: 20)
        let points: [CGPoint] = stride(from: 200.0, through: 20.0, by: -12.0).map { x in
            CGPoint(x: x, y: 100)
        }

        let result = recognizer.recognize(points: points)
        XCTAssertEqual(result?.name, "Left")
    }

    func testProfileStorageSeparatesPreferences() {
        let profileA = BrowserProfile(id: "profile-a", name: "A")
        let profileB = BrowserProfile(id: "profile-b", name: "B")
        let defaultsA = BrowserProfileStorage.userDefaults(for: profileA, bundleIdentifier: "dev.mani.VidarrTests")
        let defaultsB = BrowserProfileStorage.userDefaults(for: profileB, bundleIdentifier: "dev.mani.VidarrTests")
        defaultsA.removePersistentDomain(forName: "dev.mani.VidarrTests.profile.profile-a")
        defaultsB.removePersistentDomain(forName: "dev.mani.VidarrTests.profile.profile-b")

        let prefsA = BrowserPreferences(defaults: defaultsA)
        let prefsB = BrowserPreferences(defaults: defaultsB)

        prefsA.homePageURLString = "https://example.com/a"
        prefsB.homePageURLString = "https://example.com/b"

        XCTAssertEqual(prefsA.homePageURLString, "https://example.com/a")
        XCTAssertEqual(prefsB.homePageURLString, "https://example.com/b")
    }

    func testBookmarkStoreUsesInjectedDefaults() {
        let suiteName = "dev.mani.VidarrTests.bookmarks"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = BookmarkStore(defaults: defaults)
        let url = URL(string: "https://example.com")!

        store.addOrUpdate(url: url, title: "Example")

        XCTAssertTrue(store.contains(url: url))
        XCTAssertEqual(store.all().first?.title, "Example")
    }
}
