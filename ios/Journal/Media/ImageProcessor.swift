import Foundation
import CoreGraphics
import ImageIO

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Result of processing a raw photograph for storage in Journal.
public struct ProcessedImage: Sendable {
    /// Full-resolution square photo JPEG data (max 1800x1800 px @ 88% quality).
    public let photoData: Data
    /// Low-latency square thumbnail JPEG data (max 320x320 px @ 82% quality).
    public let thumbData: Data
    /// The pixel width and height of the processed square photo.
    public let dimension: Int
    /// The pixel width and height of the processed thumbnail.
    public let thumbDimension: Int
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
/// Implements exact parity with `mac/src/renderer/app.js:squareCanvas`:
/// - 1:1 square center crop.
/// - Photo: max 1800x1800 px, JPEG 0.88 quality.
/// - Thumbnail: max 320x320 px, JPEG 0.82 quality.
public struct ImageProcessor {
    public static let photoMaxDimension: Int = 1800
    public static let thumbMaxDimension: Int = 320
    public static let photoQuality: Double = 0.88
    public static let thumbQuality: Double = 0.82

    /// Processes raw image data (JPEG, PNG, HEIC, TIFF, WebP, etc.).
    /// Automatically applies EXIF orientation transforms.
    public static func process(rawImageData: Data) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithData(rawImageData as CFData, nil) else {
            throw ImageProcessorError.cannotDecodeImage
        }

        // Apply EXIF orientation automatically
        let options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: false
        ]

        guard let originalCGImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            throw ImageProcessorError.cannotDecodeImage
        }

        return try process(cgImage: originalCGImage)
    }

    /// Processes an existing CGImage directly.
    public static func process(cgImage: CGImage) throws -> ProcessedImage {
        let photoCG = try scaleAndCenterCrop(cgImage: cgImage, maxDimension: photoMaxDimension)
        let thumbCG = try scaleAndCenterCrop(cgImage: cgImage, maxDimension: thumbMaxDimension)

        let photoJPEG = try encodeToJPEG(cgImage: photoCG, quality: photoQuality)
        let thumbJPEG = try encodeToJPEG(cgImage: thumbCG, quality: thumbQuality)

        return ProcessedImage(
            photoData: photoJPEG,
            thumbData: thumbJPEG,
            dimension: photoCG.width,
            thumbDimension: thumbCG.width
        )
    }

    // MARK: - CoreGraphics Transformation Pipeline

    private static func scaleAndCenterCrop(cgImage: CGImage, maxDimension: Int) throws -> CGImage {
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

        let targetSize = min(shortest, maxDimension)
        if targetSize == shortest {
            return cropped
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

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
