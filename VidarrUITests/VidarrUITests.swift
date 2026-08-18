//
//  VidarrUITests.swift
//  VidarrUITests
//
//  Created by Mani on 2026/02/25.
//

import XCTest

final class VidarrUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testPreferencesWindowOpens() throws {
        let app = XCUIApplication()
        app.launch()

        let appMenu = app.menuBars.menuBarItems["Vidarr"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 3))
        appMenu.click()
        XCTAssertTrue(app.menuItems["About Vidarr"].exists)
        XCTAssertTrue(app.menuItems["Check for Updates…"].exists)
        XCTAssertTrue(app.menuItems["Services"].exists)
        XCTAssertTrue(app.menuItems["Hide Vidarr"].exists)
        XCTAssertTrue(app.menuItems["Hide Others"].exists)
        XCTAssertTrue(app.menuItems["Show All"].exists)
        XCTAssertTrue(app.menuItems["Quit Vidarr"].exists)
        app.menuItems["Settings…"].click()

        let preferencesWindow = app.windows["Preferences"]
        XCTAssertTrue(preferencesWindow.waitForExistence(timeout: 3))
        XCTAssertTrue(preferencesWindow.staticTexts["タブグループ"].waitForExistence(timeout: 3))
        XCTAssertTrue(preferencesWindow.staticTexts["外部リンクの自動振り分け"].exists)
        XCTAssertFalse(preferencesWindow.staticTexts["プロファイル"].exists)
        XCTAssertFalse(preferencesWindow.staticTexts["現在のプロファイル"].exists)

        let gestureSegment = preferencesWindow.buttons["preferences.category.gestures"]
        XCTAssertTrue(gestureSegment.waitForExistence(timeout: 3))
        gestureSegment.click()
        XCTAssertTrue(preferencesWindow.staticTexts["ジェスチャーの割り当て"].waitForExistence(timeout: 3))
        XCTAssertTrue(preferencesWindow.staticTexts["入力ごとの感度"].waitForExistence(timeout: 3))

        let openGestureTestButton = preferencesWindow.buttons["preferences.gestures.openTest"]
        XCTAssertTrue(openGestureTestButton.waitForExistence(timeout: 3))
        openGestureTestButton.click()
        let gestureWindow = app.windows["ジェスチャーテスト"]
        XCTAssertTrue(gestureWindow.waitForExistence(timeout: 3))
        gestureWindow.buttons[XCUIIdentifierCloseWindow].click()

        let storageSegment = preferencesWindow.buttons["preferences.category.data"]
        XCTAssertTrue(storageSegment.waitForExistence(timeout: 3))
        storageSegment.click()

        let bookmarksButton = preferencesWindow.buttons["preferences.data.ブックマーク"]
        let siteControlsButton = preferencesWindow.buttons["preferences.data.サイトごとの例外"]
        XCTAssertTrue(bookmarksButton.waitForExistence(timeout: 3))
        XCTAssertTrue(siteControlsButton.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(bookmarksButton.frame.width, 100)
        XCTAssertGreaterThan(siteControlsButton.frame.width, 100)
    }

    @MainActor
    func testCommandPaletteOpensAndFilters() throws {
        let app = XCUIApplication()
        app.launch()

        app.typeKey("k", modifierFlags: .command)
        let palette = app.windows["コマンドパレット"]
        XCTAssertTrue(palette.waitForExistence(timeout: 3))
        let search = palette.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.typeText("reload")
        let reloadResult = palette.staticTexts["現在のページを再読み込み"]
        XCTAssertTrue(reloadResult.waitForExistence(timeout: 2))
        XCTAssertFalse(palette.staticTexts["新しいタブ"].exists)
    }

    @MainActor
    func testTabGroupMenuKeepsSelectionFocused() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertFalse(app.staticTexts["現在のプロファイル"].exists)
        let selector = app.buttons["タブグループを選択"]
        XCTAssertTrue(selector.waitForExistence(timeout: 3))
        selector.click()

        XCTAssertTrue(app.menuItems["通常タブグループ"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.menuItems["新しいタブグループ…"].exists)
        XCTAssertFalse(app.menuItems["左へ移動"].exists)
        XCTAssertFalse(app.menuItems["右へ移動"].exists)
        XCTAssertFalse(app.menuItems["タブグループを書き出す…"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Tab group menu with colored icons"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
