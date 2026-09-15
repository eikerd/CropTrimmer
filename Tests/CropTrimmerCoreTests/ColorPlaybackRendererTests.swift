import CoreImage
import AVFoundation
import XCTest
@testable import CropTrimmer
import CropTrimmerCore

final class ColorPlaybackRendererTests: XCTestCase {
    func testVideoCompositionChangesRenderedFrame() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: TestTools.ffmpeg))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appendingPathComponent("gray.mp4")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: TestTools.ffmpeg)
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "color=c=0x404040:s=16x16:r=25",
                             "-frames:v", "1", "-c:v", "libx264", "-pix_fmt", "yuv420p", movie.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let asset = AVURLAsset(url: movie)
        let generator = AVAssetImageGenerator(asset: asset)
        let original = try generator.copyCGImage(at: .zero, actualTime: nil)
        let lut = try ColorLUT.compile(settings: ColorSettings(enabled: true, gamma: 2), size: 16)
        generator.videoComposition = try XCTUnwrap(ColorPlaybackRenderer.videoComposition(asset: asset, lut: lut))
        let corrected = try generator.copyCGImage(at: .zero, actualTime: nil)
        func pixel(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 4)
            CIContext().render(CIImage(cgImage: image), toBitmap: &bytes, rowBytes: 4,
                               bounds: CGRect(x: 8, y: 8, width: 1, height: 1), format: .RGBA8,
                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return bytes
        }
        let before = pixel(original), after = pixel(corrected)
        XCTAssertGreaterThan(Int(after[0]), Int(before[0]) + 30)
        XCTAssertEqual(after[0], after[1], accuracy: 2)
        XCTAssertEqual(after[1], after[2], accuracy: 2)
    }

    func testCubeFilterUsesTheVideoFrameAsItsInputImage() throws {
        let source = CIImage(color: CIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let lut = try ColorLUT.compile(settings: ColorSettings(enabled: true, gamma: 2), size: 16)

        let output = try XCTUnwrap(ColorPlaybackRenderer.filteredImage(source, lut: lut))
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        XCTAssertGreaterThan(pixel[0], 100, "Gamma correction should visibly lift a 25% gray frame")
        XCTAssertEqual(pixel[0], pixel[1], accuracy: 1)
        XCTAssertEqual(pixel[1], pixel[2], accuracy: 1)
    }
}
