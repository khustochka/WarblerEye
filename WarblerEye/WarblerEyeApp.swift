//
//  WarblerEyeApp.swift
//  WarblerEye
//
//  Created by Vitalii Khustochka on 2026-09-18.
//

import AppKit
import SwiftUI

/// Routes the files Finder sends to windows, one image per window.
///
/// macOS opens a fresh untitled window whenever the app is activated with a
/// file, and only then delivers the URL. So an empty window offers itself here
/// and takes the next arrival; a file with no empty window waiting gets one of
/// its own.
@MainActor
final class OpenCoordinator {
    /// Opens a URL in a window of its own. Set once the scene can create them.
    fileprivate var openInNewWindow: ((URL) -> Void)?

    /// Empty windows waiting for a file, oldest first.
    private var idle: [Idle] = []

    /// Files that arrived before anything could show them, in order.
    private var pending: [URL] = []

    private struct Idle {
        let token: ObjectIdentifier
        let show: (URL) -> Void
    }

    /// Offers an empty window as the home for the next file to arrive.
    /// Re-offering the same window replaces its earlier entry.
    func offerIdle(_ token: ObjectIdentifier, show: @escaping (URL) -> Void) {
        idle.removeAll { $0.token == token }
        idle.append(Idle(token: token, show: show))
        deliver()
    }

    /// Withdraws a window that is no longer empty.
    func withdraw(_ token: ObjectIdentifier) {
        idle.removeAll { $0.token == token }
    }

    /// Takes in files from Finder.
    func receive(_ urls: [URL]) {
        pending.append(contentsOf: urls)
        deliver()
    }

    /// Hands each waiting file to an idle window, or to a new one.
    private func deliver() {
        while !pending.isEmpty {
            if !idle.isEmpty {
                let window = idle.removeFirst()
                window.show(pending.removeFirst())
            } else if let openInNewWindow {
                openInNewWindow(pending.removeFirst())
            } else {
                // No window can be made yet; the next offer or scene will
                // come back for these.
                return
            }
        }
    }

    /// Called once the scene can open windows, for files that beat it there.
    fileprivate func sceneReady(_ open: @escaping (URL) -> Void) {
        openInNewWindow = open
        deliver()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let coordinator = OpenCoordinator()

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { coordinator.receive(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct WarblerEyeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    /// Browser of the window the menus act on: whichever window has focus.
    @FocusedValue(\.browser) private var focusedBrowser
    @FocusedValue(\.zoom) private var focusedZoom

    var body: some Scene {
        // Keyed by URL so every file gets a window of its own, each with its
        // own browser: the state that used to be shared app-wide, which made
        // a newly opened image replace the one already on screen.
        WindowGroup(for: URL.self) { $url in
            WindowContent(url: url, coordinator: appDelegate.coordinator)
                .onAppear {
                    appDelegate.coordinator.sceneReady { openWindow(value: $0) }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { showOpenPanel() }
                    .keyboardShortcut("o")
            }
            // The bare arrow keys are handled by the focused image view, so
            // these carry Command-modified shortcuts to avoid swallowing them.
            CommandMenu("Image") {
                Button("Next Image") { focusedBrowser?.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(focusedBrowser?.canGoNext != true)

                Button("Previous Image") { focusedBrowser?.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(focusedBrowser?.canGoPrevious != true)

                Divider()

                Button("Forward 10") { focusedBrowser?.advance(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(focusedBrowser?.canGoNext != true)

                Button("Back 10") { focusedBrowser?.advance(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(focusedBrowser?.canGoPrevious != true)

                Button("Forward 100") { focusedBrowser?.advance(by: 100) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                    .disabled(focusedBrowser?.canGoNext != true)

                Button("Back 100") { focusedBrowser?.advance(by: -100) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                    .disabled(focusedBrowser?.canGoPrevious != true)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo Move to Trash") { focusedBrowser?.undoTrash() }
                    .keyboardShortcut("z")
                    .disabled(focusedBrowser?.canUndo != true)
            }

            CommandGroup(after: .saveItem) {
                Button("Move to Trash") { focusedBrowser?.trashCurrent() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(focusedBrowser?.current == nil)
            }

            // Zoom has no on-screen controls, so the menu is where it is found.
            CommandGroup(after: .sidebar) {
                Button("Zoom In") { focusedZoom?.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(focusedZoom == nil)

                Button("Zoom Out") { focusedZoom?.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(focusedZoom == nil)

                Button("Actual Size") { focusedZoom?.actualSize() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(focusedZoom == nil)

                Button("Fit to Window") { focusedZoom?.fitToWindow() }
                    .keyboardShortcut("/", modifiers: .command)
                    .disabled(focusedZoom == nil)

                Toggle("Keep Zoom and Position", isOn: Binding(
                    get: { focusedZoom?.keepsView ?? false },
                    set: { _ in focusedZoom?.toggleKeepsView() }
                ))
                .keyboardShortcut("l", modifiers: .command)
                .disabled(focusedZoom == nil)

                Divider()
            }
        }
    }

    /// Presents an open panel and shows the chosen file in a window of its own.
    @MainActor
    private func showOpenPanel() {
        guard let url = ImageBrowser.runOpenPanel() else { return }
        openWindow(value: url)
    }
}

/// One window's worth of state: a browser of its own.
///
/// A window opened with a URL shows that file. One opened without — at launch,
/// on activation, or by New Window — offers itself to the coordinator, so the
/// file macOS is about to deliver lands here instead of in another window.
private struct WindowContent: View {
    let url: URL?
    let coordinator: OpenCoordinator

    @State private var browser = ImageBrowser()

    var body: some View {
        ContentView(browser: browser)
            .focusedSceneValue(\.browser, browser)
            .task(id: url) {
                let token = ObjectIdentifier(browser)
                if let url {
                    coordinator.withdraw(token)
                    if url != browser.current { browser.open(url) }
                } else if browser.current == nil {
                    coordinator.offerIdle(token) { browser.open($0) }
                }
            }
            .onDisappear { coordinator.withdraw(ObjectIdentifier(browser)) }
    }
}

/// Lets the menu commands reach the browser of the front window.
private struct BrowserFocusedValueKey: FocusedValueKey {
    typealias Value = ImageBrowser
}

extension FocusedValues {
    fileprivate var browser: ImageBrowser? {
        get { self[BrowserFocusedValueKey.self] }
        set { self[BrowserFocusedValueKey.self] = newValue }
    }
}
