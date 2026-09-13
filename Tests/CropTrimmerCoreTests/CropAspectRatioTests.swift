import XCTest
@testable import CropTrimmerCore

final class CropAspectRatioTests: XCTestCase {
    private func check(_ rect: PixelRect, _ ratio: Double, width: Int = 1920, height: Int = 1080, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect, rect.constrained(toWidth: width, height: height), file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Double(rect.width) - ratio * Double(rect.height)), 1 + ratio + 0.0001, file: file, line: line)
    }

    func testPresetFitAndAllCornerDragsStayLockedAndAnchored() throws {
        for aspect in CropAspectRatio.allCases where aspect != .free {
            let ratio = try XCTUnwrap(aspect.value(sourceWidth: 1920, sourceHeight: 1080))
            let original = CropGeometry.fitted(PixelRect(x: 200, y: 200, width: 800, height: 600), aspect: aspect, sourceWidth: 1920, sourceHeight: 1080)
            check(original, ratio)
            for corner in 0..<4 {
                for (dx, dy) in [(101, -51), (-3000, -3000), (3000, 3000), (0, 0)] {
                    let resized = CropGeometry.resized(original, aspect: aspect, corner: corner, dx: dx, dy: dy, sourceWidth: 1920, sourceHeight: 1080)
                    check(resized, ratio)
                    XCTAssertEqual(corner % 2 == 0 ? resized.x + resized.width : resized.x, corner % 2 == 0 ? original.x + original.width : original.x)
                    XCTAssertEqual(corner < 2 ? resized.y + resized.height : resized.y, corner < 2 ? original.y + original.height : original.y)
                    if dx == 0 && dy == 0 { XCTAssertEqual(resized, original) }
                }
            }
        }
    }

    func testNumericDimensionsAndResetHonorRatio() throws {
        let square = CropGeometry.fitted(PixelRect(width: 1920, height: 1080), aspect: .square, sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(square, PixelRect(x: 420, width: 1080, height: 1080))
        let widthEdit = CropGeometry.dimension(square, width: 600, aspect: .square, sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(widthEdit.width, 600); XCTAssertEqual(widthEdit.height, 600)
        let heightEdit = CropGeometry.dimension(widthEdit, height: 800, aspect: .widescreen, sourceWidth: 1920, sourceHeight: 1080)
        check(heightEdit, 16.0 / 9)
        let bounded = CropGeometry.dimension(widthEdit, width: 5000, aspect: .portrait, sourceWidth: 1920, sourceHeight: 1080)
        check(bounded, 9.0 / 16)
        let portraitSource = CropGeometry.fitted(PixelRect(width: 1080, height: 1920), aspect: .original, sourceWidth: 1080, sourceHeight: 1920)
        XCTAssertEqual(portraitSource, PixelRect(width: 1080, height: 1920))
    }

    func testFreeformAndPerLoopPersistence() throws {
        let rect = PixelRect(x: 20, y: 20, width: 200, height: 100)
        XCTAssertEqual(CropGeometry.fitted(rect, aspect: .free, sourceWidth: 1920, sourceHeight: 1080), rect)
        let resized = CropGeometry.resized(rect, aspect: .free, corner: 3, dx: 40, dy: 0, sourceWidth: 1920, sourceHeight: 1080)
        XCTAssertEqual(resized.width, 240); XCTAssertEqual(resized.height, 100)
        var settings = EditSettings(); settings.cropAspectRatio = .scope
        var loops = MovieLoops(sourceDuration: 30, settings: settings)
        let first = try XCTUnwrap(loops.selectedID)
        loops.add(length: 5)
        XCTAssertEqual(loops.selected?.settings.cropAspectRatio, .scope)
        var second = try XCTUnwrap(loops.selected).settings; second.cropAspectRatio = .square
        loops.updateSelected(settings: second); loops.select(first)
        XCTAssertEqual(loops.selected?.settings.cropAspectRatio, .scope)
        XCTAssertEqual(try JSONDecoder().decode(EditSettings.self, from: JSONEncoder().encode(settings)), settings)
    }
}
