import XCTest
@testable import CropTrimmerCore

final class LoopPaletteTests: XCTestCase {
    func testThirtySixDistinctNamedColors() {
        XCTAssertEqual(LoopPalette.count, 36)
        let colors = (0..<LoopPalette.count).map { index -> String in
            let c = LoopPalette.hsb(index)
            return String(format: "%.3f %.3f %.3f", c.hue, c.saturation, c.brightness)
        }
        XCTAssertEqual(Set(colors).count, 36)
        XCTAssertEqual(Set((0..<LoopPalette.count).map(LoopPalette.name)).count, 36)
        XCTAssertEqual(LoopPalette.name(0), "Red")
        XCTAssertEqual(LoopPalette.name(12 + 9), "Deep Violet")
        XCTAssertFalse(LoopPalette.isValid(36)); XCTAssertFalse(LoopPalette.isValid(-1))
    }

    func testRandomColorAvoidsHuesAlreadyInUse() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let used = [0, 13, 26]  // red, deep orange, pale yellow
            let pick = LoopPalette.randomIndex(avoiding: used, using: &generator)
            XCTAssertFalse([0, 1, 2].contains(LoopPalette.hue(of: pick)))
        }
        let everyHue = Array(0..<12)
        let pick = LoopPalette.randomIndex(avoiding: everyHue, using: &generator)
        XCTAssertFalse(everyHue.contains(pick), "With every hue taken it still picks an unused color")
    }

    func testLoopsGetDistinctHuesAndKeepTheirColorThroughEdits() throws {
        var loops = MovieLoops(sourceDuration: 60, colorIndex: 4)
        let first = try XCTUnwrap(loops.selectedID)
        XCTAssertEqual(loops.selected?.colorIndex, 4)
        XCTAssertTrue(loops.add(length: 5)); XCTAssertTrue(loops.add(length: 5))
        XCTAssertEqual(Set(loops.ranges.map { LoopPalette.hue(of: $0.colorIndex) }).count, 3)
        XCTAssertTrue(loops.add(length: 5) == false)
        XCTAssertTrue(loops.select(first))
        XCTAssertTrue(loops.move(first, originalStart: 0, originalEnd: 5, by: 20))
        XCTAssertTrue(loops.updateSelected(start: 21, end: 24))
        XCTAssertEqual(loops.selected?.colorIndex, 4, "Moving and resizing keep the color")
        XCTAssertTrue(loops.setColor(first, to: 30))
        XCTAssertEqual(loops.selected?.colorIndex, 30)
        XCTAssertFalse(loops.setColor(first, to: 36))
        XCTAssertFalse(loops.setColor(UUID(), to: 1))
        XCTAssertEqual(loops.selected?.colorIndex, 30)
    }
}
