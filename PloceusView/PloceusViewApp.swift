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

extension Notification.Name {
    static let zoomIn = Notification.Name("PloceusViewZoomIn")
    static let zoomOut = Notification.Name("PloceusViewZoomOut")
    static let zoomActual = Notification.Name("PloceusViewZoomActual")
    static let zoomFit = Notification.Name("PloceusViewZoomFit")
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
            // The bare arrow keys are handled by the focused image view, so
            // these carry Command-modified shortcuts to avoid swallowing them.
            CommandMenu("Image") {
                Button("Next Image") { browser.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!browser.canGoNext)

                Button("Previous Image") { browser.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(!browser.canGoPrevious)

                Divider()

                Button("Forward 10") { browser.advance(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(!browser.canGoNext)

                Button("Back 10") { browser.advance(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(!browser.canGoPrevious)

                Button("Forward 100") { browser.advance(by: 100) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                    .disabled(!browser.canGoNext)

                Button("Back 100") { browser.advance(by: -100) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                    .disabled(!browser.canGoPrevious)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo Move to Trash") { browser.undoTrash() }
                    .keyboardShortcut("z")
                    .disabled(!browser.canUndo)
            }

            CommandGroup(after: .saveItem) {
                Button("Move to Trash") { browser.trashCurrent() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(browser.current == nil)
            }

            // Zoom has no on-screen controls, so the menu is where it is found.
            CommandGroup(after: .sidebar) {
                Button("Zoom In") { NotificationCenter.default.post(name: .zoomIn, object: nil) }
                    .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") { NotificationCenter.default.post(name: .zoomOut, object: nil) }
                    .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") { NotificationCenter.default.post(name: .zoomActual, object: nil) }
                    .keyboardShortcut("0", modifiers: .command)

                Button("Fit to Window") { NotificationCenter.default.post(name: .zoomFit, object: nil) }
                    .keyboardShortcut("/", modifiers: .command)

                Divider()
            }
        }
    }
}
