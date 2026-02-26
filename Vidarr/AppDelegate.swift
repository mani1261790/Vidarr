//
//  AppDelegate.swift
//  Vidarr
//
//  Created by Mani on 2026/02/25.
//

import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private let updateChecker = UpdateChecker()
    private var hasPresentedUpdateAlert = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMainMenu()
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }

        let windowController = MainWindowController()
        mainWindowController = windowController

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
        // Insert code here to tear down your application
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
    private let ephemeralModeCheckbox = NSButton(checkboxWithTitle: "フットプリント最小化（終了時に履歴/Cookieを残さない）", target: nil, action: nil)
    private let doNotTrackCheckbox = NSButton(checkboxWithTitle: "Do Not Track / GPC を送信", target: nil, action: nil)
    private let clearDataButton = NSButton(title: "閲覧データを削除", target: nil, action: nil)
    private let sensitivityPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
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

            ephemeralModeCheckbox.topAnchor.constraint(equalTo: antiTrackingCheckbox.bottomAnchor, constant: 8),
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
