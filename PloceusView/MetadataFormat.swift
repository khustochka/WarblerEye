//
//  MetadataFormat.swift
//  PloceusView
//

import Foundation
import ImageIO

/// Renders raw EXIF values as a person would write them.
///
/// Nothing here discards information: the formatters annotate the raw value
/// rather than replacing it, so a file's own numbers stay visible in the panel
/// even where an enumeration has a friendlier name.
nonisolated enum MetadataFormat {

    // MARK: - Scalars

    /// EXIF writes timestamps with colons in the date, which reads as a time.
    static func date(_ raw: String) -> String? {
        let parts = raw.split(separator: " ", maxSplits: 1)
        guard let day = parts.first, day.filter({ $0 == ":" }).count == 2 else { return nil }
        let rest = parts.count > 1 ? " \(parts[1])" : ""
        return day.replacingOccurrences(of: ":", with: "-") + rest
    }

    /// Shutter speed as a fraction, which is how it is set and spoken.
    static func exposureTime(_ seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        if seconds >= 1 { return "\(trim(seconds)) s" }
        return "1/\(Int((1 / seconds).rounded())) s"
    }

    /// Apertures are quoted to one decimal place: the stored value is a
    /// rational whose expansion ("5.656854") is precision the lens does not
    /// have.
    static func fNumber(_ value: Double) -> String? {
        guard value > 0 else { return nil }
        return "f/\(trim((value * 10).rounded() / 10))"
    }

    static func focalLength(_ mm: Double) -> String? {
        guard mm > 0 else { return nil }
        return "\(trim(mm)) mm"
    }

    static func iso(_ value: Double) -> String? {
        guard value > 0 else { return nil }
        return "ISO \(trim(value))"
    }

    /// Exposure compensation, with the thirds of a stop cameras actually step
    /// in spelled as fractions rather than repeating decimals.
    static func exposureBias(_ ev: Double) -> String? {
        if abs(ev) < 0.0001 { return "0 EV" }
        let sign = ev > 0 ? "+" : "−"
        let magnitude = abs(ev)
        let whole = Int(magnitude)
        let fraction = magnitude - Double(whole)

        let fractionText: String
        switch fraction {
        case ..<0.0834: fractionText = ""
        case ..<0.2084: fractionText = "⅙"
        case ..<0.2917: fractionText = "¼"
        case ..<0.4167: fractionText = "⅓"
        case ..<0.5834: fractionText = "½"
        case ..<0.7084: fractionText = "⅔"
        case ..<0.7917: fractionText = "¾"
        case ..<0.9167: fractionText = "⅚"
        default: return "\(sign)\(trim(magnitude.rounded())) EV"
        }

        if whole == 0 && fractionText.isEmpty { return "0 EV" }
        if fractionText.isEmpty { return "\(sign)\(whole) EV" }
        if whole == 0 { return "\(sign)\(fractionText) EV" }
        return "\(sign)\(whole)\(fractionText) EV"
    }

    /// APEX aperture: the f-number is 2 to the power of half the value.
    static func apertureValue(_ apex: Double) -> String? {
        let f = pow(2, apex / 2)
        guard f.isFinite, f > 0 else { return nil }
        return "f/\(trim((f * 10).rounded() / 10))"
    }

    /// APEX shutter speed: the exposure time is 2 to the power of minus the value.
    static func shutterSpeedValue(_ apex: Double) -> String? {
        let seconds = pow(2, -apex)
        guard seconds.isFinite, seconds > 0 else { return nil }
        return exposureTime(seconds)
    }

    /// Version tags arrive as digit arrays: [2, 3] is version 2.3.
    static func version(_ parts: [Double], separator: String = ".") -> String? {
        guard !parts.isEmpty else { return nil }
        return parts.map { trim($0) }.joined(separator: separator)
    }

    /// A lens's range, as the four-value EXIF specification records it:
    /// min and max focal length, then min and max aperture.
    static func lensSpecification(_ values: [Double]) -> String? {
        guard values.count >= 2, values[0] > 0, values[1] > 0 else { return nil }
        let range = values[0] == values[1]
            ? "\(trim(values[0])) mm"
            : "\(trim(values[0]))–\(trim(values[1])) mm"
        guard values.count >= 4, values[2] > 0, values[3] > 0 else { return range }
        let apertures = values[2] == values[3]
            ? "f/\(trim(values[2]))"
            : "f/\(trim(values[2]))–\(trim(values[3]))"
        return "\(range) \(apertures)"
    }

    /// Drops the trailing zeros a whole double would otherwise print with.
    static func trim(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%g", value)
    }

    // MARK: - Enumerations

    /// The meaning of an enumerated tag, or nil when the tag is not one or the
    /// value is not a value we know.
    static func enumeration(_ tag: String, _ value: Double) -> String? {
        let key = Int(value)
        switch tag {
        case "Flash":
            return flash(key)
        case "MeteringMode":
            return [0: "Unknown", 1: "Average", 2: "Centre-weighted average",
                    3: "Spot", 4: "Multi-spot", 5: "Multi-segment",
                    6: "Partial", 255: "Other"][key]
        case "ExposureProgram":
            return [0: "Not defined", 1: "Manual", 2: "Program",
                    3: "Aperture priority", 4: "Shutter priority",
                    5: "Creative", 6: "Action", 7: "Portrait",
                    8: "Landscape"][key]
        case "ExposureMode":
            return [0: "Auto", 1: "Manual", 2: "Auto bracket"][key]
        case "WhiteBalance":
            return [0: "Auto", 1: "Manual"][key]
        case "SceneCaptureType":
            return [0: "Standard", 1: "Landscape", 2: "Portrait",
                    3: "Night"][key]
        case "ColorSpace":
            return [1: "sRGB", 2: "Adobe RGB", 65535: "Uncalibrated"][key]
        case "Orientation":
            return [1: "Normal", 2: "Mirrored", 3: "Rotated 180°",
                    4: "Mirrored, rotated 180°", 5: "Mirrored, rotated 90° CCW",
                    6: "Rotated 90° CW", 7: "Mirrored, rotated 90° CW",
                    8: "Rotated 90° CCW"][key]
        case "ResolutionUnit", "FocalPlaneResolutionUnit":
            return [1: "None", 2: "Inches", 3: "Centimetres"][key]
        case "SensitivityType":
            return [0: "Unknown", 1: "Standard output sensitivity",
                    2: "Recommended exposure index", 3: "ISO speed",
                    4: "SOS and REI", 5: "SOS and ISO", 6: "REI and ISO",
                    7: "SOS, REI and ISO"][key]
        case "CustomRendered":
            return [0: "Normal", 1: "Custom"][key]
        case "ContrastValue", "SaturationValue", "SharpnessValue":
            return [0: "Normal", 1: "Low", 2: "High"][key]
        case "ImageStabilization":
            return [0: "Off", 1: "On", 2: "Shot only", 3: "Panning",
                    4: "Dynamic"][key]
        case "FocusMode":
            return [0: "One-shot AF", 1: "AI servo AF", 2: "AI focus AF",
                    3: "Manual focus", 4: "Single", 5: "Continuous",
                    6: "Manual focus"][key]
        case "ContinuousDrive":
            return [0: "Single", 1: "Continuous", 2: "Movie",
                    3: "Continuous, speed priority", 4: "Continuous, low",
                    5: "Continuous, high", 6: "Silent single"][key]
        case "DensityUnit":
            return [0: "None", 1: "Pixels per inch",
                    2: "Pixels per centimetre"][key]
        default:
            return nil
        }
    }

    /// Flash is a bitfield rather than a plain enumeration: bit 0 is whether it
    /// fired, and the rest qualify how.
    private static func flash(_ value: Int) -> String? {
        guard value >= 0 else { return nil }
        if value == 0 { return "Did not fire" }

        var parts = [(value & 1) == 1 ? "Fired" : "Did not fire"]
        switch (value >> 3) & 3 {
        case 1: parts.append("compulsory")
        case 2: parts.append("suppressed")
        case 3: parts.append("auto")
        default: break
        }
        if (value >> 5) & 1 == 1 { parts.append("no flash function") }
        if (value >> 6) & 1 == 1 { parts.append("red-eye reduction") }
        switch (value >> 1) & 3 {
        case 2: parts.append("no return detected")
        case 3: parts.append("return detected")
        default: break
        }
        return parts.joined(separator: ", ")
    }
}
