import AppKit
import CoreGraphics
import Testing
import VidarrCore
import WebKit
@testable import Vidarr

struct BrowserProfileIsolationTests {
    @Test @MainActor func persistentWebsiteDataStoresAreUniquePerTabGroup() throws {
        let suiteName = "VidarrTests.TabGroupDataStores.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = BrowserProfileManager(defaults: defaults)

        let regularStore = manager.websiteDataStore(for: BrowserTabGroup.regular)
        let workStore = manager.websiteDataStore(for: BrowserTabGroup.work)
        let researchStore = manager.websiteDataStore(for: BrowserTabGroup.research)

        #expect(regularStore === WKWebsiteDataStore.default())
        #expect(workStore !== regularStore)
        #expect(researchStore !== regularStore)
        #expect(workStore !== researchStore)
        #expect(workStore.isPersistent)
        #expect(researchStore.isPersistent)
        #expect(manager.websiteDataStore(for: BrowserTabGroup.work) === workStore)
    }

    @Test func legacyDefaultRoutesMigrateToTheRegularTabGroup() throws {
        let suiteName = "VidarrTests.TabGroupRouteMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["example.com": BrowserProfile.default.id], forKey: "profiles.routeRules")

        let manager = BrowserProfileManager(defaults: defaults)

        #expect(manager.tabGroupRouteRules["example.com"] == BrowserTabGroup.regular.id)
    }

    @Test @MainActor func persistentWebsiteDataStoresAreUniquePerProfile() {
        let profileA = BrowserProfile(id: "11111111-1111-4111-8111-111111111111", name: "A")
        let profileB = BrowserProfile(id: "22222222-2222-4222-8222-222222222222", name: "B")
        let manager = BrowserProfileManager.shared

        let storeA = manager.websiteDataStore(for: profileA)
        let storeB = manager.websiteDataStore(for: profileB)

        #expect(storeA !== storeB)
        #expect(storeA.isPersistent)
        #expect(storeB.isPersistent)
        #expect(storeA.identifier == UUID(uuidString: profileA.id))
        #expect(storeB.identifier == UUID(uuidString: profileB.id))
    }

    @Test @MainActor func defaultProfileKeepsTheLegacyDefaultStore() {
        let store = BrowserProfileManager.shared.websiteDataStore(for: .default)
        #expect(store === WKWebsiteDataStore.default())
    }

    @Test @MainActor func profileRoutingUsesTheMostSpecificMatchingDomain() {
        let rules = [
            "example.com": "personal",
            "work.example.com": "work"
        ]
        let manager = BrowserProfileManager.shared

        #expect(manager.routedProfileID(for: URL(string: "https://example.com/")!, rules: rules) == "personal")
        #expect(manager.routedProfileID(for: URL(string: "https://news.example.com/")!, rules: rules) == "personal")
        #expect(manager.routedProfileID(for: URL(string: "https://docs.work.example.com/")!, rules: rules) == "work")
        #expect(manager.routedProfileID(for: URL(string: "https://example.org/")!, rules: rules) == nil)
    }
}

struct GestureStudioPreferencesTests {
    @Test func storesAssignmentsAndDeviceSensitivityIndependently() throws {
        let suiteName = "VidarrTests.GestureStudio.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = BrowserPreferences(defaults: defaults)

        preferences.setGestureAction(.search, for: .o)
        preferences.setGestureAction(nil, for: .left)
        preferences.setGestureSensitivity(.low, for: .touchSurface)
        preferences.setGestureSensitivity(.high, for: .rightDrag)

        #expect(preferences.gestureAction(for: .o) == .search)
        #expect(preferences.gestureAction(for: .left) == nil)
        #expect(!preferences.enabledGesturePatternNames.contains("Left"))
        #expect(preferences.gestureSensitivity(for: .touchSurface) == .low)
        #expect(preferences.gestureSensitivity(for: .rightDrag) == .high)
    }

    @Test func defaultAssignmentsCoverEveryActionOnce() throws {
        let suiteName = "VidarrTests.GestureDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = BrowserPreferences(defaults: defaults)

        for action in BrowserPreferences.GestureOption.allCases {
            #expect(preferences.gesturePatterns(assignedTo: action).count == 1)
        }
    }
}

struct TabSleepingTests {
    @Test @MainActor func inactiveTabSleepsAndRestoresWhenSelected() {
        let manager = TabManager()
        manager.newTab(url: URL(string: "about:blank"))
        manager.openBackgroundTab(url: URL(string: "https://example.com/"))

        manager.sleepInactiveTabs(now: Date().addingTimeInterval(3 * 60 * 60))
        #expect(manager.sleepingTabCount == 1)
        #expect(manager.isTabSleeping(at: 1))

        manager.selectTab(index: 1)
        #expect(manager.sleepingTabCount == 0)
        #expect(!manager.isTabSleeping(at: 1))
    }
}

