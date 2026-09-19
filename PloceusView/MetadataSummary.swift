//
//  MetadataSummary.swift
//  PloceusView
//

import CoreGraphics
import Foundation
import ImageIO

extension MetadataGroup {
    /// The fields a photographer looks for first, gathered from wherever in
    /// the file they happen to live and written the way they would be spoken.
    ///
    /// This duplicates values that also appear in the raw groups below it.
    /// That is the point: the raw groups stay a faithful record of the file,
    /// while this one answers the usual questions without a hunt.
    static func summary(from properties: [CFString: Any]) -> MetadataGroup? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        var fields: [Field] = []

        func add(_ name: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            fields.append(Field(name: name, value: value))
        }

        func number(_ dictionary: [CFString: Any], _ key: CFString) -> Double? {
            (dictionary[key] as? NSNumber)?.doubleValue
        }

        // Camera and lens, as one line each rather than the make/model split
        // the file stores.
        let make = tiff[kCGImagePropertyTIFFMake] as? String
        let model = tiff[kCGImagePropertyTIFFModel] as? String
        if let model {
            // Canon writes "Canon EOS 60D" in the model, so the make would
            // otherwise be said twice.
            if let make, !model.hasPrefix(make) {
                add("Camera", "\(make) \(model)")
            } else {
                add("Camera", model)
            }
        } else {
            add("Camera", make)
        }

        add("Lens", (aux["LensModel" as CFString] as? String)
            ?? (exif["LensModel" as CFString] as? String))

        add("Focal length", number(exif, kCGImagePropertyExifFocalLength)
            .flatMap(MetadataFormat.focalLength))
        add("Aperture", number(exif, kCGImagePropertyExifFNumber)
            .flatMap(MetadataFormat.fNumber))
        add("Shutter", number(exif, kCGImagePropertyExifExposureTime)
            .flatMap(MetadataFormat.exposureTime))
        add("ISO", isoSpeed(exif).flatMap(MetadataFormat.iso))
        add("Exposure bias", number(exif, kCGImagePropertyExifExposureBiasValue)
            .flatMap(MetadataFormat.exposureBias))
        add("Exposure program", number(exif, kCGImagePropertyExifExposureProgram)
            .flatMap { MetadataFormat.enumeration("ExposureProgram", $0) })
        add("Metering", number(exif, kCGImagePropertyExifMeteringMode)
            .flatMap { MetadataFormat.enumeration("MeteringMode", $0) })
        add("Flash", number(exif, kCGImagePropertyExifFlash)
            .flatMap { MetadataFormat.enumeration("Flash", $0) })

        add("Taken", (exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            .flatMap(MetadataFormat.date))

        // Dimensions come from the top level, which reports the image as
        // decoded rather than as the camera wrote it.
        if let width = number(properties, kCGImagePropertyPixelWidth),
           let height = number(properties, kCGImagePropertyPixelHeight), width > 0 {
            add("Dimensions", "\(Int(width)) × \(Int(height))")
        }

        add("Location", coordinate(gps))
        add("Software", tiff[kCGImagePropertyTIFFSoftware] as? String)
        add("Artist", tiff[kCGImagePropertyTIFFArtist] as? String)
        add("Copyright", tiff[kCGImagePropertyTIFFCopyright] as? String)

        guard !fields.isEmpty else { return nil }
        return MetadataGroup(name: "Photo", fields: fields)
    }

    /// ISO, which EXIF may store as a single number or a list of them.
    private static func isoSpeed(_ exif: [CFString: Any]) -> Double? {
        let raw = exif[kCGImagePropertyExifISOSpeedRatings]
        if let number = raw as? NSNumber { return number.doubleValue }
        if let array = raw as? [NSNumber] { return array.first?.doubleValue }
        return nil
    }

    /// Latitude and longitude, signed by their hemisphere references.
    private static func coordinate(_ gps: [CFString: Any]) -> String? {
        guard let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue
        else { return nil }
        let north = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        let east = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
        let signedLatitude = north == "S" ? -latitude : latitude
        let signedLongitude = east == "W" ? -longitude : longitude
        return String(format: "%.5f, %.5f", signedLatitude, signedLongitude)
    }
}
