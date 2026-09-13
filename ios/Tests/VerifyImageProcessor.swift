import Foundation
import CoreGraphics
import ImageIO

@main
struct VerifyImageProcessor {
    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") {
        if actual != expected {
            print("❌ Assertion Failed: \(message)")
            print("  Expected: \(expected)")
            print("  Actual:   \(actual)")
            exit(1)
        }
    }

    /// Creates a test CGImage with specified dimensions and a gradient pattern.
    static func createTestImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!

        // Draw a test gradient
        let colors = [
            CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
            CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1.0)
        ] as CFArray

        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: width, y: height), options: [])

        return ctx.makeImage()!
    }

    static func main() {
        print("Running ImageProcessor.swift validation tests...")

        do {
            // Test 1: Large landscape image (4000 x 3000)
            // Shortest edge is 3000. It must be cropped to 3000x3000 and scaled to 1800x1800.
            let landscapeImage = createTestImage(width: 4000, height: 3000)
            let processedLandscape = try ImageProcessor.process(cgImage: landscapeImage)

            assertEqual(processedLandscape.dimension, 512, "Large photo must scale to photoMaxDimension (512)")
            assertEqual(processedLandscape.thumbDimension, 512, "Thumbnail dimension matches 512")
            assertEqual(processedLandscape.photoData.isEmpty, false, "Photo JPEG data must not be empty")

            // Verify JPEG magic bytes (FF D8 FF)
            let photoHeader = [UInt8](processedLandscape.photoData.prefix(3))
            assertEqual(photoHeader, [0xFF, 0xD8, 0xFF], "Photo output must be valid JPEG binary format")

            // Test 2: Portrait image smaller than 512 (400 x 600)
            // Shortest edge is 400. Since 400 < 512, photo dimension should be exactly 400 (no upscaling).
            let portraitImage = createTestImage(width: 400, height: 600)
            let processedPortrait = try ImageProcessor.process(cgImage: portraitImage)

            assertEqual(processedPortrait.dimension, 400, "Image smaller than 512 should retain shortest dimension (400)")

            // Test 3: End-to-end integration with JournalStorage
            let tempDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".cache/test_image_storage", isDirectory: true)
            try? FileManager.default.removeItem(at: tempDir)

            let storage = JournalStorage(customRootURL: tempDir)
            let media = try storage.saveMedia(
                photoData: processedLandscape.photoData,
                customUUID: "e2e-photo-test"
            )

            assertEqual(media.path.hasSuffix("e2e-photo-test.jpg"), true, "Photo saved with expected filename")
            assertEqual(media.thumbPath == nil, true, "Separate thumbnail is omitted")

            let resolvedPhoto = storage.resolveMedia(relPath: media.path)
            assertEqual(FileManager.default.fileExists(atPath: resolvedPhoto!.path), true, "Saved photo must exist on disk")

            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)

            print("✓ All ImageProcessor tests passed successfully!")
        } catch {
            print("❌ Unexpected error during image processing test: \(error)")
            exit(1)
        }
    }
}