struct PrivacyReportStoreTests {
    @Test func aggregatesAndPersistsProtectionEvents() throws {
        let suiteName = "VidarrTests.PrivacyReport.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PrivacyReportStore(defaults: defaults)

        store.record(.trackingParameter, host: "Example.COM", count: 3)
        store.record(.popup, host: "example.com")

        #expect(store.total(for: .trackingParameter) == 3)
        #expect(store.total(for: .popup) == 1)
        #expect(store.recent().first?.host == "example.com")

        let restored = PrivacyReportStore(defaults: defaults)
        #expect(restored.total(for: .trackingParameter) == 3)
    }
}

@MainActor
struct TabGroupStoreTests {
    @Test func decodesLegacyBuiltInGroupIdentifiers() throws {
        let decoded = try JSONDecoder().decode(BrowserTabGroup.self, from: Data("\"regular\"".utf8))
        #expect(decoded == .regular)
        #expect(decoded.displayName == "通常タブグループ")
    }

    @Test func createsRenamesReordersAndExportsCustomGroups() throws {
        let suiteName = "VidarrTests.TabGroups.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TabGroupStore(defaults: defaults)

        let group = try #require(store.add(name: "Reading", symbolName: "book.closed", colorID: "orange"))
        #expect(group.displaySymbolName == "book.closed")
        #expect(group.displayColorID == "orange")
        #expect(store.rename(id: group.id, to: "あとで読む"))
        #expect(store.groups.last?.name == "あとで読む")
        #expect(store.move(id: group.id, by: -1))

        let data = try #require(store.exportData())
        let exported = try JSONDecoder().decode([BrowserTabGroup].self, from: data)
        #expect(exported.contains(where: { $0.id == group.id && $0.name == "あとで読む" }))

        let restored = TabGroupStore(defaults: defaults)
        let restoredGroup = try #require(restored.groups.first(where: { $0.id == group.id }))
        #expect(restoredGroup.displaySymbolName == "book.closed")
        #expect(restoredGroup.displayColorID == "orange")
    }
}

struct CommandPaletteTests {
    @Test func filtersAcrossTitleDetailAndSearchAliases() {
        let items = [
            CommandPaletteItem(title: "現在のページを再読み込み", detail: "操作", symbol: "arrow.clockwise", searchText: "reload 更新", action: {}),
            CommandPaletteItem(title: "Example", detail: "ブックマーク · https://example.com", symbol: "star", searchText: "bookmark", action: {})
        ]

        #expect(CommandPaletteWindowController.filtered(items, query: "再読み込み").map(\.title) == ["現在のページを再読み込み"])
        #expect(CommandPaletteWindowController.filtered(items, query: "bookmark example").map(\.title) == ["Example"])
        #expect(CommandPaletteWindowController.filtered(items, query: "missing").isEmpty)
    }
}

struct GestureRecognizerTests {
    private func makeRecognizer() -> GestureRecognizer {
        GestureRecognizer(
            matchScoreThreshold: 0.65,
            minPathLength: 80,
            dominanceRatio: 1.8
        )
    }

    @Test func recognizesLeftStroke() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 320, y: 160),
            CGPoint(x: 220, y: 166),
            CGPoint(x: 80, y: 158)
        ], stepsPerSegment: 30)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "Left", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesDoubleCircleAsOO() {
        let recognizer = makeRecognizer()
        let points = circle(loopCount: 2, center: CGPoint(x: 180, y: 180), radius: 90, segmentsPerLoop: 56)
        let result = recognizer.recognize(points: points)

        #expect(result?.name == "OO", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesUpRightArrow() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 140, y: 40),
            CGPoint(x: 138, y: 220),
            CGPoint(x: 290, y: 220)
        ], stepsPerSegment: 26)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "UpRight", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesUpLeftArrow() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 210, y: 40),
            CGPoint(x: 208, y: 220),
            CGPoint(x: 60, y: 218)
        ], stepsPerSegment: 26)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "UpLeft", "actual result: \(String(describing: result))")
    }

    @Test func recognizesDownLeftForNewTab() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 190, y: 250),
            CGPoint(x: 185, y: 70),
            CGPoint(x: 40, y: 65)
        ], stepsPerSegment: 24)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "DownLeft", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesDownRightStroke() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 125, y: 220),
            CGPoint(x: 125, y: 35),
            CGPoint(x: 220, y: 35)
        ], stepsPerSegment: 24)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "DownRight", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func recognizesDownRightDownRightStroke() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 80, y: 260),
            CGPoint(x: 80, y: 150),
            CGPoint(x: 180, y: 150),
            CGPoint(x: 180, y: 70),
            CGPoint(x: 300, y: 70)
        ], stepsPerSegment: 18)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "DownRightDownRight", "actual result: \(String(describing: result))")
        #expect((result?.score ?? 0) >= 0.65)
    }

    @Test func prefersUpRightOverSimpleRightWhenVerticalLeadExists() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 160, y: 60),
            CGPoint(x: 160, y: 240),
            CGPoint(x: 320, y: 235)
        ], stepsPerSegment: 24)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "UpRight", "actual result: \(String(describing: result))")
    }

    @Test func prefersDownLeftOverSimpleLeftWhenVerticalLeadExists() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 220, y: 250),
            CGPoint(x: 214, y: 70),
            CGPoint(x: 70, y: 72)
        ], stepsPerSegment: 24)

        let result = recognizer.recognize(points: points)
        #expect(result?.name == "DownLeft", "actual result: \(String(describing: result))")
    }

    @Test func recognizesSingleLoopO() {
        let recognizer = makeRecognizer()
        let points = circle(loopCount: 1, center: CGPoint(x: 190, y: 190), radius: 85, segmentsPerLoop: 54)
        let result = recognizer.recognize(points: points)
        #expect(result?.name == "O", "actual result: \(String(describing: result))")
    }

    @Test func lowConfidenceGestureReturnsNil() {
        let recognizer = makeRecognizer()
        let points = polyline([
            CGPoint(x: 12, y: 12),
            CGPoint(x: 14, y: 16),
            CGPoint(x: 16, y: 11),
            CGPoint(x: 18, y: 15)
        ], stepsPerSegment: 3)

        let result = recognizer.recognize(points: points)
        #expect(result == nil)
    }

    @Test func disallowedNamesFilterRejectsLShape() {
        let recognizer = makeRecognizer()
        let points = circle(loopCount: 1, center: CGPoint(x: 190, y: 190), radius: 85, segmentsPerLoop: 54)
        let allowedNames: Set<String> = ["Left"]
        let result = recognizer.recognize(points: points, allowedNames: allowedNames)
        #expect(result == nil)
    }
}

