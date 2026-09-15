import AVFoundation
import CoreImage
import CropTrimmerCore
import Foundation

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
        let filters = image.autoAdjustmentFilters(options: [CIImageAutoAdjustmentOption.enhance: true,
                                                            CIImageAutoAdjustmentOption.redEye: false,
                                                            CIImageAutoAdjustmentOption.features: false])
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
