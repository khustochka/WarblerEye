//
//  ImageFileTests.swift
//  WarblerEyeTests
//

import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import WarblerEye

/// Reading real files: the status-bar facts and the orientation baked in at
/// decode time.
struct ImageFileTests {

    // MARK: - ImageInfo

    @Test func infoDescribesTheFile() throws {
        try Fixtures.withDirectory { folder in
            let url = folder.appendingPathComponent("photo.tiff")
            try Fixtures.writeImage(to: url, width: 16, height: 8)

            let info = try #require(ImageInfo(url: url))
            #expect(info.dimensions == "16x8")
            #expect(info.format == "TIFF")
            #expect(info.colorModel == "sRGB")
            let size = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            #expect(info.byteCount == size)
            #expect(info.fileSize == "\(size / 1000) kB")
        }
    }

    @Test(arguments: 1...8)
    func infoReportsDimensionsAsDisplayed(_ orientation: UInt32) throws {
        try Fixtures.withDirectory { folder in
            let url = folder.appendingPathComponent("photo.tiff")
            try Fixtures.writeImage(
                to: url, width: 16, height: 8,
                properties: [kCGImagePropertyOrientation: orientation]
            )
            let info = try #require(ImageInfo(url: url))
            #expect(info.dimensions == (orientation >= 5 ? "8x16" : "16x8"))
        }
    }

    @Test func captureTimeReadsBackAsTheCameraWroteIt() throws {
        try Fixtures.withDirectory { folder in
            let url = folder.appendingPathComponent("photo.jpg")
            try Fixtures.writeImage(to: url, type: .jpeg, properties: [
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifDateTimeOriginal: "2024:05:17 14:30:05",
                ] as [CFString: Any],
            ])

            let info = try #require(ImageInfo(url: url))
            #expect(info.format == "JPEG")
            #expect(info.dateIsCaptureTime)
            #expect(info.timestamp == "2024-05-17 14:30:05")
            #expect(info.metadata.first?.name == "Photo")
        }
    }

    @Test func modificationTimeStandsInForAMissingCaptureTime() throws {
        try Fixtures.withDirectory { folder in
            let url = folder.appendingPathComponent("photo.png")
            try Fixtures.writeImage(to: url, type: .png)
            let modified = Date(timeIntervalSince1970: 1_700_000_000)
            try FileManager.default.setAttributes(
                [.modificationDate: modified], ofItemAtPath: url.path
            )

            let info = try #require(ImageInfo(url: url))
            #expect(info.format == "PNG")
            #expect(!info.dateIsCaptureTime)
            #expect(info.date == modified)
        }
    }

    @Test func infoIsAbsentForAFileThatIsNotAnImage() throws {
        try Fixtures.withDirectory { folder in
            let url = folder.appendingPathComponent("notes.txt")
            try Fixtures.writeText(to: url)
            #expect(ImageInfo(url: url) == nil)
            #expect(ImageDecoder.load(url: url) == nil)
        }
    }

    // MARK: - Orientation

    @Test func onlyQuarterTurnsSwapAxes() {
        let swapping = (UInt32(1)...8).filter {
            CGImagePropertyOrientation(rawValue: $0)!.swapsAxes
        }
        #expect(swapping == [5, 6, 7, 8])
    }

    /// Stored quadrants are red, green / blue, white. Each case lists where
    /// they must appear on screen, read the same way, per the EXIF definition
    /// of the tag.
    private static let upright: [(UInt32, [Fixtures.Colour])] = [
        (1, [.red, .green, .blue, .white]),
        (2, [.green, .red, .white, .blue]),
        (3, [.white, .blue, .green, .red]),
        (4, [.blue, .white, .red, .green]),
        (5, [.red, .blue, .green, .white]),
        (6, [.blue, .red, .white, .green]),
        (7, [.white, .green, .blue, .red]),
        (8, [.green, .white, .red, .blue]),
    ]

    @Test(arguments: upright)
    func decodeTurnsTheImageUpright(
        _ orientation: UInt32, _ expected: [Fixtures.Colour]
    ) throws {
        try Fixtures.withDirectory { folder in
            let url = folder.appendingPathComponent("photo.tiff")
            try Fixtures.writeImage(
                to: url, width: 16, height: 8,
                properties: [kCGImagePropertyOrientation: orientation]
            )

            let loaded = try #require(ImageDecoder.load(url: url))
            let size = orientation >= 5 ? CGSize(width: 8, height: 16) : CGSize(width: 16, height: 8)
            #expect(loaded.image.size == size)
            #expect(Fixtures.quadrants(of: loaded.image) == expected)
        }
    }
}
