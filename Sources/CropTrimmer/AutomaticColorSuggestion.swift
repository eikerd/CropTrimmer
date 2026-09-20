import AVFoundation
import CoreImage
import CropTrimmerCore
import Foundation
import ImageIO

/// Produces a bounded local color suggestion from one sampled frame. Core Image's
/// auto-adjustment filters provide the target frame; the shared fitter turns the
/// before/after pixels into a global LUT that can be previewed and exported.
enum AutomaticColorSuggestion {
    struct Result: Sendable {
        let fit: ColorFitResult
        let sampleCount: Int
    }

    static func suggest(url: URL, time: Double, sampleSide: Int = 32) async throws -> Result {
        guard url.isFileURL, time.isFinite, time >= 0, (8...128).contains(sampleSide) else {
            throw MediaError.invalid("Choose a valid movie frame for automatic correction.")
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60_000)).image
        let source = CIImage(cgImage: frame)
        let target = try adjustedImage(source)
        return try fit(source: source, target: target, sampleSide: sampleSide)
    }

    /// Encodes the upright representative frame for a reference-conditioned
    /// provider. The image is transient request data and is never added to the
    /// media library.
    static func framePNGData(url: URL, time: Double, maximumSide: CGFloat? = nil, crop: PixelRect? = nil) async throws -> Data {
        guard url.isFileURL, time.isFinite, time >= 0 else {
            throw MediaError.invalid("Choose a valid movie frame for color correction.")
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        // A crop is expressed in source pixels, so the frame has to arrive at full
        // size; the downscale to maximumSide happens after cropping instead.
        if let maximumSide, crop == nil {
            guard maximumSide.isFinite, maximumSide > 0, maximumSide <= 4096 else {
                throw MediaError.invalid("Choose a valid frame size.")
            }
            generator.maximumSize = CGSize(width: maximumSide, height: maximumSide)
        }
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let fullFrame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60_000)).image
        let frame = try crop.map { try cropped(fullFrame, to: $0, maximumSide: maximumSide) } ?? fullFrame
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw MediaError.failed("The representative frame could not be encoded.")
        }
        CGImageDestinationAddImage(destination, frame, nil)
        guard CGImageDestinationFinalize(destination) else { throw MediaError.failed("The representative frame could not be encoded.") }
        let result = Data(data)
        guard result.count <= 16 * 1024 * 1024 else { throw MediaError.failed("The representative frame is too large for a color provider request.") }
        return result
    }

    /// Crops to a region in source pixels, then downscales so the long side is at
    /// most `maximumSide`. Cropping first keeps the requested region's detail.
    private static func cropped(_ image: CGImage, to crop: PixelRect, maximumSide: CGFloat?) throws -> CGImage {
        let region = crop.constrained(toWidth: image.width, height: image.height, even: false)
        let rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
        guard let cut = image.cropping(to: rect) else {
            throw MediaError.failed("The crop region could not be read from this frame.")
        }
        guard let maximumSide, maximumSide > 0,
              CGFloat(max(cut.width, cut.height)) > maximumSide else { return cut }
        let scale = maximumSide / CGFloat(max(cut.width, cut.height))
        let width = max(1, Int((CGFloat(cut.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(cut.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw MediaError.failed("The crop region could not be resized.")
        }
        context.interpolationQuality = .high
        context.draw(cut, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else {
            throw MediaError.failed("The crop region could not be resized.")
        }
        return scaled
    }

    static func suggest(url: URL, time: Double, referenceURL: URL, sampleSide: Int = 32) async throws -> Result {
        guard referenceURL.isFileURL else { throw MediaError.invalid("Choose a local matching reference image.") }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60_000)).image
        let source = CIImage(cgImage: frame)
        guard let target = CIImage(contentsOf: referenceURL), !target.extent.isEmpty else {
            throw MediaError.invalid("The reference image could not be decoded.")
        }
        let sourceAspect = source.extent.width / max(source.extent.height, 1)
        let targetAspect = target.extent.width / max(target.extent.height, 1)
        guard abs(sourceAspect - targetAspect) / max(sourceAspect, targetAspect) < 0.02 else {
            throw MediaError.invalid("A matching reference frame must have the same composition and aspect ratio.")
        }
        return try fit(source: source, target: target, sampleSide: sampleSide)
    }

    private static func fit(source: CIImage, target: CIImage, sampleSide: Int) throws -> Result {
        let samples = try pairedSamples(source: source, target: target, side: sampleSide)
        let fit = try ColorLUTFitter.fit(samples: samples, gridSize: 17)
        return Result(fit: fit, sampleCount: samples.count)
    }

    private static func adjustedImage(_ image: CIImage) throws -> CIImage {
        var adjusted = image
        // The `features` option expects an array of detected feature objects;
        // passing a Boolean causes Core Image to throw an Objective-C exception.
        let filters = image.autoAdjustmentFilters(options: [CIImageAutoAdjustmentOption.enhance: true,
                                                            CIImageAutoAdjustmentOption.redEye: false])
        for filter in filters {
            filter.setValue(adjusted, forKey: kCIInputImageKey)
            adjusted = filter.outputImage ?? adjusted
        }
        guard !adjusted.extent.isEmpty else { throw MediaError.failed("Automatic correction returned no image.") }
        return adjusted.cropped(to: image.extent)
    }

    private static func pairedSamples(source: CIImage, target: CIImage, side: Int) throws -> [ColorSample] {
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        let sourceBytes = try rgbaBytes(context: context, image: source, side: side)
        let targetBytes = try rgbaBytes(context: context, image: target, side: side)
        var samples: [ColorSample] = []
        samples.reserveCapacity(side * side)
        for index in stride(from: 0, to: side * side * 4, by: 4) {
            samples.append(ColorSample(source: SIMD3(Float(sourceBytes[index]) / 255,
                                                      Float(sourceBytes[index + 1]) / 255,
                                                      Float(sourceBytes[index + 2]) / 255),
                                       target: SIMD3(Float(targetBytes[index]) / 255,
                                                     Float(targetBytes[index + 1]) / 255,
                                                     Float(targetBytes[index + 2]) / 255)))
        }
        return samples
    }

    private static func rgbaBytes(context: CIContext, image: CIImage, side: Int) throws -> [UInt8] {
        let extent = image.extent
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(side) / max(extent.width, 1),
                                                             y: CGFloat(side) / max(extent.height, 1)))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        context.render(scaled, toBitmap: &bytes, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side), format: .RGBA8, colorSpace: colorSpace)
        return bytes
    }
}
