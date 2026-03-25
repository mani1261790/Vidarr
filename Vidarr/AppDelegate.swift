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

        developMenu.addItem(makeMenuItem("Open Page Inspector", action: #selector(menuToggleWebInspector), key: "i", modifiers: [.command, .option]))
        developMenu.addItem(makeMenuItem("Privacy & Site Controls...", action: #selector(menuOpenSiteSettings), key: ",", modifiers: [.command, .option]))
        developMenu.addItem(makeMenuItem("Turn Ad Blocking On/Off for This Site", action: #selector(menuToggleContentBlockingForCurrentSite), key: "", modifiers: []))
        developMenu.addItem(makeMenuItem("Clear Cookies and Cache...", action: #selector(menuClearBrowsingData), key: "", modifiers: []))

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

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(self)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


}

private final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {
    private let prefs = BrowserPreferences.shared

    private let homePageField = NSTextField()
    private let searchTemplateField = NSTextField()
    private let updatesCheckbox = NSButton(checkboxWithTitle: "アップデート通知を有効化", target: nil, action: nil)
    private let antiTrackingCheckbox = NSButton(checkboxWithTitle: "URLトラッキングパラメータを除去", target: nil, action: nil)
    private let contentBlockingCheckbox = NSButton(checkboxWithTitle: "広告/追跡スクリプトをブロック", target: nil, action: nil)
    private let popupBlockingCheckbox = NSButton(checkboxWithTitle: "勝手に開くポップアップ/新規タブを抑止", target: nil, action: nil)
    private let harmfulSiteWarningCheckbox = NSButton(checkboxWithTitle: "有害サイト警告を表示", target: nil, action: nil)
    private let ephemeralModeCheckbox = NSButton(checkboxWithTitle: "フットプリント最小化（終了時に履歴/Cookieを残さない）", target: nil, action: nil)
    private let doNotTrackCheckbox = NSButton(checkboxWithTitle: "Do Not Track / GPC を送信", target: nil, action: nil)
    private let clearDataButton = NSButton(title: "閲覧データを削除", target: nil, action: nil)
    private let sensitivityPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let homeLabel = NSTextField(labelWithString: "スタートページ URL")
        homeLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        homeLabel.translatesAutoresizingMaskIntoConstraints = false

        homePageField.translatesAutoresizingMaskIntoConstraints = false
        homePageField.delegate = self
        homePageField.placeholderString = "https://search.fenrir-inc.com/"

        let searchLabel = NSTextField(labelWithString: "検索 URL テンプレート ({query} を使用)")
        searchLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        searchLabel.translatesAutoresizingMaskIntoConstraints = false

        searchTemplateField.translatesAutoresizingMaskIntoConstraints = false
        searchTemplateField.delegate = self
        searchTemplateField.placeholderString = "https://search.fenrir-inc.com/?q={query}"

        let sensitivityLabel = NSTextField(labelWithString: "ジェスチャー感度")
        sensitivityLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        sensitivityLabel.translatesAutoresizingMaskIntoConstraints = false

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

        clearDataButton.translatesAutoresizingMaskIntoConstraints = false
        clearDataButton.target = self
        clearDataButton.action = #selector(clearBrowsingData)

        let resetButton = NSButton(title: "デフォルトに戻す", target: self, action: #selector(resetDefaults))
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(homeLabel)
        root.addSubview(homePageField)
        root.addSubview(searchLabel)
        root.addSubview(searchTemplateField)
        root.addSubview(sensitivityLabel)
        root.addSubview(sensitivityPopup)
        root.addSubview(updatesCheckbox)
        root.addSubview(antiTrackingCheckbox)
        root.addSubview(contentBlockingCheckbox)
        root.addSubview(popupBlockingCheckbox)
        root.addSubview(harmfulSiteWarningCheckbox)
        root.addSubview(ephemeralModeCheckbox)
        root.addSubview(doNotTrackCheckbox)
        root.addSubview(clearDataButton)
        root.addSubview(resetButton)

        NSLayoutConstraint.activate([
            homeLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            homeLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            homeLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            homePageField.topAnchor.constraint(equalTo: homeLabel.bottomAnchor, constant: 6),
            homePageField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            homePageField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            searchLabel.topAnchor.constraint(equalTo: homePageField.bottomAnchor, constant: 16),
            searchLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            searchLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            searchTemplateField.topAnchor.constraint(equalTo: searchLabel.bottomAnchor, constant: 6),
            searchTemplateField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            searchTemplateField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            sensitivityLabel.topAnchor.constraint(equalTo: searchTemplateField.bottomAnchor, constant: 16),
            sensitivityLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            sensitivityPopup.centerYAnchor.constraint(equalTo: sensitivityLabel.centerYAnchor),
            sensitivityPopup.leadingAnchor.constraint(equalTo: sensitivityLabel.trailingAnchor, constant: 12),
            sensitivityPopup.widthAnchor.constraint(equalToConstant: 120),

            updatesCheckbox.topAnchor.constraint(equalTo: sensitivityLabel.bottomAnchor, constant: 16),
            updatesCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            antiTrackingCheckbox.topAnchor.constraint(equalTo: updatesCheckbox.bottomAnchor, constant: 10),
            antiTrackingCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            contentBlockingCheckbox.topAnchor.constraint(equalTo: antiTrackingCheckbox.bottomAnchor, constant: 8),
            contentBlockingCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            popupBlockingCheckbox.topAnchor.constraint(equalTo: contentBlockingCheckbox.bottomAnchor, constant: 8),
            popupBlockingCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            harmfulSiteWarningCheckbox.topAnchor.constraint(equalTo: popupBlockingCheckbox.bottomAnchor, constant: 8),
            harmfulSiteWarningCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            ephemeralModeCheckbox.topAnchor.constraint(equalTo: harmfulSiteWarningCheckbox.bottomAnchor, constant: 8),
            ephemeralModeCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            doNotTrackCheckbox.topAnchor.constraint(equalTo: ephemeralModeCheckbox.bottomAnchor, constant: 8),
            doNotTrackCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            clearDataButton.topAnchor.constraint(equalTo: doNotTrackCheckbox.bottomAnchor, constant: 14),
            clearDataButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            resetButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            resetButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])
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

        let sensitivity = prefs.gestureSensitivity
        if let index = BrowserPreferences.GestureSensitivity.allCases.firstIndex(of: sensitivity) {
            sensitivityPopup.selectItem(at: index)
        } else {
            sensitivityPopup.selectItem(at: 1)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field == homePageField {
            prefs.homePageURLString = field.stringValue
        } else if field == searchTemplateField {
            prefs.searchTemplate = field.stringValue
        }
    }

    @objc private func updatesChanged(_ sender: NSButton) {
        prefs.updatesEnabled = (sender.state == .on)
    }

    @objc private func antiTrackingChanged(_ sender: NSButton) {
        prefs.antiTrackingEnabled = (sender.state == .on)
    }

    @objc private func contentBlockingChanged(_ sender: NSButton) {
        prefs.contentBlockingEnabled = (sender.state == .on)
    }

    @objc private func popupBlockingChanged(_ sender: NSButton) {
        prefs.popupBlockingEnabled = (sender.state == .on)
    }

    @objc private func harmfulSiteWarningChanged(_ sender: NSButton) {
        prefs.harmfulSiteWarningEnabled = (sender.state == .on)
    }

    @objc private func ephemeralModeChanged(_ sender: NSButton) {
        prefs.ephemeralModeEnabled = (sender.state == .on)
    }

    @objc private func doNotTrackChanged(_ sender: NSButton) {
        prefs.sendDoNotTrack = (sender.state == .on)
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
    }

    @objc private func resetDefaults() {
        prefs.resetDefaults()
        loadValues()
    }
}
