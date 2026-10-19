//
//  Fixtures.swift
//  WarblerEyeTests
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Image files written to disk on demand, so tests exercise ImageIO's real
/// reading path rather than a stand-in for it.
enum Fixtures {

    /// A colour that survives a round trip through any lossless encoder and
    /// colour-space conversion, because each channel is either off or full.
    struct Colour: Equatable, CustomStringConvertible {
        var r: Bool, g: Bool, b: Bool

        static let red = Colour(r: true, g: false, b: false)
        static let green = Colour(r: false, g: true, b: false)
        static let blue = Colour(r: false, g: false, b: true)
        static let white = Colour(r: true, g: true, b: true)

        var description: String {
            switch self {
            case .red: "red"
            case .green: "green"
            case .blue: "blue"
            case .white: "white"
            default: "(\(r), \(g), \(b))"
            }
        }
    }

    /// A fresh, empty folder inside `base` that is removed when `body` returns.
    static func withDirectory<T>(
        in base: URL = FileManager.default.temporaryDirectory,
        _ body: (URL) throws -> T
    ) throws -> T {
        let url = base
            .appendingPathComponent("WarblerEyeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    /// Writes an image split into four coloured quadrants, listed top-left,
    /// top-right, bottom-left, bottom-right as the pixels are stored.
    static func writeImage(
        to url: URL,
        type: UTType = .tiff,
        width: Int = 16,
        height: Int = 8,
        quadrants: [Colour] = [.red, .green, .blue, .white],
        properties: [CFString: Any] = [:]
    ) throws {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let quadrant = (y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)
                let colour = quadrants[quadrant]
                let offset = (y * width + x) * 4
                bytes[offset] = colour.r ? 255 : 0
                bytes[offset + 1] = colour.g ? 255 : 0
                bytes[offset + 2] = colour.b ? 255 : 0
            }
        }

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Writes a file that is not an image, to check it is passed over.
    static func writeText(to url: URL) throws {
        try Data("not an image".utf8).write(to: url)
    }

    /// The colour at a pixel of `image`, measured from its top-left corner.
    static func colour(of image: NSImage, x: Int, y: Int) -> Colour? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // A bitmap context's memory runs from the top row down.
        let offset = (y * width + x) * 4
        return Colour(r: bytes[offset] > 127, g: bytes[offset + 1] > 127, b: bytes[offset + 2] > 127)
    }

    /// The colour at the centre of each quadrant, in the same order as
    /// `writeImage(quadrants:)` takes them.
    static func quadrants(of image: NSImage) -> [Colour?] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return [] }
        let xs = [cgImage.width / 4, cgImage.width * 3 / 4]
        let ys = [cgImage.height / 4, cgImage.height * 3 / 4]
        return ys.flatMap { y in xs.map { x in colour(of: image, x: x, y: y) } }
    }
}
