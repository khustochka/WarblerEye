//
//  PloceusViewApp.swift
//  PloceusView
//
//  Created by Vitalii Khustochka on 2026-09-18.
//

import AppKit
import SwiftUI

/// Receives the files Finder sends on double-click or "Open With".
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set before the first file arrives; the browser outlives each open event.
    @MainActor var browser: ImageBrowser?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated {
            browser?.open(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct PloceusViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var browser = ImageBrowser()

    var body: some Scene {
        WindowGroup {
            ContentView(browser: browser)
                .onAppear { appDelegate.browser = browser }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { browser.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Image") {
                Button("Next Image") { browser.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(!browser.canGoNext)

                Button("Previous Image") { browser.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(!browser.canGoPrevious)
            }
        }
    }
}
