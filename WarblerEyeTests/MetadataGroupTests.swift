//
//  MetadataGroupTests.swift
//  WarblerEyeTests
//

import Foundation
import ImageIO
import Testing
@testable import WarblerEye

struct MetadataGroupTests {

    private static let photo: [CFString: Any] = [
        kCGImagePropertyPixelWidth: 8192,
        kCGImagePropertyPixelHeight: 5464,
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFMake: "Canon",
            kCGImagePropertyTIFFModel: "Canon EOS R5",
        ] as [CFString: Any],
        kCGImagePropertyExifAuxDictionary: [
            "LensModel" as CFString: "RF100-500mm F4.5-7.1 L IS USM",
        ] as [CFString: Any],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifFocalLength: 400,
            kCGImagePropertyExifFNumber: 5.6,
            kCGImagePropertyExifExposureTime: 0.002,
            kCGImagePropertyExifISOSpeedRatings: [800],
            kCGImagePropertyExifExposureBiasValue: -1.0 / 3,
            kCGImagePropertyExifExposureProgram: 3,
            kCGImagePropertyExifMeteringMode: 5,
            kCGImagePropertyExifFlash: 16,
            kCGImagePropertyExifDateTimeOriginal: "2024:05:17 14:30:05",
        ] as [CFString: Any],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 51.5,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 0.12,
            kCGImagePropertyGPSLongitudeRef: "W",
        ] as [CFString: Any],
    ]

    private func values(_ group: MetadataGroup?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (group?.fields ?? []).map { ($0.name, $0.value) })
    }

    // MARK: - Summary

    @Test func summaryReadsTheUsualFields() throws {
        let summary = try #require(MetadataGroup.summary(from: Self.photo))
        #expect(summary.name == "Photo")
        #expect(summary.fields.map(\.name) == [
            "Camera", "Lens", "Focal length", "Aperture", "Shutter", "ISO",
            "Exposure bias", "Exposure program", "Metering", "Flash", "Taken",
            "Dimensions", "Location",
        ])
        #expect(summary.fields.map(\.value) == [
            "Canon EOS R5", "RF100-500mm F4.5-7.1 L IS USM", "400 mm", "f/5.6",
            "1/500 s", "ISO 800", "−⅓ EV", "Aperture priority", "Multi-segment",
            "Did not fire, suppressed", "2024-05-17 14:30:05", "8192 × 5464",
            "51.50000, -0.12000",
        ])
    }

    @Test func summaryJoinsMakeAndModelWhenTheModelOmitsTheMake() {
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "NIKON CORPORATION",
                kCGImagePropertyTIFFModel: "NIKON Z 9",
            ] as [CFString: Any],
        ]
        #expect(values(MetadataGroup.summary(from: properties))["Camera"]
            == "NIKON CORPORATION NIKON Z 9")
    }

    @Test func summaryFallsBackToMakeAlone() {
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Canon"] as [CFString: Any],
        ]
        #expect(values(MetadataGroup.summary(from: properties))["Camera"] == "Canon")
    }

    @Test func summaryReadsISOStoredAsASingleNumber() {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifISOSpeedRatings: 3200,
            ] as [CFString: Any],
        ]
        #expect(values(MetadataGroup.summary(from: properties))["ISO"] == "ISO 3200")
    }

    @Test func summarySignsCoordinatesByHemisphere() {
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.86,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 151.21,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
        ]
        #expect(values(MetadataGroup.summary(from: properties))["Location"]
            == "-33.86000, 151.21000")
    }

    @Test func summaryIsAbsentWithoutAnyKnownField() {
        #expect(MetadataGroup.summary(from: [:]) == nil)
        #expect(MetadataGroup.summary(from: [kCGImagePropertyDPIWidth: 72]) == nil)
    }

    // MARK: - Groups

    @Test func groupsAreOrderedSummaryThenImageThenByName() {
        var properties = Self.photo
        properties[kCGImagePropertyJFIFDictionary] = [
            kCGImagePropertyJFIFDensityUnit: 1,
        ] as [CFString: Any]

        let groups = MetadataGroup.groups(from: properties)
        #expect(groups.map(\.name) == ["Photo", "Image", "Exif", "ExifAux", "GPS", "JFIF", "TIFF"])
        #expect(groups.first { $0.name == "JFIF" }?.isNoise == true)
        #expect(groups.first { $0.name == "Exif" }?.isNoise == false)
    }

    @Test func topLevelFieldsAreSortedByName() throws {
        let groups = MetadataGroup.groups(from: [
            kCGImagePropertyPixelWidth: 10,
            kCGImagePropertyDepth: 8,
            kCGImagePropertyColorModel: "RGB",
        ])
        let image = try #require(groups.first { $0.name == "Image" })
        #expect(image.fields.map(\.name) == ["ColorModel", "Depth", "PixelWidth"])
    }

    @Test func emptyNestedGroupsAreDropped() {
        let groups = MetadataGroup.groups(from: [
            kCGImagePropertyIPTCDictionary: [:] as [CFString: Any],
        ])
        #expect(groups.isEmpty)
    }

    @Test func fieldsCarryReadingsAlongsideRawValues() throws {
        let groups = MetadataGroup.groups(from: [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 0.004,
                kCGImagePropertyExifMeteringMode: 5,
                kCGImagePropertyExifMaxApertureValue: 5,
                kCGImagePropertyExifVersion: [2, 3, 2],
                kCGImagePropertyExifDateTimeOriginal: "2024:05:17 14:30:05",
                kCGImagePropertyExifLensModel: "EF50mm f/1.8",
            ] as [CFString: Any],
        ])
        let exif = try #require(groups.first { $0.name == "Exif" })
        let fields = Dictionary(uniqueKeysWithValues: exif.fields.map { ($0.name, $0) })

        #expect(fields["ExposureTime"]?.value == "0.004")
        #expect(fields["ExposureTime"]?.reading == "1/250 s")
        #expect(fields["MeteringMode"]?.value == "5")
        #expect(fields["MeteringMode"]?.reading == "Multi-segment")
        #expect(fields["MaxApertureValue"]?.reading == "f/5.7")
        #expect(fields["ExifVersion"]?.value == "2, 3, 2")
        #expect(fields["ExifVersion"]?.reading == "2.3.2")
        #expect(fields["DateTimeOriginal"]?.reading == "2024-05-17 14:30:05")
        #expect(fields["LensModel"]?.reading == nil)
    }

    @Test func valuesAreDescribedCompactly() throws {
        let groups = MetadataGroup.groups(from: [
            "Bytes" as CFString: Data([1, 2, 3]),
            "Flag" as CFString: kCFBooleanTrue as Any,
            "Whole" as CFString: 72.0,
            "Repeating" as CFString: 1.0 / 3,
            "Nested" as CFString: ["{B}" as CFString: 2, "A" as CFString: "x"] as [CFString: Any],
        ])
        // A non-dictionary value at the top level lands in "Image"; the
        // dictionary becomes its own group.
        let image = try #require(groups.first { $0.name == "Image" })
        let fields = Dictionary(uniqueKeysWithValues: image.fields.map { ($0.name, $0) })
        #expect(fields["Bytes"]?.value == "<3 bytes>")
        #expect(fields["Flag"]?.value == "true")
        #expect(fields["Whole"]?.value == "72")
        #expect(fields["Repeating"]?.value == "0.333333")

        let nested = try #require(groups.first { $0.name == "Nested" })
        #expect(nested.fields.map(\.name) == ["A", "B"])
    }

    @Test func emptyAndLongFieldsSortLastAsNoise() throws {
        let long = String(repeating: "1, ", count: 60)
        let groups = MetadataGroup.groups(from: [
            kCGImagePropertyExifDictionary: [
                "AAA" as CFString: "",
                "BBB" as CFString: long,
                "ZZZ" as CFString: "real",
            ] as [CFString: Any],
        ])
        let exif = try #require(groups.first { $0.name == "Exif" })
        #expect(exif.fields.map(\.name) == ["ZZZ", "AAA", "BBB"])
        #expect(exif.fields.map(\.isNoise) == [false, true, true])
        #expect(exif.fields.allSatisfy { $0.reading == nil })
    }
}
