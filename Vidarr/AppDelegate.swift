//
//  AppDelegate.swift
//  Vidarr
//
//  Created by Mani on 2026/02/25.
//

import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var mainWindowController: MainWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var downloadsWindowController: DownloadsWindowController?
    private var historyWindowController: BrowsingItemsWindowController?
    private var bookmarksWindowController: BrowsingItemsWindowController?
    private var siteSettingsWindowController: SiteSettingsWindowController?
    private let updateChecker = UpdateChecker()
    private var hasPresentedUpdateAlert = false
    private weak var historyMenu: NSMenu?
    private weak var bookmarksMenu: NSMenu?
    private weak var developMenu: NSMenu?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMainMenu()
        if let iconImage = NSImage(named: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) {
            NSApp.applicationIconImage = iconImage
        }

        let windowController = MainWindowController()
        mainWindowController = windowController
        windowController.restoreSavedSessionIfAvailable()

        windowController.showWindow(self)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.checkForAppUpdateIfNeeded()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        mainWindowController?.showWindow(self)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        mainWindowController?.saveSessionSnapshot()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    private func checkForAppUpdateIfNeeded() {
        guard BrowserPreferences.shared.updatesEnabled else { return }
        guard !hasPresentedUpdateAlert else { return }
        updateChecker.check { [weak self] candidate in
            guard let self, let candidate else { return }
            DispatchQueue.main.async {
                self.presentUpdateAlertIfNeeded(candidate)
            }
        }
    }

    private func presentUpdateAlertIfNeeded(_ candidate: UpdateCandidate) {
        guard !hasPresentedUpdateAlert else { return }
        hasPresentedUpdateAlert = true

        let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "新しいバージョンがあります"
        alert.informativeText = "現在: \(currentVersion)\n最新: \(candidate.version)\nGitHub Releasesからアップデートできます。"
        alert.addButton(withTitle: "ダウンロード")
        alert.addButton(withTitle: "あとで")

        if let window = mainWindowController?.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(candidate.url)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(candidate.url)
            }
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let appName = ProcessInfo.processInfo.processName

        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        let fileMenu = NSMenu(title: "File")
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        fileMenu.addItem(makeMenuItem("New Tab", action: #selector(menuNewTab), key: "t"))
        fileMenu.addItem(makeMenuItem("Open File...", action: #selector(menuOpenFile), key: "o"))
        fileMenu.addItem(makeMenuItem("Close Tab", action: #selector(menuCloseTab), key: "w"))
        fileMenu.addItem(makeMenuItem("Toggle Bookmark", action: #selector(menuToggleBookmark), key: "d"))
        fileMenu.addItem(makeMenuItem("Reopen Closed Tab", action: #selector(menuReopenClosedTab), key: "t", modifiers: [.command, .shift]))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(makeMenuItem("Open Downloads", action: #selector(menuOpenDownloads), key: "j", modifiers: [.command, .option]))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(makeMenuItem("Print...", action: #selector(menuPrintPage), key: "p"))
        fileMenu.addItem(makeMenuItem("Export as PDF...", action: #selector(menuExportPDF), key: "p", modifiers: [.command, .shift]))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(makeMenuItem("Close Window", action: #selector(menuCloseWindow), key: "w", modifiers: [.command, .shift]))

        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(makeMenuItem("AutoFill Password", action: #selector(menuAutoFillPassword), key: "\\"))
        editMenu.addItem(makeMenuItem("Open Passwords App", action: #selector(menuOpenPasswordsApp), key: "\\", modifiers: [.command, .option]))

        let viewMenu = NSMenu(title: "View")
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        viewMenu.addItem(makeMenuItem("Reload", action: #selector(menuReload), key: "r"))
        viewMenu.addItem(makeMenuItem("Reload All Tabs", action: #selector(menuReloadAll), key: "r", modifiers: [.command, .shift]))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(makeMenuItem("Next Tab", action: #selector(menuNextTab), key: "]", modifiers: [.command, .shift]))
        viewMenu.addItem(makeMenuItem("Previous Tab", action: #selector(menuPreviousTab), key: "[", modifiers: [.command, .shift]))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(makeMenuItem("Focus Address Bar", action: #selector(menuFocusAddressBar), key: "l"))
        viewMenu.addItem(makeMenuItem("Focus Tab Search", action: #selector(menuFocusTabSearch), key: "f", modifiers: [.command, .shift]))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(makeMenuItem("Zoom In", action: #selector(menuZoomIn), key: "+"))
        viewMenu.addItem(makeMenuItem("Zoom Out", action: #selector(menuZoomOut), key: "-"))
        viewMenu.addItem(makeMenuItem("Actual Size", action: #selector(menuActualSize), key: "0"))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(makeMenuItem("Enter Full Screen", action: #selector(menuToggleFullScreen), key: "f", modifiers: [.command, .control]))

        let historyMenu = NSMenu(title: "History")
        let historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyMenuItem.submenu = historyMenu
        mainMenu.addItem(historyMenuItem)
        historyMenu.delegate = self
        self.historyMenu = historyMenu

        historyMenu.addItem(makeMenuItem("Back", action: #selector(menuGoBack), key: "["))
        historyMenu.addItem(makeMenuItem("Forward", action: #selector(menuGoForward), key: "]"))
        historyMenu.addItem(NSMenuItem.separator())
        historyMenu.addItem(makeMenuItem("Reopen Closed Tab", action: #selector(menuReopenClosedTab), key: "", modifiers: []))
        historyMenu.addItem(makeMenuItem("Show Full History", action: #selector(menuOpenHistoryWindow), key: "y"))
        historyMenu.addItem(makeMenuItem("Clear History...", action: #selector(menuClearHistory), key: "", modifiers: []))

        let bookmarksMenu = NSMenu(title: "Bookmarks")
        let bookmarksMenuItem = NSMenuItem(title: "Bookmarks", action: nil, keyEquivalent: "")
        bookmarksMenuItem.submenu = bookmarksMenu
        mainMenu.addItem(bookmarksMenuItem)
        bookmarksMenu.delegate = self
        self.bookmarksMenu = bookmarksMenu
        bookmarksMenu.addItem(makeMenuItem("Show All Bookmarks", action: #selector(menuOpenBookmarksWindow), key: "b", modifiers: [.command, .option]))
        bookmarksMenu.addItem(NSMenuItem.separator())

        let developMenu = NSMenu(title: "Develop")
        let developMenuItem = NSMenuItem(title: "Develop", action: nil, keyEquivalent: "")
        developMenuItem.submenu = developMenu
        mainMenu.addItem(developMenuItem)
        developMenu.delegate = self
        self.developMenu = developMenu

        rebuildDevelopMenu(developMenu)

        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        windowMenu.addItem(makeMenuItem("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(makeMenuItem("Zoom", action: #selector(NSWindow.performZoom(_:)), key: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(makeMenuItem("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), key: ""))

        let helpMenu = NSMenu(title: "Help")
        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        helpMenu.addItem(makeMenuItem("Vidarr on GitHub", action: #selector(menuOpenGitHub), key: ""))
        helpMenu.addItem(makeMenuItem("Releases", action: #selector(menuOpenReleases), key: ""))
    }

    private func makeMenuItem(
        _ title: String,
        action: Selector?,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func menuNewTab() {
        mainWindowController?.menuNewTab()
    }

    @objc private func menuCloseTab() {
        mainWindowController?.menuCloseTab()
    }

    @objc private func menuToggleBookmark() {
        mainWindowController?.menuToggleBookmark()
    }

    @objc private func menuCloseWindow() {
        mainWindowController?.window?.performClose(nil)
    }

    @objc private func menuOpenDownloads() {
        if downloadsWindowController == nil {
            downloadsWindowController = DownloadsWindowController()
        }
        downloadsWindowController?.showWindowAndReload()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuOpenFile() {
        mainWindowController?.menuOpenLocalFile()
    }

    @objc private func menuOpenHistoryWindow() {
        if historyWindowController == nil {
            historyWindowController = BrowsingItemsWindowController(mode: .history) { [weak self] url in
                self?.mainWindowController?.menuOpenExternalListURL(url)
            }
        }
        historyWindowController?.showWindowAndReload()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuClearHistory() {
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "履歴を削除しますか？"
        confirmation.informativeText = "Vidarr に保存されている閲覧履歴をすべて削除します。ブックマーク、ダウンロード履歴、Cookie、サイト設定は削除しません。"
        confirmation.addButton(withTitle: "削除")
        confirmation.addButton(withTitle: "キャンセル")

        let clear = {
            BrowsingHistoryStore.shared.clear()
            self.historyWindowController?.showWindowAndReload()
        }

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            clear()
        }

        if let window = mainWindowController?.window {
            confirmation.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(confirmation.runModal())
        }
    }

    @objc private func menuOpenBookmarksWindow() {
        if bookmarksWindowController == nil {
            bookmarksWindowController = BrowsingItemsWindowController(mode: .bookmarks) { [weak self] url in
                self?.mainWindowController?.menuOpenExternalListURL(url)
            }
        }
        bookmarksWindowController?.showWindowAndReload()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuReload() {
        mainWindowController?.menuReload()
    }

    @objc private func menuReloadAll() {
        mainWindowController?.menuReloadAllTabs()
    }

    @objc private func menuFocusAddressBar() {
        mainWindowController?.menuFocusAddressBar()
    }

    @objc private func menuFocusTabSearch() {
        mainWindowController?.menuFocusTabSearch()
    }

    @objc private func menuZoomIn() {
        mainWindowController?.menuZoomIn()
    }

    @objc private func menuZoomOut() {
        mainWindowController?.menuZoomOut()
    }

    @objc private func menuActualSize() {
        mainWindowController?.menuResetZoom()
    }

    @objc private func menuNextTab() {
        mainWindowController?.menuSelectNextTab()
    }

    @objc private func menuPreviousTab() {
        mainWindowController?.menuSelectPreviousTab()
    }

    @objc private func menuAutoFillPassword() {
        mainWindowController?.menuPreparePasswordAutoFill()
    }

    @objc private func menuOpenPasswordsApp() {
        let systemPath = "/System/Applications/Passwords.app"
        if FileManager.default.fileExists(atPath: systemPath) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: systemPath), configuration: .init(), completionHandler: nil)
            return
        }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
            NSWorkspace.shared.open(fallback)
        }
    }

    @objc private func menuToggleFullScreen() {
        mainWindowController?.window?.toggleFullScreen(nil)
    }

    @objc private func menuGoBack() {
        mainWindowController?.menuGoBack()
    }

    @objc private func menuGoForward() {
        mainWindowController?.menuGoForward()
    }

    @objc private func menuReopenClosedTab() {
        mainWindowController?.menuReopenClosedTab()
    }

    @objc private func menuPrintPage() {
        mainWindowController?.menuPrintPage()
    }

    @objc private func menuExportPDF() {
        mainWindowController?.menuExportPDF()
    }

    @objc private func menuOpenHistoryEntry(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let url = URL(string: raw) else { return }
        mainWindowController?.menuOpenExternalListURL(url)
    }

    @objc private func menuOpenBookmarkEntry(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let url = URL(string: raw) else { return }
        mainWindowController?.menuOpenExternalListURL(url)
    }

    @objc private func menuToggleWebInspector() {
        mainWindowController?.menuToggleWebInspector()
    }

    @objc private func menuOpenSiteSettings() {
        if siteSettingsWindowController == nil {
            siteSettingsWindowController = SiteSettingsWindowController()
        }
        siteSettingsWindowController?.showWindowAndReload()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuToggleContentBlockingForCurrentSite() {
        mainWindowController?.menuToggleContentBlockingForCurrentSite()
    }

    @objc private func menuClearBrowsingData() {
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Clear cookies and cache?"
        confirmation.informativeText = "This removes cookies, cache, and saved website data. History, bookmarks, downloads, and site permissions stay as they are."
        confirmation.addButton(withTitle: "Clear")
        confirmation.addButton(withTitle: "Cancel")

        let runClear = { [weak self] in
            BrowserDataCleaner.clearPersistentBrowsingData { result in
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    switch result {
                    case .success:
                        alert.alertStyle = .informational
                        alert.messageText = "Cookies and cache cleared"
                        alert.informativeText = "Saved website data was removed."
                    case .failure(let error):
                        alert.alertStyle = .warning
                        alert.messageText = "Couldn't clear cookies and cache"
                        alert.informativeText = error.localizedDescription
                    }
                    alert.addButton(withTitle: "OK")
                    if let window = self?.mainWindowController?.window {
                        alert.beginSheetModal(for: window)
                    } else {
                        alert.runModal()
                    }
                }
            }
        }

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            runClear()
        }

        if let window = mainWindowController?.window {
            confirmation.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(confirmation.runModal())
        }
    }

    @objc private func menuOpenGitHub() {
        guard let url = URL(string: "https://github.com/mani1261790/Vidarr") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func menuOpenReleases() {
        guard let url = URL(string: "https://github.com/mani1261790/Vidarr/releases") else { return }
        NSWorkspace.shared.open(url)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === historyMenu {
            rebuildHistoryMenu(menu)
            return
        }
        if menu === bookmarksMenu {
            rebuildBookmarksMenu(menu)
            return
        }
        if menu === developMenu {
            rebuildDevelopMenu(menu)
        }
    }

    private func rebuildHistoryMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(makeMenuItem("Back", action: #selector(menuGoBack), key: "["))
        menu.addItem(makeMenuItem("Forward", action: #selector(menuGoForward), key: "]"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem("Reopen Closed Tab", action: #selector(menuReopenClosedTab), key: "", modifiers: []))
        menu.addItem(makeMenuItem("Show Full History", action: #selector(menuOpenHistoryWindow), key: "y"))
        menu.addItem(NSMenuItem.separator())

        let entries = BrowsingHistoryStore.shared.recent(limit: 10)
        if entries.isEmpty {
            let empty = NSMenuItem(title: "履歴はありません", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for entry in entries {
                let title = entry.title.isEmpty ? (entry.url?.host ?? entry.urlString) : entry.title
                let item = NSMenuItem(title: title, action: #selector(menuOpenHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.urlString
                item.toolTip = entry.urlString
                menu.addItem(item)
            }
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem("Clear History...", action: #selector(menuClearHistory), key: "", modifiers: []))
    }

    private func rebuildBookmarksMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(makeMenuItem("Show All Bookmarks", action: #selector(menuOpenBookmarksWindow), key: "b", modifiers: [.command, .option]))
        menu.addItem(NSMenuItem.separator())
        let entries = BookmarkStore.shared.all()
        if entries.isEmpty {
            let empty = NSMenuItem(title: "ブックマークはありません", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for entry in entries {
            let title = entry.title.isEmpty ? (entry.url?.host ?? entry.urlString) : entry.title
            let item = NSMenuItem(title: title, action: #selector(menuOpenBookmarkEntry(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.urlString
            item.toolTip = entry.urlString
            menu.addItem(item)
        }
    }

    private func rebuildDevelopMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(makeMenuItem("Open Page Inspector in Safari...", action: #selector(menuToggleWebInspector), key: "i", modifiers: [.command, .option]))
        menu.addItem(makeMenuItem("Privacy & Site Controls...", action: #selector(menuOpenSiteSettings), key: ",", modifiers: [.command, .option]))
        menu.addItem(NSMenuItem.separator())

        let state = mainWindowController?.currentDevelopMenuState()
        let currentSiteTitle: String
        if let host = state?.host, !host.isEmpty {
            currentSiteTitle = "Current Site: \(host)"
        } else {
            currentSiteTitle = "Current Site: none"
        }
        let currentSiteItem = NSMenuItem(title: currentSiteTitle, action: nil, keyEquivalent: "")
        currentSiteItem.isEnabled = false
        menu.addItem(currentSiteItem)

        let blockingStatus = (state?.adBlockingEnabledForSite ?? BrowserPreferences.shared.contentBlockingEnabled) ? "On" : "Off"
        let statusItem = NSMenuItem(title: "Ad Blocking for This Site: \(blockingStatus)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let toggleTitle: String
        if let host = state?.host, !host.isEmpty {
            toggleTitle = (state?.adBlockingEnabledForSite ?? false)
                ? "Turn Off Ad Blocking for \(host)"
                : "Turn On Ad Blocking for \(host)"
        } else {
            toggleTitle = "Change Ad Blocking for This Site"
        }
        let toggleItem = makeMenuItem(toggleTitle, action: #selector(menuToggleContentBlockingForCurrentSite), key: "", modifiers: [])
        toggleItem.isEnabled = state?.host != nil
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeMenuItem("Clear Cookies and Cache...", action: #selector(menuClearBrowsingData), key: "", modifiers: []))
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                openDownloads: { [weak self] in self?.menuOpenDownloads() },
                openHistory: { [weak self] in self?.menuOpenHistoryWindow() },
                openBookmarks: { [weak self] in self?.menuOpenBookmarksWindow() },
                openSiteControls: { [weak self] in self?.menuOpenSiteSettings() }
            )
        }
        preferencesWindowController?.showWindow(self)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


}

private final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {
    private let prefs = BrowserPreferences.shared
    private let openDownloadsAction: () -> Void
    private let openHistoryAction: () -> Void
    private let openBookmarksAction: () -> Void
    private let openSiteControlsAction: () -> Void
    private weak var rootLayoutView: NSView?

    private let homePageField = NSTextField()
    private let searchTemplateField = NSTextField()
    private let contentLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let generalSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let gestureSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let gestureListLabel = NSTextField(wrappingLabelWithString: "")
    private let privacySummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let dataSummaryLabel = NSTextField(wrappingLabelWithString: "")
    private let updatesCheckbox = NSButton(checkboxWithTitle: "アップデート通知を有効化", target: nil, action: nil)
    private let antiTrackingCheckbox = NSButton(checkboxWithTitle: "URLトラッキングパラメータを除去", target: nil, action: nil)
    private let contentBlockingCheckbox = NSButton(checkboxWithTitle: "広告/追跡スクリプトをブロック", target: nil, action: nil)
    private let popupBlockingCheckbox = NSButton(checkboxWithTitle: "勝手に開くポップアップ/新規タブを抑止", target: nil, action: nil)
    private let harmfulSiteWarningCheckbox = NSButton(checkboxWithTitle: "有害サイト警告を表示", target: nil, action: nil)
    private let ephemeralModeCheckbox = NSButton(checkboxWithTitle: "フットプリント最小化（終了時に履歴/Cookieを残さない）", target: nil, action: nil)
    private let doNotTrackCheckbox = NSButton(checkboxWithTitle: "Do Not Track / GPC を送信", target: nil, action: nil)
    private let restoreClosedTabHistoryCheckbox = NSButton(checkboxWithTitle: "閉じたタブを復元したとき、前に見ていたページ履歴も戻す", target: nil, action: nil)
    private let clearDataButton = NSButton(title: "閲覧データを削除", target: nil, action: nil)
    private let sensitivityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gestureTestView = GesturePracticeView(frame: .zero)
    private let summaryLabel = NSTextField(labelWithString: "")
    private let openDownloadsButton = NSButton(title: "", target: nil, action: nil)
    private let openHistoryButton = NSButton(title: "", target: nil, action: nil)
    private let openBookmarksButton = NSButton(title: "", target: nil, action: nil)
    private let openSiteControlsButton = NSButton(title: "", target: nil, action: nil)
    private let downloadFolderLabel = NSTextField(wrappingLabelWithString: "")
    private let chooseDownloadFolderButton = NSButton(title: "ダウンロード先フォルダを選ぶ", target: nil, action: nil)
    private let clearDownloadFolderButton = NSButton(title: "既定に戻す", target: nil, action: nil)
    private var observers: [NSObjectProtocol] = []

    init(
        openDownloads: @escaping () -> Void,
        openHistory: @escaping () -> Void,
        openBookmarks: @escaping () -> Void,
        openSiteControls: @escaping () -> Void
    ) {
        self.openDownloadsAction = openDownloads
        self.openHistoryAction = openHistory
        self.openBookmarksAction = openBookmarks
        self.openSiteControlsAction = openSiteControls
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
        setupObservers()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func setupUI() {
        guard let window else { return }
        let contentView = makeRootContentView(for: window)
        let titleLabel = NSTextField(labelWithString: "Preferences")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .semibold)

        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.stringValue = "ホームページ、ジェスチャー、プライバシー、保存データをここでまとめて管理できます。"

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder
        tabView.drawsBackground = false
        let tabHostView = makeTabHostView(content: tabView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(summaryLabel)
        contentView.addSubview(tabHostView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),

            summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            summaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),

            tabHostView.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 14),
            tabHostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            tabHostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            tabHostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        let homeLabel = makeFieldLabel("スタートページ URL")

        homePageField.translatesAutoresizingMaskIntoConstraints = false
        homePageField.delegate = self
        homePageField.placeholderString = "https://search.fenrir-inc.com/"
        homePageField.controlSize = .large

        let searchLabel = makeFieldLabel("検索 URL テンプレート ({query} を使用)")

        searchTemplateField.translatesAutoresizingMaskIntoConstraints = false
        searchTemplateField.delegate = self
        searchTemplateField.placeholderString = "https://search.fenrir-inc.com/?q={query}"
        searchTemplateField.controlSize = .large

        let contentLanguageLabel = makeFieldLabel("コンテンツ言語")

        contentLanguagePopup.translatesAutoresizingMaskIntoConstraints = false
        contentLanguagePopup.removeAllItems()
        contentLanguagePopup.addItems(withTitles: BrowserPreferences.PreferredContentLanguage.allCases.map(\.displayName))
        contentLanguagePopup.target = self
        contentLanguagePopup.action = #selector(contentLanguageChanged(_:))

        let sensitivityLabel = makeFieldLabel("ジェスチャー感度")

        sensitivityPopup.translatesAutoresizingMaskIntoConstraints = false
        sensitivityPopup.removeAllItems()
        sensitivityPopup.addItems(withTitles: BrowserPreferences.GestureSensitivity.allCases.map(\.displayName))
        sensitivityPopup.target = self
        sensitivityPopup.action = #selector(sensitivityChanged(_:))

        updatesCheckbox.translatesAutoresizingMaskIntoConstraints = false
        updatesCheckbox.target = self
        updatesCheckbox.action = #selector(updatesChanged(_:))

        antiTrackingCheckbox.translatesAutoresizingMaskIntoConstraints = false
        antiTrackingCheckbox.target = self
        antiTrackingCheckbox.action = #selector(antiTrackingChanged(_:))

        contentBlockingCheckbox.translatesAutoresizingMaskIntoConstraints = false
        contentBlockingCheckbox.target = self
        contentBlockingCheckbox.action = #selector(contentBlockingChanged(_:))

        popupBlockingCheckbox.translatesAutoresizingMaskIntoConstraints = false
        popupBlockingCheckbox.target = self
        popupBlockingCheckbox.action = #selector(popupBlockingChanged(_:))

        harmfulSiteWarningCheckbox.translatesAutoresizingMaskIntoConstraints = false
        harmfulSiteWarningCheckbox.target = self
        harmfulSiteWarningCheckbox.action = #selector(harmfulSiteWarningChanged(_:))

        ephemeralModeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        ephemeralModeCheckbox.target = self
        ephemeralModeCheckbox.action = #selector(ephemeralModeChanged(_:))

        doNotTrackCheckbox.translatesAutoresizingMaskIntoConstraints = false
        doNotTrackCheckbox.target = self
        doNotTrackCheckbox.action = #selector(doNotTrackChanged(_:))

        restoreClosedTabHistoryCheckbox.translatesAutoresizingMaskIntoConstraints = false
        restoreClosedTabHistoryCheckbox.target = self
        restoreClosedTabHistoryCheckbox.action = #selector(restoreClosedTabHistoryChanged(_:))

        clearDataButton.translatesAutoresizingMaskIntoConstraints = false
        clearDataButton.target = self
        clearDataButton.action = #selector(clearBrowsingData)

        let resetButton = NSButton(title: "デフォルトに戻す", target: self, action: #selector(resetDefaults))
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.controlSize = .regular
        [openDownloadsButton, openHistoryButton, openBookmarksButton, openSiteControlsButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.target = self
        }
        [chooseDownloadFolderButton, clearDownloadFolderButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.target = self
            $0.controlSize = .regular
        }
        clearDataButton.controlSize = .regular
        openDownloadsButton.action = #selector(openDownloads)
        openHistoryButton.action = #selector(openHistory)
        openBookmarksButton.action = #selector(openBookmarks)
        openSiteControlsButton.action = #selector(openSiteControls)
        chooseDownloadFolderButton.action = #selector(chooseDownloadFolder)
        clearDownloadFolderButton.action = #selector(clearDownloadFolder)

        if #available(macOS 26.0, *) {
            [
                openDownloadsButton,
                openHistoryButton,
                openBookmarksButton,
                openSiteControlsButton,
                chooseDownloadFolderButton,
                clearDownloadFolderButton,
                clearDataButton,
                resetButton
            ].forEach {
                $0.bezelStyle = .glass
            }
        }

        let generalGrid = makeTwoColumnGrid()
        let generalSection = makeSectionContentStack()
        let generalStack = generalSection
        generalStack.addArrangedSubview(configureSummaryLabel(generalSummaryLabel))
        generalStack.addArrangedSubview(homeLabel)
        generalStack.addArrangedSubview(homePageField)
        generalStack.addArrangedSubview(searchLabel)
        generalStack.addArrangedSubview(searchTemplateField)
        let contentLanguageRow = NSStackView()
        contentLanguageRow.translatesAutoresizingMaskIntoConstraints = false
        contentLanguageRow.orientation = .horizontal
        contentLanguageRow.alignment = .centerY
        contentLanguageRow.spacing = 12
        contentLanguageRow.addArrangedSubview(contentLanguageLabel)
        contentLanguageRow.addArrangedSubview(contentLanguagePopup)
        generalStack.addArrangedSubview(contentLanguageRow)
        generalStack.addArrangedSubview(updatesCheckbox)
        generalStack.addArrangedSubview(restoreClosedTabHistoryCheckbox)
        generalStack.addArrangedSubview(generalGrid)
        generalGrid.addArrangedSubview(openDownloadsButton)
        generalGrid.addArrangedSubview(openHistoryButton)

        let gestureSection = makeSectionContentStack()
        let gestureStack = gestureSection
        gestureStack.addArrangedSubview(configureSummaryLabel(gestureSummaryLabel))
        let gestureListTitle = makeFieldLabel("使えるジェスチャー")
        gestureStack.addArrangedSubview(gestureListTitle)
        gestureStack.addArrangedSubview(configureSummaryLabel(gestureListLabel))
        let sensitivityRow = NSStackView()
        sensitivityRow.translatesAutoresizingMaskIntoConstraints = false
        sensitivityRow.orientation = .horizontal
        sensitivityRow.alignment = .centerY
        sensitivityRow.spacing = 12
        sensitivityRow.addArrangedSubview(sensitivityLabel)
        sensitivityRow.addArrangedSubview(sensitivityPopup)
        gestureStack.addArrangedSubview(sensitivityRow)
        let gestureTestNote = NSTextField(wrappingLabelWithString: "この領域で Magic Mouse / トラックパッドのジェスチャー、または右クリックを押しながらのドラッグを試せます。ここでの入力はページ操作に影響しません。")
        gestureTestNote.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        gestureTestNote.textColor = .secondaryLabelColor
        gestureStack.addArrangedSubview(gestureTestNote)
        let gestureTestContainer = NSView()
        gestureTestContainer.translatesAutoresizingMaskIntoConstraints = false
        gestureTestContainer.addSubview(gestureTestView)
        gestureStack.addArrangedSubview(gestureTestContainer)

        let privacySection = makeSectionContentStack()
        let privacyStack = privacySection
        privacyStack.addArrangedSubview(configureSummaryLabel(privacySummaryLabel))
        privacyStack.setCustomSpacing(6, after: privacySummaryLabel)
        privacyStack.addArrangedSubview(antiTrackingCheckbox)
        privacyStack.addArrangedSubview(contentBlockingCheckbox)
        privacyStack.addArrangedSubview(popupBlockingCheckbox)
        privacyStack.addArrangedSubview(harmfulSiteWarningCheckbox)
        privacyStack.addArrangedSubview(ephemeralModeCheckbox)
        privacyStack.addArrangedSubview(doNotTrackCheckbox)

        let dataSection = makeSectionContentStack()
        let dataStack = dataSection
        dataStack.addArrangedSubview(configureSummaryLabel(dataSummaryLabel))
        dataStack.setCustomSpacing(8, after: dataSummaryLabel)
        let dataGrid = makeTwoColumnGrid()
        dataStack.addArrangedSubview(dataGrid)
        dataGrid.addArrangedSubview(openBookmarksButton)
        dataGrid.addArrangedSubview(openSiteControlsButton)
        dataStack.addArrangedSubview(configureSummaryLabel(downloadFolderLabel))
        dataStack.setCustomSpacing(6, after: downloadFolderLabel)
        let downloadFolderButtons = NSStackView()
        downloadFolderButtons.translatesAutoresizingMaskIntoConstraints = false
        downloadFolderButtons.orientation = .horizontal
        downloadFolderButtons.alignment = .centerY
        downloadFolderButtons.spacing = 10
        downloadFolderButtons.addArrangedSubview(chooseDownloadFolderButton)
        downloadFolderButtons.addArrangedSubview(clearDownloadFolderButton)
        dataStack.addArrangedSubview(downloadFolderButtons)
        dataStack.addArrangedSubview(clearDataButton)

        let resetSection = makeSectionContentStack()
        let resetStack = resetSection
        let resetNote = NSTextField(wrappingLabelWithString: "ホームページ、検索、ジェスチャー感度、プライバシー設定を初期状態に戻します。")
        resetNote.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        resetNote.textColor = .secondaryLabelColor
        resetStack.addArrangedSubview(resetNote)
        resetStack.setCustomSpacing(8, after: resetNote)
        resetStack.addArrangedSubview(resetButton)

        NSLayoutConstraint.activate([
            homePageField.widthAnchor.constraint(equalTo: generalSection.widthAnchor),
            searchTemplateField.widthAnchor.constraint(equalTo: generalSection.widthAnchor),
            contentLanguageRow.widthAnchor.constraint(equalTo: generalSection.widthAnchor),
            generalGrid.widthAnchor.constraint(equalTo: generalSection.widthAnchor),

            gestureListLabel.widthAnchor.constraint(equalTo: gestureSection.widthAnchor),
            sensitivityRow.widthAnchor.constraint(equalTo: gestureSection.widthAnchor),
            gestureTestNote.widthAnchor.constraint(equalTo: gestureSection.widthAnchor),
            gestureTestContainer.widthAnchor.constraint(equalTo: gestureSection.widthAnchor),
            gestureTestContainer.heightAnchor.constraint(equalToConstant: 210),
            gestureTestView.leadingAnchor.constraint(equalTo: gestureTestContainer.leadingAnchor),
            gestureTestView.trailingAnchor.constraint(equalTo: gestureTestContainer.trailingAnchor),
            gestureTestView.topAnchor.constraint(equalTo: gestureTestContainer.topAnchor),
            gestureTestView.bottomAnchor.constraint(equalTo: gestureTestContainer.bottomAnchor),

            dataGrid.widthAnchor.constraint(equalTo: dataSection.widthAnchor),
            downloadFolderButtons.widthAnchor.constraint(equalTo: dataSection.widthAnchor)
        ])

        tabView.addTabViewItem(makeTab(title: "General", content: wrapTabContent(generalSection)))
        tabView.addTabViewItem(makeTab(title: "Gestures", content: wrapTabContent(gestureSection)))
        tabView.addTabViewItem(makeTab(title: "Privacy", content: wrapTabContent(privacySection)))
        tabView.addTabViewItem(makeTab(title: "Saved Data", content: wrapTabContent(dataSection)))
        tabView.addTabViewItem(makeTab(title: "Reset", content: wrapTabContent(resetSection)))
    }

    private func makeFieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func configureSummaryLabel(_ label: NSTextField) -> NSTextField {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func setupObservers() {
        let center = NotificationCenter.default
        let names = [
            BrowserPreferences.didChangeNotification,
            BrowsingHistoryStore.didChangeNotification,
            BookmarkStore.didChangeNotification,
            DownloadStore.didChangeNotification,
            MediaPermissionStore.didChangeNotification
        ]
        names.forEach { name in
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.loadValues()
            }
            observers.append(observer)
        }
    }

    private func makeSectionContentStack() -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .gravityAreas
        stack.spacing = 12
        stack.setHuggingPriority(.required, for: .vertical)
        stack.setClippingResistancePriority(.required, for: .vertical)
        return stack
    }

    private func wrapTabContent(_ stack: NSStackView) -> NSView {
        let container = NSView()
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        container.addSubview(scrollView)
        documentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18)
        ])
        return container
    }

    private func makeTab(title: String, content: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = content
        return item
    }

    private func makeTwoColumnGrid() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .leading
        stack.distribution = .fillEqually
        stack.spacing = 10
        return stack
    }

    private func loadValues() {
        homePageField.stringValue = prefs.homePageURLString
        searchTemplateField.stringValue = prefs.searchTemplate
        updatesCheckbox.state = prefs.updatesEnabled ? .on : .off
        antiTrackingCheckbox.state = prefs.antiTrackingEnabled ? .on : .off
        contentBlockingCheckbox.state = prefs.contentBlockingEnabled ? .on : .off
        popupBlockingCheckbox.state = prefs.popupBlockingEnabled ? .on : .off
        harmfulSiteWarningCheckbox.state = prefs.harmfulSiteWarningEnabled ? .on : .off
        ephemeralModeCheckbox.state = prefs.ephemeralModeEnabled ? .on : .off
        doNotTrackCheckbox.state = prefs.sendDoNotTrack ? .on : .off
        restoreClosedTabHistoryCheckbox.state = prefs.restoreClosedTabPageHistory ? .on : .off

        let sensitivity = prefs.gestureSensitivity
        if let index = BrowserPreferences.GestureSensitivity.allCases.firstIndex(of: sensitivity) {
            sensitivityPopup.selectItem(at: index)
        } else {
            sensitivityPopup.selectItem(at: 1)
        }

        let homeHost = URL(string: prefs.homePageURLString)?.host ?? prefs.homePageURLString
        let searchHost = URL(string: prefs.searchTemplate)?.host ?? prefs.searchTemplate
        if let index = BrowserPreferences.PreferredContentLanguage.allCases.firstIndex(of: prefs.preferredContentLanguage) {
            contentLanguagePopup.selectItem(at: index)
        } else {
            contentLanguagePopup.selectItem(at: 0)
        }
        generalSummaryLabel.stringValue = "現在のスタートページ: \(homeHost)\n検索先: \(searchHost)\nコンテンツ言語: \(prefs.preferredContentLanguage.displayName)\n更新通知: \(prefs.updatesEnabled ? "オン" : "オフ")\n閉じたタブの履歴復元: \(prefs.restoreClosedTabPageHistory ? "オン" : "オフ")"

        gestureSummaryLabel.stringValue = "現在の感度: \(sensitivity.displayName)\nMagic Mouse / トラックパッド / 右クリック押下ジェスチャーで共通使用"
        gestureListLabel.stringValue = [
            "→ : 次のタブ",
            "← : 前のタブ",
            "L（↓→）: 現在のタブを閉じる",
            "LL（↓→↓→）: すべてのタブを閉じる",
            "U（↓→↑）: 閉じたタブを復元",
            "O（↑→↓←）: 現在のタブを再読み込み",
            "↑→ : 戻る",
            "↑← : 進む",
            "S（←↓→↓←）: 検索",
            "↓← : 新規タブ"
        ].joined(separator: "\n")
        gestureTestView.sensitivityMultiplier = sensitivity.multiplier

        privacySummaryLabel.stringValue = [
            "追跡除去 \(prefs.antiTrackingEnabled ? "オン" : "オフ")",
            "広告ブロック \(prefs.contentBlockingEnabled ? "オン" : "オフ")",
            "ポップアップ抑止 \(prefs.popupBlockingEnabled ? "オン" : "オフ")",
            "有害サイト警告 \(prefs.harmfulSiteWarningEnabled ? "オン" : "オフ")",
            "フットプリント最小化 \(prefs.ephemeralModeEnabled ? "オン" : "オフ")",
            "DNT/GPC \(prefs.sendDoNotTrack ? "オン" : "オフ")"
        ].joined(separator: " / ")

        let historyCount = BrowsingHistoryStore.shared.all().count
        let bookmarkCount = BookmarkStore.shared.all().count
        let downloadCount = DownloadStore.shared.all().count
        let contentExceptionCount = prefs.contentBlockingDisabledHosts.count
        let harmfulExceptionCount = prefs.harmfulSiteAllowedHosts.count
        let mediaPermissionCount = MediaPermissionStore.shared.all().count
        let downloadFolderPath = prefs.preferredDownloadDirectoryPath

        dataSummaryLabel.stringValue = "履歴 \(historyCount)件 / ブックマーク \(bookmarkCount)件 / ダウンロード \(downloadCount)件\nサイト例外 \(contentExceptionCount + harmfulExceptionCount)件 / メディア権限 \(mediaPermissionCount)件"
        downloadFolderLabel.stringValue = "ダウンロード先: \(downloadFolderPath ?? "毎回確認")"
        openDownloadsButton.title = "ダウンロード一覧を開く (\(downloadCount)件)"
        openHistoryButton.title = "履歴を管理 (\(historyCount)件)"
        openBookmarksButton.title = "ブックマークを管理 (\(bookmarkCount)件)"
        openSiteControlsButton.title = "サイトごとの例外を管理 (\(contentExceptionCount + harmfulExceptionCount + mediaPermissionCount)件)"
        clearDownloadFolderButton.isEnabled = (downloadFolderPath != nil)
    }

    private func makeRootContentView(for window: NSWindow) -> NSView {
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView()
            container.translatesAutoresizingMaskIntoConstraints = false
            let layoutView = NSView()
            layoutView.translatesAutoresizingMaskIntoConstraints = false
            container.contentView = layoutView
            container.spacing = 12
            window.contentView = container
            rootLayoutView = layoutView
            return layoutView
        }

        guard let contentView = window.contentView else {
            let fallback = NSView()
            fallback.translatesAutoresizingMaskIntoConstraints = false
            window.contentView = fallback
            rootLayoutView = fallback
            return fallback
        }
        rootLayoutView = contentView
        return contentView
    }

    private func makeTabHostView(content tabView: NSTabView) -> NSView {
        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.style = .regular
            glassView.cornerRadius = 24

            let contentView = NSView()
            contentView.translatesAutoresizingMaskIntoConstraints = false
            glassView.contentView = contentView
            contentView.addSubview(tabView)

            NSLayoutConstraint.activate([
                tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
                tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
                tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
                tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
            ])
            return glassView
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: container.topAnchor),
            tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field == homePageField {
            prefs.homePageURLString = field.stringValue
        } else if field == searchTemplateField {
            prefs.searchTemplate = field.stringValue
        }
        loadValues()
    }

    @objc private func updatesChanged(_ sender: NSButton) {
        prefs.updatesEnabled = (sender.state == .on)
        loadValues()
    }

    @objc private func contentLanguageChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < BrowserPreferences.PreferredContentLanguage.allCases.count else { return }
        prefs.preferredContentLanguage = BrowserPreferences.PreferredContentLanguage.allCases[index]
        loadValues()
    }

    @objc private func antiTrackingChanged(_ sender: NSButton) {
        prefs.antiTrackingEnabled = (sender.state == .on)
        loadValues()
    }

    @objc private func contentBlockingChanged(_ sender: NSButton) {
        prefs.contentBlockingEnabled = (sender.state == .on)
        loadValues()
    }

    @objc private func popupBlockingChanged(_ sender: NSButton) {
        prefs.popupBlockingEnabled = (sender.state == .on)
        loadValues()
    }

    @objc private func harmfulSiteWarningChanged(_ sender: NSButton) {
        prefs.harmfulSiteWarningEnabled = (sender.state == .on)
        loadValues()
    }

    @objc private func ephemeralModeChanged(_ sender: NSButton) {
        prefs.ephemeralModeEnabled = (sender.state == .on)
        loadValues()
    }

    @objc private func doNotTrackChanged(_ sender: NSButton) {
        prefs.sendDoNotTrack = (sender.state == .on)
        loadValues()
    }

    @objc private func restoreClosedTabHistoryChanged(_ sender: NSButton) {
        prefs.restoreClosedTabPageHistory = (sender.state == .on)
        loadValues()
    }

    @objc private func clearBrowsingData() {
        clearDataButton.isEnabled = false
        BrowserDataCleaner.clearPersistentBrowsingData { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.clearDataButton.isEnabled = true

                let alert = NSAlert()
                switch result {
                case .success:
                    alert.alertStyle = .informational
                    alert.messageText = "閲覧データを削除しました"
                    alert.informativeText = "Cookie、キャッシュ、保存済みサイトデータを削除しました。"
                case .failure(let error):
                    alert.alertStyle = .warning
                    alert.messageText = "閲覧データの削除に失敗しました"
                    alert.informativeText = error.localizedDescription
                }
                if let window = self.window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
        }
    }

    @objc private func sensitivityChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < BrowserPreferences.GestureSensitivity.allCases.count else { return }
        prefs.gestureSensitivity = BrowserPreferences.GestureSensitivity.allCases[index]
        loadValues()
    }

    @objc private func resetDefaults() {
        prefs.resetDefaults()
        loadValues()
    }

    @objc private func openDownloads() {
        openDownloadsAction()
    }

    @objc private func openHistory() {
        openHistoryAction()
    }

    @objc private func openBookmarks() {
        openBookmarksAction()
    }

    @objc private func openSiteControls() {
        openSiteControlsAction()
    }

    @objc private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if let currentURL = prefs.preferredDownloadDirectoryURL() {
            panel.directoryURL = currentURL
        }

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try self.prefs.setPreferredDownloadDirectory(url)
                self.loadValues()
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "ダウンロード先を保存できませんでした"
                alert.informativeText = error.localizedDescription
                if let window = self.window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
        }

        if let window = window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    @objc private func clearDownloadFolder() {
        _ = try? prefs.setPreferredDownloadDirectory(nil)
        loadValues()
    }
}

private final class GesturePracticeView: NSView {
    var sensitivityMultiplier: CGFloat = 1.0 {
        didSet { recognizer = makeRecognizer() }
    }

    private let allowedGestureNames: Set<String> = [
        "UpRight", "UpLeft", "DownRight", "DownLeft",
        "O", "U", "S", "OO", "DownRightDownRight",
        "Right", "Left"
    ]
    private let livePreviewScoreThreshold: CGFloat = 0.52
    private let triggerDominanceRatio: CGFloat = 1.65
    private let triggerWindowMs: TimeInterval = 90
    private let seedHistoryWindowMs: TimeInterval = 240
    private let triggerHorizontalDelta: CGFloat = 4.5
    private let baseMinPathLength: CGFloat = 90
    private let baseMatchScoreThreshold: CGFloat = 0.68
    private let upStrokeDominanceRatio: CGFloat = 2.0

    private struct DeltaSample {
        let dx: CGFloat
        let dy: CGFloat
        let timestamp: TimeInterval
    }

    private enum State {
        case idle
        case capturing
    }

    private var state: State = .idle
    private var recentSamples: [DeltaSample] = []
    private var capturePoints: [CGPoint] = []
    private var rightDragLastPoint: NSPoint?
    private var lastResultName: String?
    private var recognizer = GestureRecognizer(matchScoreThreshold: 0.68, minPathLength: 90, dominanceRatio: 2.0)

    private let titleLabel = NSTextField(labelWithString: "ジェスチャーテスト")
    private let detailLabel = NSTextField(wrappingLabelWithString: "未入力")
    private let canvasLayer = CAShapeLayer()
    private let pathLayer = CAShapeLayer()
    private let borderLayer = CALayer()
    private let fillLayer = CALayer()
    private let outlineLayer = CALayer()
    private var glassBackgroundView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        recognizer = makeRecognizer()
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        recognizer = makeRecognizer()
        commonInit()
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        glassBackgroundView?.frame = bounds
        fillLayer.frame = bounds
        borderLayer.frame = bounds
        outlineLayer.frame = bounds
        pathLayer.frame = bounds
        canvasLayer.frame = bounds
    }

    override func scrollWheel(with event: NSEvent) {
        let xSign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let ySign: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        let dx = event.scrollingDeltaX * xSign
        let dy = event.scrollingDeltaY * ySign
        handleInput(dx: dx, dy: dy, timestamp: event.timestamp, anchorInView: convert(event.locationInWindow, from: nil), shouldCommit: shouldCommitImmediately(for: event))
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        rightDragLastPoint = convert(event.locationInWindow, from: nil)
    }

    override func rightMouseDragged(with event: NSEvent) {
        let current = convert(event.locationInWindow, from: nil)
        guard let last = rightDragLastPoint else {
            rightDragLastPoint = current
            return
        }
        rightDragLastPoint = current
        handleInput(dx: current.x - last.x, dy: current.y - last.y, timestamp: event.timestamp, anchorInView: current, shouldCommit: false)
    }

    override func rightMouseUp(with event: NSEvent) {
        rightDragLastPoint = nil
        if state == .capturing {
            commitCapture()
        }
    }

    private func commonInit() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 14
        layer?.masksToBounds = false

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.translatesAutoresizingMaskIntoConstraints = true
            glassView.style = .regular
            glassView.cornerRadius = 14
            let glassContent = NSView()
            glassContent.translatesAutoresizingMaskIntoConstraints = false
            glassView.contentView = glassContent
            glassBackgroundView = glassView
            addSubview(glassView, positioned: .below, relativeTo: nil)
        } else {
            fillLayer.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
            fillLayer.cornerRadius = 14
            borderLayer.borderWidth = 1
            borderLayer.cornerRadius = 14
            borderLayer.borderColor = NSColor.separatorColor.withAlphaComponent(0.9).cgColor
            layer?.addSublayer(fillLayer)
            layer?.addSublayer(borderLayer)
        }

        outlineLayer.cornerRadius = 14
        outlineLayer.borderWidth = 1
        outlineLayer.borderColor = NSColor.separatorColor.withAlphaComponent(0.58).cgColor
        layer?.addSublayer(outlineLayer)

        pathLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.72).cgColor
        pathLayer.fillColor = NSColor.clear.cgColor
        pathLayer.lineWidth = 2.5
        pathLayer.lineCap = .round
        pathLayer.lineJoin = .round

        layer?.addSublayer(pathLayer)
        layer?.addSublayer(canvasLayer)

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 210),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])

        detailLabel.stringValue = "ここで入力したジェスチャーは動作しません。判定結果だけ表示します。"
    }

    private func handleInput(dx: CGFloat, dy: CGFloat, timestamp: TimeInterval, anchorInView: CGPoint, shouldCommit: Bool) {
        switch state {
        case .idle:
            trackRecent(dx: dx, dy: dy, timestamp: timestamp)
            if shouldStartCapture() {
                startCapture(at: anchorInView, withSeed: recentSamples)
                if shouldCommit {
                    commitCapture()
                }
            }
        case .capturing:
            appendCaptureDelta(dx: dx, dy: dy)
            updateLiveCandidate()
            if shouldCommit {
                commitCapture()
            }
        }
    }

    private func trackRecent(dx: CGFloat, dy: CGFloat, timestamp: TimeInterval) {
        recentSamples.append(DeltaSample(dx: dx, dy: dy, timestamp: timestamp))
        let threshold = timestamp - (seedHistoryWindowMs / 1000)
        recentSamples.removeAll { $0.timestamp < threshold }
    }

    private func shouldStartCapture() -> Bool {
        guard let latestTimestamp = recentSamples.last?.timestamp else { return false }
        let triggerThreshold = latestTimestamp - (triggerWindowMs / 1000)
        let triggerSamples = recentSamples.filter { $0.timestamp >= triggerThreshold }
        guard !triggerSamples.isEmpty else { return false }

        let requiredHorizontal = triggerHorizontalDelta / max(0.75, sensitivityMultiplier)
        if triggerSamples.contains(where: { abs($0.dx) > abs($0.dy) * triggerDominanceRatio && abs($0.dx) > requiredHorizontal }) {
            return true
        }

        let lastSamples = triggerSamples.suffix(4)
        let sumX = lastSamples.reduce(CGFloat.zero) { $0 + $1.dx }
        let sumY = lastSamples.reduce(CGFloat.zero) { $0 + $1.dy }
        return abs(sumX) > abs(sumY) * triggerDominanceRatio && abs(sumX) > requiredHorizontal
    }

    private func startCapture(at point: CGPoint, withSeed seed: [DeltaSample]) {
        state = .capturing
        capturePoints = [point]
        recentSamples.removeAll()
        for sample in seed {
            appendCaptureDelta(dx: sample.dx, dy: sample.dy)
        }
        updateLiveCandidate()
    }

    private func appendCaptureDelta(dx: CGFloat, dy: CGFloat) {
        guard let last = capturePoints.last else { return }
        capturePoints.append(CGPoint(x: last.x + dx, y: last.y + dy))
        redrawPath()
    }

    private func redrawPath() {
        guard capturePoints.count >= 2 else {
            pathLayer.path = nil
            return
        }
        let path = CGMutablePath()
        path.move(to: capturePoints[0])
        for point in capturePoints.dropFirst() {
            path.addLine(to: point)
        }
        pathLayer.path = path
    }

    private func updateLiveCandidate() {
        if let best = recognizer.bestPassingMatch(points: capturePoints, minimumScore: livePreviewScoreThreshold, allowedNames: allowedGestureNames) {
            lastResultName = best.name
            detailLabel.stringValue = "候補: \(displayName(for: best.name))\nscore: \(String(format: "%.2f", best.score))"
            detailLabel.textColor = .secondaryLabelColor
            return
        }

        if let best = recognizer.bestMatch(points: capturePoints, allowedNames: allowedGestureNames) {
            lastResultName = best.name
            detailLabel.stringValue = "候補: \(displayName(for: best.name))\nscore: \(String(format: "%.2f", best.score))\nまだ確定条件に届いていません。"
            detailLabel.textColor = .secondaryLabelColor
        } else {
            detailLabel.stringValue = "判定中..."
            detailLabel.textColor = .secondaryLabelColor
        }
    }

    private func commitCapture() {
        defer { resetCapture() }

        guard !capturePoints.isEmpty else { return }

        let result = recognizer.recognize(points: capturePoints, allowedNames: allowedGestureNames)
            ?? recognizer.bestPassingMatch(
                points: capturePoints,
                minimumScore: max(0.58, baseMatchScoreThreshold - 0.16),
                allowedNames: allowedGestureNames
            )

        if let result {
            detailLabel.stringValue = "確定: \(displayName(for: result.name))\nscore: \(String(format: "%.2f", result.score))"
            detailLabel.textColor = .labelColor
            lastResultName = result.name
        } else if isLikelyDoubleLoop(capturePoints) {
            detailLabel.stringValue = "確定: \(displayName(for: "OO"))\nscore: 0.30"
            detailLabel.textColor = .labelColor
            lastResultName = "OO"
        } else {
            detailLabel.stringValue = "不成立\n認識できる形から外れています。"
            detailLabel.textColor = .systemRed
            lastResultName = nil
        }
    }

    private func resetCapture() {
        state = .idle
        recentSamples.removeAll()
        capturePoints.removeAll()
        rightDragLastPoint = nil
        pathLayer.path = nil
    }

    private func shouldCommitImmediately(for event: NSEvent) -> Bool {
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            return true
        }
        if event.phase == [] && event.momentumPhase.contains(.began) {
            return true
        }
        return false
    }

    private func makeRecognizer() -> GestureRecognizer {
        GestureRecognizer(
            matchScoreThreshold: baseMatchScoreThreshold,
            minPathLength: baseMinPathLength,
            dominanceRatio: upStrokeDominanceRatio
        )
    }

    private func isLikelyDoubleLoop(_ points: [CGPoint]) -> Bool {
        guard points.count >= 16 else { return false }
        var minX = points[0].x
        var maxX = points[0].x
        var minY = points[0].y
        var maxY = points[0].y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let width = maxX - minX
        let height = maxY - minY
        guard width > 24, height > 24 else { return false }
        let diagonal = hypot(width, height)
        guard diagonal > 1 else { return false }
        let closeRatio = hypot(points[0].x - points[points.count - 1].x, points[0].y - points[points.count - 1].y) / diagonal
        guard closeRatio <= 0.68 else { return false }
        let a = max(width * 0.5, 1)
        let b = max(height * 0.5, 1)
        let ellipseCircumference = .pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))
        guard ellipseCircumference > 1 else { return false }
        return pathLength(points) / ellipseCircumference >= 1.22
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for index in 1..<points.count {
            total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        return total
    }

    private func displayName(for gesture: String) -> String {
        switch gesture {
        case "Left": return "← タブ切替"
        case "Right": return "→ タブ切替"
        case "DownRight": return "↓→ タブを閉じる"
        case "DownRightDownRight": return "↓→↓→ 全タブを閉じる"
        case "O": return "O リロード"
        case "OO": return "OO 全タブ再読み込み"
        case "U": return "U 閉じたタブを復元"
        case "UpRight": return "↑→ 戻る"
        case "UpLeft": return "↑← 進む"
        case "DownLeft": return "↓← 新規タブ"
        case "S": return "S 検索"
        default: return gesture
        }
    }
}
