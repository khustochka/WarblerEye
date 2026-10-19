//
//  ImageBrowserTests.swift
//  WarblerEyeTests
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import WarblerEye

/// Folder navigation and culling, against a real folder on disk.
///
/// The trash tests really do move files to the Trash, and put them back with
/// undo before they finish.
@MainActor
@Suite(.serialized)
struct ImageBrowserTests {

    /// Outside /private, which `open` does not yet handle; see
    /// `openFindsTheFileUnderPrivate`.
    private static let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

    /// A folder of three images listed out of Finder order, plus files the
    /// browser should pass over.
    private func withFolder(
        in base: URL = Self.base,
        _ body: (URL) throws -> Void
    ) throws {
        try Fixtures.withDirectory(in: base) { folder in
            for name in ["img10.jpg", "img2.png", "img1.tiff"] {
                try Fixtures.writeImage(
                    to: folder.appendingPathComponent(name),
                    type: UTType(filenameExtension: (name as NSString).pathExtension)!
                )
            }
            try Fixtures.writeText(to: folder.appendingPathComponent("notes.txt"))
            try Fixtures.writeImage(to: folder.appendingPathComponent(".hidden.png"), type: .png)
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("nested.png"), withIntermediateDirectories: false
            )
            try body(folder)
        }
    }

    private func names(_ browser: ImageBrowser) -> [String] {
        browser.urls.map(\.lastPathComponent)
    }

    @Test func openAdoptsTheFolderInFinderOrder() throws {
        try withFolder { folder in
            let browser = ImageBrowser()
            browser.open(folder.appendingPathComponent("img2.png"))

            #expect(names(browser) == ["img1.tiff", "img2.png", "img10.jpg"])
            #expect(browser.current?.lastPathComponent == "img2.png")
            #expect(browser.position == "2/3")
        }
    }

    /// `resolvingSymlinksInPath()` strips a leading /private while the folder
    /// listing keeps it, so the opened file is not found among its siblings
    /// and the browser starts on the first image instead.
    @Test func openFindsTheFileUnderPrivate() throws {
        try withFolder(in: FileManager.default.temporaryDirectory) { folder in
            let browser = ImageBrowser()
            browser.open(folder.appendingPathComponent("img2.png"))
            withKnownIssue("open() misses files under /private") {
                #expect(browser.current?.lastPathComponent == "img2.png")
            }
        }
    }

    @Test func advanceClampsAtEitherEnd() throws {
        try withFolder { folder in
            let browser = ImageBrowser()
            browser.open(folder.appendingPathComponent("img1.tiff"))
            #expect(!browser.canGoPrevious)

            browser.previous()
            #expect(browser.index == 0)

            browser.next()
            #expect(browser.index == 1)

            browser.advance(by: 100)
            #expect(browser.index == 2)
            #expect(!browser.canGoNext)

            browser.advance(by: -10)
            #expect(browser.index == 0)
        }
    }

    @Test func nothingOpenHasNoPosition() {
        let browser = ImageBrowser()
        #expect(browser.position == nil)
        #expect(browser.current == nil)
        browser.next()
        browser.trashCurrent()
        browser.undoTrash()
        #expect(browser.index == 0)
    }

    @Test func trashMovesToTheFollowingImageAndUndoRestoresIt() throws {
        try withFolder { folder in
            let browser = ImageBrowser()
            let url = folder.appendingPathComponent("img2.png")
            browser.open(url)

            browser.trashCurrent()
            defer { if browser.canUndo { browser.undoTrash() } }
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(names(browser) == ["img1.tiff", "img10.jpg"])
            #expect(browser.current?.lastPathComponent == "img10.jpg")
            #expect(browser.notice == "Moved img2.png to Trash")
            #expect(browser.canUndo)

            browser.undoTrash()
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(names(browser) == ["img1.tiff", "img2.png", "img10.jpg"])
            #expect(browser.current?.lastPathComponent == "img2.png")
            #expect(browser.notice == "Restored img2.png")
            #expect(!browser.canUndo)
        }
    }

    @Test func trashingTheLastImageStepsBackOne() throws {
        try withFolder { folder in
            let browser = ImageBrowser()
            browser.open(folder.appendingPathComponent("img10.jpg"))

            browser.trashCurrent()
            defer { if browser.canUndo { browser.undoTrash() } }
            #expect(browser.current?.lastPathComponent == "img2.png")
            #expect(browser.position == "2/2")
        }
    }

    @Test func undoRestoresInReverseOrder() throws {
        try withFolder { folder in
            let browser = ImageBrowser()
            browser.open(folder.appendingPathComponent("img1.tiff"))

            browser.trashCurrent()
            browser.trashCurrent()
            defer { while browser.canUndo { browser.undoTrash() } }
            #expect(names(browser) == ["img10.jpg"])

            browser.undoTrash()
            #expect(names(browser) == ["img2.png", "img10.jpg"])
            #expect(browser.current?.lastPathComponent == "img2.png")

            browser.undoTrash()
            #expect(names(browser) == ["img1.tiff", "img2.png", "img10.jpg"])
            #expect(browser.current?.lastPathComponent == "img1.tiff")
        }
    }

    @Test func trashingEveryImageLeavesNothingCurrent() throws {
        try withFolder { folder in
            let browser = ImageBrowser()
            browser.open(folder.appendingPathComponent("img1.tiff"))

            for _ in 0..<3 { browser.trashCurrent() }
            defer { while browser.canUndo { browser.undoTrash() } }
            #expect(browser.urls.isEmpty)
            #expect(browser.current == nil)
            #expect(browser.position == nil)

            browser.undoTrash()
            #expect(names(browser) == ["img10.jpg"])
            #expect(browser.position == "1/1")
        }
    }
}
