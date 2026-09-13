#!/usr/bin/env swift
import Foundation
import CoreGraphics
import ImageIO

let photoTargetDimension = 256
let photoQuality: Double = 0.82

func processImage(at sourceURL: URL, destinationURL: URL) throws -> (origWidth: Int, origHeight: Int, newSize: Int) {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
        throw NSError(domain: "ImageMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read image at \(sourceURL.path)"])
    }

    var origW = 0
    var origH = 0
    if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
        origW = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        origH = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    }

    let longest = max(origW, origH)
    let shortest = min(origW, origH)

    var maxPixelSize = photoTargetDimension
    if shortest > 0 && shortest < photoTargetDimension {
        maxPixelSize = longest
    } else if shortest >= photoTargetDimension {
        let needed = (Double(photoTargetDimension) * Double(longest) / Double(shortest)).rounded(.up)
        maxPixelSize = min(Int(needed), longest)
    }

    let decodeOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]

    guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) else {
        throw NSError(domain: "ImageMigration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot decode image"])
    }

    let w = oriented.width
    let h = oriented.height
    let shortestOriented = min(w, h)
    let cropX = (w - shortestOriented) / 2
    let cropY = (h - shortestOriented) / 2
    let cropRect = CGRect(x: cropX, y: cropY, width: shortestOriented, height: shortestOriented)

    guard let cropped = oriented.cropping(to: cropRect) else {
        throw NSError(domain: "ImageMigration", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot crop image to square"])
    }

    let targetSize = photoTargetDimension
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

    guard let ctx = CGContext(
        data: nil,
        width: targetSize,
        height: targetSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        throw NSError(domain: "ImageMigration", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot create CGContext"])
    }

    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

    guard let finalCG = ctx.makeImage() else {
        throw NSError(domain: "ImageMigration", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot generate final CGImage"])
    }

    let destData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(destData as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
        throw NSError(domain: "ImageMigration", code: 6, userInfo: [NSLocalizedDescriptionKey: "Cannot create JPEG destination"])
    }

    let encodeOptions: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: photoQuality
    ]
    CGImageDestinationAddImage(dest, finalCG, encodeOptions as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "ImageMigration", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize JPEG"])
    }

    try (destData as Data).write(to: destinationURL, options: .atomic)
    return (origWidth: origW, origHeight: origH, newSize: destData.length)
}

func main() {
    let args = CommandLine.arguments
    guard args.count > 1 else {
        print("Usage: migrate-media-256 <journal-root-directory>")
        exit(1)
    }

    let rootURL = URL(fileURLWithPath: args[1], isDirectory: true)
    let mediaURL = rootURL.appendingPathComponent("media", isDirectory: true)

    guard FileManager.default.fileExists(atPath: mediaURL.path) else {
        print("Error: media directory not found at \(mediaURL.path)")
        exit(1)
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let backupDirName = "media_backup_\(formatter.string(from: Date()))"
    let backupURL = rootURL.appendingPathComponent(backupDirName, isDirectory: true)

    print("==================================================")
    print("Journal Media 256px Migration")
    print("Target Root: \(rootURL.path)")
    print("Creating safe backup at: \(backupURL.path)")
    print("==================================================")

    do {
        try FileManager.default.copyItem(at: mediaURL, to: backupURL)
        print("✓ Backup completed successfully.")
    } catch {
        print("Error creating backup: \(error)")
        exit(1)
    }

    guard let enumerator = FileManager.default.enumerator(at: mediaURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
        print("Error: unable to enumerate media directory")
        exit(1)
    }

    var processedCount = 0
    var thumbsRemovedCount = 0
    var totalOrigBytes: Int64 = 0
    var totalNewBytes: Int64 = 0

    var filesToProcess: [URL] = []
    for case let fileURL as URL in enumerator {
        if fileURL.pathExtension.lowercased() == "ds_store" { continue }
        filesToProcess.append(fileURL)
    }

    for fileURL in filesToProcess.sorted(by: { $0.path < $1.path }) {
        let name = fileURL.lastPathComponent
        let relPath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")

        let origAttributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let origSize = (origAttributes?[.size] as? NSNumber)?.int64Value ?? 0
        totalOrigBytes += origSize

        if name.hasSuffix(".thumb.jpg") {
            // Remove unreferenced thumbnail
            try? FileManager.default.removeItem(at: fileURL)
            thumbsRemovedCount += 1
            print("🗑️ Removed thumbnail: \(relPath) (\(origSize / 1024) KB)")
            continue
        }

        let ext = fileURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic"].contains(ext) {
            do {
                let (origW, origH, newBytes) = try processImage(at: fileURL, destinationURL: fileURL)
                processedCount += 1
                totalNewBytes += Int64(newBytes)
                let pct = 100 - Int((Double(newBytes) / Double(max(1, origSize))) * 100)
                print("✓ Transformed: \(relPath)")
                print("   Original: \(origW)x\(origH) (\(origSize / 1024) KB) -> 256x256 (\(newBytes / 1024) KB) [-\(pct)%]")
            } catch {
                print("⚠️ Could not process \(relPath): \(error.localizedDescription)")
                totalNewBytes += origSize
            }
        }
    }

    print("==================================================")
    print("Migration Complete!")
    print("Photos converted to 256x256: \(processedCount)")
    print("Old thumbnails removed: \(thumbsRemovedCount)")
    let origMB = Double(totalOrigBytes) / (1024 * 1024)
    let newMB = Double(totalNewBytes) / (1024 * 1024)
    print(String(format: "Total Storage: %.2f MB -> %.2f MB (Saved %.1f%%)", origMB, newMB, (1.0 - newMB / max(0.001, origMB)) * 100))
    print("Original photos safely backed up at: \(backupURL.path)")
    print("==================================================")
}

main()
