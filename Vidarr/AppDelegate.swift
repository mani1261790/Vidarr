//
//  AppDelegate.swift
//  Vidarr
//
//  Created by 中川誠星 on 2026/02/25.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let windowController = MainWindowController()
        self.mainWindowController = windowController
        windowController.showWindow(self)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}
