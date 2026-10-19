//
//  MetadataFormatTests.swift
//  WarblerEyeTests
//

import Testing
@testable import WarblerEye

struct MetadataFormatTests {

    @Test(arguments: [
        ("2024:05:17 14:30:05", "2024-05-17 14:30:05"),
        ("2024:05:17", "2024-05-17"),
    ])
    func date(_ raw: String, _ expected: String) {
        #expect(MetadataFormat.date(raw) == expected)
    }

    @Test(arguments: ["", "May 17", "2024-05-17 14:30:05"])
    func dateRejectsOtherFormats(_ raw: String) {
        #expect(MetadataFormat.date(raw) == nil)
    }

    @Test(arguments: [
        (0.004, "1/250 s"),
        (1.0 / 3, "1/3 s"),
        (1.0, "1 s"),
        (2.5, "2.5 s"),
        (30.0, "30 s"),
    ])
    func exposureTime(_ seconds: Double, _ expected: String) {
        #expect(MetadataFormat.exposureTime(seconds) == expected)
    }

    @Test func nonPositiveValuesHaveNoReading() {
        #expect(MetadataFormat.exposureTime(0) == nil)
        #expect(MetadataFormat.fNumber(0) == nil)
        #expect(MetadataFormat.focalLength(-1) == nil)
        #expect(MetadataFormat.iso(0) == nil)
    }

    @Test(arguments: [
        (5.656854, "f/5.7"),
        (8.0, "f/8"),
        (1.4, "f/1.4"),
    ])
    func fNumber(_ value: Double, _ expected: String) {
        #expect(MetadataFormat.fNumber(value) == expected)
    }

    @Test func focalLengthAndISO() {
        #expect(MetadataFormat.focalLength(400) == "400 mm")
        #expect(MetadataFormat.focalLength(4.25) == "4.25 mm")
        #expect(MetadataFormat.iso(1600) == "ISO 1600")
    }

    private static let biases: [(Double, String)] = [
        (0.0, "0 EV"),
        (0.00001, "0 EV"),
        (0.05, "0 EV"),
        (1.0 / 3, "+⅓ EV"),
        (-2.0 / 3, "−⅔ EV"),
        (0.5, "+½ EV"),
        (1.0, "+1 EV"),
        (-2.0, "−2 EV"),
        (4.0 / 3, "+1⅓ EV"),
        (-5.0 / 3, "−1⅔ EV"),
        (0.95, "+1 EV"),
        (1.95, "+2 EV"),
    ]

    @Test(arguments: biases)
    func exposureBias(_ ev: Double, _ expected: String) {
        #expect(MetadataFormat.exposureBias(ev) == expected)
    }

    @Test func apexValues() {
        #expect(MetadataFormat.apertureValue(5) == "f/5.7")
        #expect(MetadataFormat.apertureValue(6) == "f/8")
        #expect(MetadataFormat.shutterSpeedValue(8) == "1/256 s")
        #expect(MetadataFormat.shutterSpeedValue(-1) == "2 s")
    }

    @Test func version() {
        #expect(MetadataFormat.version([2, 3, 2]) == "2.3.2")
        #expect(MetadataFormat.version([1, 0]) == "1.0")
        #expect(MetadataFormat.version([]) == nil)
    }

    @Test(arguments: [
        ([100.0, 400, 4.5, 5.6], "100–400 mm f/4.5–5.6"),
        ([50.0, 50, 1.8, 1.8], "50 mm f/1.8"),
        ([24.0, 70, 0, 0], "24–70 mm"),
        ([24.0, 70], "24–70 mm"),
    ])
    func lensSpecification(_ values: [Double], _ expected: String) {
        #expect(MetadataFormat.lensSpecification(values) == expected)
    }

    @Test func lensSpecificationNeedsAFocalRange() {
        #expect(MetadataFormat.lensSpecification([24]) == nil)
        #expect(MetadataFormat.lensSpecification([0, 0, 0, 0]) == nil)
    }

    @Test(arguments: [
        (3.0, "3"),
        (-2.0, "-2"),
        (0.25, "0.25"),
        (1e20, "1e+20"),
    ])
    func trim(_ value: Double, _ expected: String) {
        #expect(MetadataFormat.trim(value) == expected)
    }

    @Test func enumeration() {
        #expect(MetadataFormat.enumeration("MeteringMode", 5) == "Multi-segment")
        #expect(MetadataFormat.enumeration("Orientation", 6) == "Rotated 90° CW")
        #expect(MetadataFormat.enumeration("ColorSpace", 65535) == "Uncalibrated")
        #expect(MetadataFormat.enumeration("FocalPlaneResolutionUnit", 3) == "Centimetres")
    }

    @Test func enumerationOfUnknownTagOrValue() {
        #expect(MetadataFormat.enumeration("MeteringMode", 42) == nil)
        #expect(MetadataFormat.enumeration("NotATag", 1) == nil)
    }

    @Test(arguments: [
        (0, "Did not fire"),
        (1, "Fired"),
        (0x0F, "Fired, compulsory, return detected"),
        (0x10, "Did not fire, suppressed"),
        (0x19, "Fired, auto"),
        (0x20, "Did not fire, no flash function"),
        (0x5F, "Fired, auto, red-eye reduction, return detected"),
    ])
    func flash(_ value: Int, _ expected: String) {
        #expect(MetadataFormat.enumeration("Flash", Double(value)) == expected)
    }

    @Test func flashRejectsNegativeValues() {
        #expect(MetadataFormat.enumeration("Flash", -1) == nil)
    }
}
