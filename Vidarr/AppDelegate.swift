//
//  AppDelegate.swift
//  Vidarr
//
//  Created by 中川誠星 on 2026/02/25.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    private let updateChecker = UpdateChecker()
    private var hasPresentedUpdateAlert = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.regular)
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


}
