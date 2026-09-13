import Foundation
import CoreGraphics
import ImageIO

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Result of processing a raw photograph for storage in Journal.
///
/// One tier: the square JPEG below is the only copy kept. The picked original
/// is never written to disk.
public struct ProcessedImage: Sendable {
    /// The stored square JPEG (256x256 px @ 82% quality).
    public let photoData: Data
    /// The pixel width and height of that square.
    public let dimension: Int

    public init(photoData: Data, dimension: Int) {
        self.photoData = photoData
        self.dimension = dimension
    }
}

public enum ImageProcessorError: LocalizedError {
    case cannotDecodeImage
    case cannotCropImage
    case cannotEncodeJPEG

    public var errorDescription: String? {
        switch self {
        case .cannotDecodeImage:
            return "The image data could not be decoded or is corrupt."
        case .cannotCropImage:
            return "Failed to center-crop the image to a square."
        case .cannotEncodeJPEG:
            return "Failed to compress the processed image to JPEG format."
        }
    }
}

/// Preprocesses, center-crops, scales, and compresses images for Journal storage.
///
/// Matches `mac/src/renderer/app.js`: a 1:1 square centre crop, scaled to 256x256 px
/// and encoded as JPEG at 0.82 quality. If the lower dimension is less than 256, it is
/// enlarged to 256; if larger, it is downscaled. That square is the only copy stored
/// on either platform — the original is not kept.
public struct ImageProcessor {
    public static let photoMaxDimension: Int = 256
    public static let photoQuality: Double = 0.82

    /// Processes raw image data (JPEG, PNG, HEIC, TIFF, WebP, etc.).
    /// Automatically applies EXIF orientation transforms.
    public static func process(rawImageData: Data) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithData(rawImageData as CFData, nil) else {
            throw ImageProcessorError.cannotDecodeImage
        }

        // Decode through the thumbnail API to apply EXIF orientation transforms.
        var maxPixelSize = photoMaxDimension
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? (props[kCGImagePropertyPixelWidth] as? Int),
           let pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? (props[kCGImagePropertyPixelHeight] as? Int),
           pixelWidth > 0, pixelHeight > 0 {
            let longest = max(pixelWidth, pixelHeight)
            let shortest = min(pixelWidth, pixelHeight)

            if shortest < photoMaxDimension {
                // If lower dimension is less than 256, don't downsample during decode;
                // scaleAndCenterCrop will enlarge it to 256.
                maxPixelSize = longest
            } else {
                // If lower dimension is >= 256, downsample so the shorter edge survives
                // at proportionally up to photoMaxDimension (256) pixels.
                let needed = (Double(photoMaxDimension) * Double(longest) / Double(shortest)).rounded(.up)
                maxPixelSize = min(Int(needed), longest)
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let orientedCGImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessorError.cannotDecodeImage
        }

        return try process(cgImage: orientedCGImage)
    }

    /// Processes an existing CGImage into a 256x256 centre-cropped square JPEG.
    public static func process(cgImage: CGImage) throws -> ProcessedImage {
        let photoCG = try scaleAndCenterCrop(
            cgImage: cgImage,
            targetDimension: photoMaxDimension
        )
        let photoJPEG = try encodeToJPEG(cgImage: photoCG, quality: photoQuality)

        return ProcessedImage(
            photoData: photoJPEG,
            dimension: photoCG.width
        )
    }

    // MARK: - CoreGraphics Transformation Pipeline

    private static func scaleAndCenterCrop(
        cgImage: CGImage,
        targetDimension: Int
    ) throws -> CGImage {
        let w = cgImage.width
        let h = cgImage.height
        let shortest = min(w, h)
        guard shortest > 0 else { throw ImageProcessorError.cannotCropImage }

        let sx = (w - shortest) / 2
        let sy = (h - shortest) / 2
        let cropRect = CGRect(x: sx, y: sy, width: shortest, height: shortest)

        guard let cropped = cgImage.cropping(to: cropRect) else {
            throw ImageProcessorError.cannotCropImage
        }

        // Direct crop from center and scale to targetDimension (256px).
        // If lower dimension is less than 256, it enlarges to 256; if larger, it scales down to 256.
        let targetSize = targetDimension

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

        guard let ctx = CGContext(
            data: nil,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: targetSize * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw ImageProcessorError.cannotCropImage
        }

        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

        guard let scaled = ctx.makeImage() else {
            throw ImageProcessorError.cannotCropImage
        }

        return scaled
    }

    private static func encodeToJPEG(cgImage: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        let uti: CFString
        if #available(macOS 11.0, iOS 14.0, *) {
            uti = UTType.jpeg.identifier as CFString
        } else {
            uti = "public.jpeg" as CFString
        }

        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, uti, 1, nil) else {
            throw ImageProcessorError.cannotEncodeJPEG
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.cannotEncodeJPEG
        }

        return data as Data
    }
}
