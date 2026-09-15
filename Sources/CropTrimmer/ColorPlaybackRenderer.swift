import AVFoundation
import CoreImage
import CropTrimmerCore

enum ColorPlaybackRenderer {
    static func videoComposition(asset: AVAsset, lut: ColorLUT) -> AVVideoComposition? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let cubeData = lut.values.withUnsafeBufferPointer { values -> Data in
            var rgba = [Float](); rgba.reserveCapacity(lut.size * lut.size * lut.size * 4)
            for index in stride(from: 0, to: values.count, by: 3) {
                rgba.append(values[index]); rgba.append(values[index + 1]); rgba.append(values[index + 2]); rgba.append(1)
            }
            return rgba.withUnsafeBytes { Data($0) }
        }
        return AVVideoComposition(asset: asset) { request in
            guard let filter = CIFilter(name: "CIColorCubeWithColorSpace") else {
                request.finish(with: request.sourceImage, context: nil); return
            }
            filter.setValue(lut.size, forKey: "inputCubeDimension")
            filter.setValue(cubeData, forKey: "inputCubeData")
            filter.setValue(colorSpace, forKey: "inputColorSpace")
            guard let output = filter.outputImage else {
                request.finish(with: request.sourceImage, context: nil); return
            }
            request.finish(with: output, context: nil)
        }
    }
}
