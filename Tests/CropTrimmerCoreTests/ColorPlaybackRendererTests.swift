import CoreImage
import XCTest
@testable import CropTrimmer
import CropTrimmerCore

final class ColorPlaybackRendererTests: XCTestCase {
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
