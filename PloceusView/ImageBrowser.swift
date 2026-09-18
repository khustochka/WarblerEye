//
//  ImageBrowser.swift
//  PloceusView
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The images in one folder, plus a cursor into them.
///
/// Opening any file adopts its whole folder, so the user can page through
/// siblings without returning to Finder.
@MainActor
@Observable
final class ImageBrowser {
    private(set) var urls: [URL] = []
    private(set) var index: Int = 0
    private(set) var image: NSImage?
    private(set) var errorMessage: String?

    var current: URL? { urls.indices.contains(index) ? urls[index] : nil }
    var canGoNext: Bool { index + 1 < urls.count }
    var canGoPrevious: Bool { index > 0 }

    /// Positional label such as "3 of 57", or nil when nothing is open.
    var position: String? {
        urls.isEmpty ? nil : "\(index + 1) of \(urls.count)"
    }

    /// Content types we are willing to display, as a superset of JPEG so that a
    /// folder of mixed photos still pages through sensibly.
    private static let supportedTypes: Set<UTType> = [
        .jpeg, .png, .heic, .heif, .gif, .tiff, .bmp, .webP
    ]

    /// Opens `url` and loads the sibling images in its folder.
    func open(_ url: URL) {
        urls = Self.siblings(of: url)
        index = urls.firstIndex(of: url.resolvingSymlinksInPath()) ?? 0
        // A file we cannot enumerate the parent of is still worth showing alone.
        if urls.isEmpty {
            urls = [url]
            index = 0
        }
        loadCurrent()
    }

    func next() {
        guard canGoNext else { return }
        index += 1
        loadCurrent()
    }

    func previous() {
        guard canGoPrevious else { return }
        index -= 1
        loadCurrent()
    }

    /// Presents an open panel and adopts whatever the user picks.
    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Array(Self.supportedTypes)
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    private func loadCurrent() {
        guard let url = current else {
            image = nil
            errorMessage = nil
            return
        }
        if let loaded = NSImage(contentsOf: url) {
            image = loaded
            errorMessage = nil
        } else {
            image = nil
            errorMessage = "Could not read \(url.lastPathComponent)."
        }
    }

    /// Image files in the same folder as `url`, including `url`, in Finder order.
    private static func siblings(of url: URL) -> [URL] {
        let resolved = url.resolvingSymlinksInPath()
        let folder = resolved.deletingLastPathComponent()
        let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        guard let contents else { return [] }

        return contents
            .filter(isSupportedImage)
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }
    }

    private static func isSupportedImage(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey])
        guard values?.isRegularFile == true, let type = values?.contentType else {
            return false
        }
        return supportedTypes.contains { type.conforms(to: $0) }
    }
}
