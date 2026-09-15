import AVFoundation
import CoreImage
import CropTrimmerCore

enum ColorPlaybackRenderer {
    static func videoComposition(asset: AVAsset, lut: ColorLUT) -> AVVideoComposition? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let cubeData = cubeData(for: lut)
        return AVVideoComposition(asset: asset) { request in
            guard let output = filteredImage(request.sourceImage, dimension: lut.size, cubeData: cubeData, colorSpace: colorSpace) else {
                request.finish(with: request.sourceImage, context: nil); return
            }
            request.finish(with: output, context: nil)
        }
    }

    static func filteredImage(_ sourceImage: CIImage, lut: ColorLUT) -> CIImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return filteredImage(sourceImage, dimension: lut.size, cubeData: cubeData(for: lut), colorSpace: colorSpace)
    }

    private static func filteredImage(_ sourceImage: CIImage, dimension: Int, cubeData: Data, colorSpace: CGColorSpace) -> CIImage? {
        guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else { return nil }
        filter.setValue(sourceImage, forKey: kCIInputImageKey)
        filter.setValue(dimension, forKey: "inputCubeDimension")
        filter.setValue(cubeData, forKey: "inputCubeData")
        filter.setValue(colorSpace, forKey: "inputColorSpace")
        return filter.outputImage
    }

    private static func cubeData(for lut: ColorLUT) -> Data {
        lut.values.withUnsafeBufferPointer { values -> Data in
            var rgba = [Float](); rgba.reserveCapacity(lut.size * lut.size * lut.size * 4)
            for index in stride(from: 0, to: values.count, by: 3) {
                rgba.append(values[index]); rgba.append(values[index + 1]); rgba.append(values[index + 2]); rgba.append(1)
            }
            return rgba.withUnsafeBytes { Data($0) }
        }
    }
}
