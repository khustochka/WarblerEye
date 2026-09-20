//
//  ImageMetadata.swift
//  WarblerEye
//

import CoreGraphics
import Foundation
import ImageIO

/// One group of metadata fields, corresponding to a dictionary ImageIO reports
/// for a file: EXIF, TIFF, GPS, IPTC, and so on.
nonisolated struct MetadataGroup: Identifiable {
    var name: String
    var fields: [Field]

    /// Whether the panel should start this group collapsed. Set for groups
    /// that are bulky or opaque rather than wrong, so they stay reachable.
    var isNoise: Bool = false

    var id: String { name }

    nonisolated struct Field: Identifiable {
        var name: String

        /// The value as the file records it.
        var value: String

        /// What the raw value means, where it is an encoding a person would
        /// not read directly: an enumeration, an APEX logarithm, a bare
        /// number wanting a unit. Shown alongside `value`, never instead.
        var reading: String?

        /// Bulky or empty values, which the panel dims and orders last within
        /// their group.
        var isNoise: Bool = false

        var id: String { name }
    }

    /// Fields whose value is long enough to swamp the panel, such as the 45
    /// autofocus points a Canon body records.
    private static let maximumValueLength = 120

    /// Flattens the property tree into displayable groups.
    ///
    /// Values are rendered as text here rather than kept as `Any`, both so the
    /// result can cross actor boundaries during prefetch and because the panel
    /// only ever shows them as strings.
    static func groups(from properties: [CFString: Any]) -> [MetadataGroup] {
        var groups: [MetadataGroup] = []
        var topLevel: [Field] = []

        for (key, value) in properties {
            let name = label(for: key)
            if let nested = value as? [CFString: Any] {
                let fields = nested
                    .map { field(named: label(for: $0.key), from: $0.value) }
                    .sorted(by: ordering)
                if !fields.isEmpty {
                    groups.append(
                        MetadataGroup(name: name, fields: fields, isNoise: isNoise(group: name))
                    )
                }
            } else {
                topLevel.append(field(named: name, from: value))
            }
        }

        groups.sort { $0.name < $1.name }

        // The ungrouped properties describe the file as a whole, so they read
        // best above the per-format dictionaries rather than sorted among them.
        if !topLevel.isEmpty {
            groups.insert(
                MetadataGroup(name: "Image", fields: topLevel.sorted(by: ordering)),
                at: 0
            )
        }

        // The summary goes above everything, since it answers most questions
        // without the user having to find the tag that holds the answer.
        if let summary = summary(from: properties) {
            groups.insert(summary, at: 0)
        }
        return groups
    }

    /// Empty and bulky fields sort last, so a group opens on its real content.
    private static func ordering(_ a: Field, _ b: Field) -> Bool {
        a.isNoise == b.isNoise ? a.name < b.name : !a.isNoise
    }

    /// Groups that hold camera internals rather than facts about the picture.
    private static func isNoise(group: String) -> Bool {
        group == "PictureStyle" || group == "JFIF"
    }

    /// Builds one field, attaching a reading where the raw value is an
    /// encoding rather than something meant to be read as it stands.
    private static func field(named name: String, from value: Any) -> Field {
        let text = describe(value)
        let long = text.count > maximumValueLength
        return Field(
            name: name,
            value: text,
            reading: long ? nil : reading(for: name, value: value, text: text),
            isNoise: text.isEmpty || long
        )
    }

    /// The human reading of a raw value, or nil when the raw value already is
    /// one.
    private static func reading(for name: String, value: Any, text: String) -> String? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            switch name {
            case "ExposureTime": return MetadataFormat.exposureTime(double)
            // Canon's maker note records apertures as plain f-numbers, while
            // EXIF's own MaxApertureValue below is an APEX logarithm. The two
            // look alike and convert differently.
            case "FNumber", "MaxAperture", "MinAperture": return MetadataFormat.fNumber(double)
            case "FocalLength", "FocalLenIn35mmFilm": return MetadataFormat.focalLength(double)
            case "ISOSpeedRatings", "RecommendedExposureIndex", "StandardOutputSensitivity":
                return MetadataFormat.iso(double)
            case "ExposureBiasValue", "FlashCompensation":
                return MetadataFormat.exposureBias(double)
            case "ApertureValue", "MaxApertureValue":
                return MetadataFormat.apertureValue(double)
            case "ShutterSpeedValue":
                return MetadataFormat.shutterSpeedValue(double)
            default:
                return MetadataFormat.enumeration(name, double)
            }
        }

        if let array = value as? [Any] {
            let numbers = array.compactMap { ($0 as? NSNumber)?.doubleValue }
            guard numbers.count == array.count else { return nil }
            switch name {
            case "ExifVersion", "FlashPixVersion", "JFIFVersion":
                // These spell a version as its digits: [2, 3] is 2.3.
                return MetadataFormat.version(numbers)
            case "LensSpecification", "LensInfo":
                return MetadataFormat.lensSpecification(numbers)
            case "ISOSpeedRatings" where numbers.count == 1:
                return numbers.first.flatMap(MetadataFormat.iso)
            default:
                return nil
            }
        }

        if value is String {
            return MetadataFormat.date(text)
        }
        return nil
    }

    /// Strips the braces ImageIO wraps some dictionary keys in, so "{Exif}"
    /// and "PixelWidth" are presented alike.
    private static func label(for key: CFString) -> String {
        let name = key as String
        guard name.hasPrefix("{"), name.hasSuffix("}") else { return name }
        return String(name.dropFirst().dropLast())
    }

    /// Renders one value as text.
    private static func describe(_ value: Any) -> String {
        switch value {
        case let data as Data:
            // Maker notes and embedded thumbnails run to tens of kilobytes,
            // which would swamp the panel if spelled out byte by byte.
            return "<\(data.count) bytes>"
        case let string as String:
            return string
        case let number as NSNumber:
            return describe(number)
        case let array as [Any]:
            return array.map(describe).joined(separator: ", ")
        case let nested as [CFString: Any]:
            return nested
                .map { "\(label(for: $0.key)): \(describe($0.value))" }
                .sorted()
                .joined(separator: ", ")
        default:
            return String(describing: value)
        }
    }

    /// Numbers, without the trailing ".0" that whole doubles would otherwise
    /// print with, since most EXIF integers arrive as doubles.
    private static func describe(_ number: NSNumber) -> String {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        let double = number.doubleValue
        if double == double.rounded(), abs(double) < 1e15 {
            return String(Int64(double))
        }
        // Long repeating decimals are an artefact of the rational EXIF stores,
        // not precision the camera measured.
        return MetadataFormat.trim((double * 1_000_000).rounded() / 1_000_000)
    }
}