struct GestureOverlayEventRoutingTests {
    @Test func passesStandardWebInteractionThroughToWebView() {
        #expect(!GestureOverlayView.capturesEvent(.mouseMoved))
        #expect(!GestureOverlayView.capturesEvent(.cursorUpdate))
        #expect(!GestureOverlayView.capturesEvent(.leftMouseDown))
        #expect(!GestureOverlayView.capturesEvent(.leftMouseDragged))
        #expect(!GestureOverlayView.capturesEvent(.leftMouseUp))
        #expect(!GestureOverlayView.capturesEvent(nil))
    }

    @Test func retainsGestureInputCapture() {
        #expect(GestureOverlayView.capturesEvent(.scrollWheel))
        #expect(GestureOverlayView.capturesEvent(.rightMouseDown))
        #expect(GestureOverlayView.capturesEvent(.rightMouseDragged))
        #expect(GestureOverlayView.capturesEvent(.rightMouseUp))
    }

    @Test @MainActor func overlayHitTestingPassesWebInteractionThrough() {
        let overlay = GestureOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let point = NSPoint(x: 120, y: 160)

        #expect(overlay.hitTarget(at: point, for: .mouseMoved) == nil)
        #expect(overlay.hitTarget(at: point, for: .cursorUpdate) == nil)
        #expect(overlay.hitTarget(at: point, for: .leftMouseDown) == nil)
        #expect(overlay.hitTarget(at: point, for: .leftMouseUp) == nil)
    }

    @Test @MainActor func overlayHitTestingStillOwnsGestureEvents() {
        let overlay = GestureOverlayView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let point = NSPoint(x: 120, y: 160)

        #expect(overlay.hitTarget(at: point, for: .scrollWheel) === overlay)
        #expect(overlay.hitTarget(at: point, for: .rightMouseDown) === overlay)
        #expect(overlay.hitTarget(at: point, for: .rightMouseDragged) === overlay)
        #expect(overlay.hitTarget(at: point, for: .rightMouseUp) === overlay)
    }
}

private func polyline(_ controlPoints: [CGPoint], stepsPerSegment: Int) -> [CGPoint] {
    guard controlPoints.count >= 2 else { return controlPoints }

    var output: [CGPoint] = []
    for i in 1..<controlPoints.count {
        let segment = line(from: controlPoints[i - 1], to: controlPoints[i], steps: stepsPerSegment)
        if output.isEmpty {
            output.append(contentsOf: segment)
        } else {
            output.append(contentsOf: segment.dropFirst())
        }
    }
    return output
}

private func line(from: CGPoint, to: CGPoint, steps: Int) -> [CGPoint] {
    guard steps > 0 else { return [from, to] }
    return (0...steps).map { i in
        let t = CGFloat(i) / CGFloat(steps)
        return CGPoint(
            x: from.x + (to.x - from.x) * t,
            y: from.y + (to.y - from.y) * t
        )
    }
}

private func circle(loopCount: Int, center: CGPoint, radius: CGFloat, segmentsPerLoop: Int) -> [CGPoint] {
    let total = segmentsPerLoop * loopCount
    return (0...total).map { i in
        let t = CGFloat(i) / CGFloat(total)
        let radians = t * 2 * .pi * CGFloat(loopCount)
        return CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )
    }
}
