//
//  ImageBrowser.swift
//  WarblerEye
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The facts about a file shown in the status bar.
///
/// Reads only the file header, so it is safe to build off the main actor while
/// prefetching.
nonisolated struct ImageInfo {
    var pixelSize: CGSize
    var colorModel: String
    var format: String
    var byteCount: Int
    var date: Date?

    /// Whether `date` is the camera's capture time rather than the file's
    /// modification time. The two need different clocks when displayed.
    var dateIsCaptureTime: Bool = false

    /// Every property the file declares, grouped as ImageIO reports them and
    /// rendered as text. Flattened at read time rather than held as the raw
    /// dictionary so the struct stays sendable across the prefetch boundary.
    var metadata: [MetadataGroup] = []

    var dimensions: String {
        "\(Int(pixelSize.width))x\(Int(pixelSize.height))"
    }

    /// File size in kB, matching the decimal units Finder reports.
    var fileSize: String {
        "\(byteCount / 1000) kB"
    }

    var timestamp: String? {
        guard let date else { return nil }
        let formatter = dateIsCaptureTime
            ? Self.captureTimestampFormatter
            : Self.fileTimestampFormatter
        return formatter.string(from: date)
    }

    /// Renders a capture time. Shares the parser's UTC zone so the digits
    /// survive the round trip unshifted: EXIF records no zone, so 14:30 is the
    /// wall clock at the shutter and should read back as 14:30 wherever the
    /// file is later opened.
    private static let captureTimestampFormatter = timestampFormatter(
        timeZone: TimeZone(secondsFromGMT: 0)
    )

    /// Renders a file modification time, which unlike a capture time is a real
    /// instant, so it belongs in the reader's own zone as Finder shows it.
    private static let fileTimestampFormatter = timestampFormatter(timeZone: nil)

    /// Built once each: the status bar reads `timestamp` on every redraw, and
    /// a DateFormatter is expensive to construct.
    private static func timestampFormatter(timeZone: TimeZone?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let timeZone { formatter.timeZone = timeZone }
        return formatter
    }

    /// Parses EXIF's own timestamp format. Fixed to POSIX because the pattern
    /// is the file's, not the reader's: a non-Gregorian system calendar would
    /// otherwise read the digits as its own era.
    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Reads the metadata without decoding the image itself.
    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            return nil
        }

        pixelSize = CGSize(
            width: properties[kCGImagePropertyPixelWidth] as? Double ?? 0,
            height: properties[kCGImagePropertyPixelHeight] as? Double ?? 0
        )

        // The preferred extension ("jpeg", "png") reads more tersely in the
        // status bar than the localized description ("JPEG image").
        let type = CGImageSourceGetType(source) as String?
        format = type.flatMap { UTType($0)?.preferredFilenameExtension?.uppercased() }
            ?? "Image"

        colorModel = Self.colorModel(from: properties)
        byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let captured = Self.captureDate(from: properties)
        dateIsCaptureTime = captured != nil
        date = captured
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        metadata = MetadataGroup.groups(from: properties)
    }

    /// The color model, preferring the profile name over the raw model since
    /// "sRGB" says more to a person than "RGB".
    private static func colorModel(from properties: [CFString: Any]) -> String {
        if let profile = properties[kCGImagePropertyProfileName] as? String {
            // Trim the version noise in names like "sRGB IEC61966-2.1".
            return profile.split(separator: " ").first.map(String.init) ?? profile
        }
        if let model = properties[kCGImagePropertyColorModel] as? String {
            return model
        }
        return "—"
    }

    /// When the photo was taken, which is more meaningful than when the file
    /// was written.
    private static func captureDate(from properties: [CFString: Any]) -> Date? {
        guard let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = (exif[kCGImagePropertyExifDateTimeOriginal]
                ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String else {
            return nil
        }
        return exifDateFormatter.date(from: raw)
    }
}

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
    private(set) var info: ImageInfo?
    private(set) var errorMessage: String?

    /// Decoded neighbours, so paging does not wait on a decode.
    private var cache: [URL: Loaded] = [:]

    /// Prefetches in flight, kept so they can be cancelled when the user moves
    /// somewhere else and their results are no longer wanted.
    private var prefetching: [URL: Task<Void, Never>] = [:]

    /// Which way the user is moving, so the cache fills ahead of them.
    private var direction = 1

    /// Files trashed this session, newest last, so they can be put back.
    /// Each entry keeps where the file sat in the list so undo restores order.
    private var trashed: [(url: URL, trashURL: URL, index: Int)] = []

    /// A short note for the status bar, such as a trash or undo confirmation.
    private(set) var notice: String?

    var canUndo: Bool { !trashed.isEmpty }

    /// How many images to keep decoded on either side of the current one.
    /// Each is a full-resolution bitmap, so this trades memory for latency.
    private static let prefetchRadius = 2

    struct Loaded: @unchecked Sendable {
        var image: NSImage
        var info: ImageInfo?
    }

    var current: URL? { urls.indices.contains(index) ? urls[index] : nil }
    var canGoNext: Bool { index + 1 < urls.count }
    var canGoPrevious: Bool { index > 0 }

    /// Positional label such as "3/57", or nil when nothing is open.
    var position: String? {
        urls.isEmpty ? nil : "\(index + 1)/\(urls.count)"
    }

    /// Content types we are willing to display, as a superset of JPEG so that a
    /// folder of mixed photos still pages through sensibly.
    private static let supportedTypes: Set<UTType> = [
        .jpeg, .png, .heic, .heif, .gif, .tiff, .bmp, .webP
    ]

    /// Opens `url` and loads the sibling images in its folder.
    func open(_ url: URL) {
        for task in prefetching.values { task.cancel() }
        prefetching.removeAll()
        cache.removeAll()
        urls = Self.siblings(of: url)
        index = urls.firstIndex(of: url.resolvingSymlinksInPath()) ?? 0
        // A file we cannot enumerate the parent of is still worth showing alone.
        if urls.isEmpty {
            urls = [url]
            index = 0
        }
        loadCurrent()
    }

    func next() { advance(by: 1) }

    func previous() { advance(by: -1) }

    /// Moves `offset` images through the folder, stopping at either end.
    ///
    /// Clamping rather than refusing means a large jump near the end still
    /// lands on the last image instead of doing nothing.
    func advance(by offset: Int) {
        guard !urls.isEmpty else { return }
        let target = min(max(index + offset, 0), urls.count - 1)
        guard target != index else { return }
        direction = target > index ? 1 : -1
        index = target
        loadCurrent(clearingNotice: true)
    }

    /// Moves the current image to the Trash and shows the next one.
    func trashCurrent() {
        guard let url = current else { return }

        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            notice = "Could not move \(url.lastPathComponent) to the Trash."
            return
        }

        let removed = index
        if let trashURL = resulting as URL? {
            trashed.append((url: url, trashURL: trashURL, index: removed))
        }

        cache[url] = nil
        prefetching[url]?.cancel()
        prefetching[url] = nil
        urls.remove(at: removed)

        // Stay on the same position, which is now the following image, unless
        // the last one was removed.
        index = min(removed, max(urls.count - 1, 0))
        notice = "Moved \(url.lastPathComponent) to Trash"
        loadCurrent()
    }

    /// Puts the most recently trashed file back and returns to it.
    func undoTrash() {
        guard let entry = trashed.popLast() else { return }

        do {
            try FileManager.default.moveItem(at: entry.trashURL, to: entry.url)
        } catch {
            notice = "Could not restore \(entry.url.lastPathComponent)."
            return
        }

        let target = min(entry.index, urls.count)
        urls.insert(entry.url, at: target)
        index = target
        notice = "Restored \(entry.url.lastPathComponent)"
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

    private func loadCurrent(clearingNotice: Bool = false) {
        if clearingNotice { notice = nil }
        guard let url = current else {
            image = nil
            info = nil
            errorMessage = nil
            return
        }

        if let hit = cache[url] {
            image = hit.image
            info = hit.info
            errorMessage = nil
        } else if let loaded = NSImage(contentsOf: url) {
            let entry = Loaded(image: loaded, info: ImageInfo(url: url))
            cache[url] = entry
            image = entry.image
            info = entry.info
            errorMessage = nil
        } else {
            image = nil
            info = nil
            errorMessage = "Could not read \(url.lastPathComponent)."
        }

        prefetchNeighbours()
    }

    /// Decodes the images around the current one, ahead of the user first.
    private func prefetchNeighbours() {
        let wanted = neighbourURLs()

        // Drop anything outside the window, cancelling work still in flight.
        let keep = Set(wanted + [current].compactMap { $0 })
        cache = cache.filter { keep.contains($0.key) }
        for (url, task) in prefetching where !keep.contains(url) {
            task.cancel()
            prefetching[url] = nil
        }

        for url in wanted where cache[url] == nil && prefetching[url] == nil {
            prefetching[url] = Task { [weak self] in
                // Decoding is the slow part, so keep it off the main actor.
                let loaded = await Task.detached(priority: .utility) { () -> Loaded? in
                    guard let image = NSImage(contentsOf: url) else { return nil }
                    return Loaded(image: image, info: ImageInfo(url: url))
                }.value

                guard !Task.isCancelled else { return }
                // This task already runs on the main actor; only the decode
                // above was detached.
                self?.store(loaded, for: url)
            }
        }
    }

    @MainActor
    private func store(_ loaded: Loaded?, for url: URL) {
        prefetching[url] = nil
        guard let loaded else { return }
        // The window may have moved on while this was decoding.
        guard neighbourURLs().contains(url) || url == current else { return }
        cache[url] = loaded
    }

    /// The neighbours worth holding, nearest first and favouring the direction
    /// of travel so the next image is always the first one fetched.
    private func neighbourURLs() -> [URL] {
        var offsets: [Int] = []
        for step in 1...Self.prefetchRadius {
            offsets.append(direction * step)
            offsets.append(-direction * step)
        }
        return offsets
            .map { index + $0 }
            .filter { urls.indices.contains($0) }
            .map { urls[$0] }
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
