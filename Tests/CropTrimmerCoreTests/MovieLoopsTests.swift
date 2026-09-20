import XCTest
@testable import CropTrimmerCore

final class MovieLoopsTests: XCTestCase {
    func testQueueSettingsStayIndependentThroughMovesAndRemoval() throws {
        var initial = EditSettings(); initial.crop = PixelRect(width: 640, height: 360)
        var loops = MovieLoops(sourceDuration: 30, settings: initial)
        let first = try XCTUnwrap(loops.selectedID)
        var edited = try XCTUnwrap(loops.selected).settings
        edited.cropEnabled = true; edited.crop = PixelRect(x: 20, y: 10, width: 200, height: 100)
        edited.method = .accurate; edited.quality = .high
        XCTAssertTrue(loops.updateSelected(settings: edited))
        loops.add(length: 10)
        let second = try XCTUnwrap(loops.selectedID)
        XCTAssertEqual(loops.selected?.settings.crop, edited.crop)
        var secondEdit = try XCTUnwrap(loops.selected).settings
        secondEdit.cropEnabled = false; secondEdit.quality = .smaller
        loops.updateSelected(settings: secondEdit)
        loops.move(second, originalStart: 5, originalEnd: 15, by: 3)
        XCTAssertEqual(loops.selected?.settings.quality, .smaller)
        loops.select(first)
        XCTAssertEqual(loops.selected?.settings, edited)
        loops.removeSelected()
        XCTAssertEqual(loops.selectedID, second)
        XCTAssertEqual(loops.selected?.settings.quality, .smaller)
        XCTAssertEqual(loops.selected?.start, 8)
    }

    func testDefaultsAndShortMovies() {
        XCTAssertEqual(MovieLoops(sourceDuration: 30).selected?.duration, 5)
        XCTAssertEqual(MovieLoops(sourceDuration: 30, defaultLength: 10).selected?.duration, 10)
        XCTAssertEqual(MovieLoops(sourceDuration: 3).selected?.duration, 3)
        XCTAssertTrue(MovieLoops().ranges.isEmpty)
        XCTAssertTrue(MovieLoops(sourceDuration: .infinity).ranges.isEmpty)
    }

    func testThreeIndependentLoopsSurviveSelectionAndEdits() throws {
        var loops = MovieLoops(sourceDuration: 30)
        let first = try XCTUnwrap(loops.selectedID)
        XCTAssertTrue(loops.add(length: 5))
        let second = try XCTUnwrap(loops.selectedID)
        XCTAssertEqual(loops.selected?.start, 5)
        XCTAssertTrue(loops.add(length: 10))
        let third = try XCTUnwrap(loops.selectedID)
        XCTAssertEqual(loops.selected?.start, 10)
        XCTAssertTrue(loops.select(second))
        XCTAssertTrue(loops.updateSelected(start: 6.123456789, end: 12.456789123))
        XCTAssertTrue(loops.select(first))
        XCTAssertEqual(loops.selected?.start, 0)
        XCTAssertEqual(loops.selected?.end, 5)
        XCTAssertTrue(loops.select(third))
        XCTAssertEqual(loops.selected?.end, 20)
        XCTAssertTrue(loops.select(second))
        XCTAssertEqual(try XCTUnwrap(loops.selected).start, 6.123456789, accuracy: 0.000000001)
        XCTAssertEqual(loops.ranges.count, 3)
    }

    func testMovingEntireRangePreservesLengthAndClampsBothEnds() throws {
        var loops = MovieLoops(sourceDuration: 30)
        let id = try XCTUnwrap(loops.selectedID)
        XCTAssertTrue(loops.updateSelected(start: 3.123456789, end: 8.123456789))
        let original = try XCTUnwrap(loops.selected)
        XCTAssertTrue(loops.move(id, originalStart: original.start, originalEnd: original.end, by: 100))
        // Pushed past the end, the loop shortens to the movie's end instead of keeping its length.
        XCTAssertEqual(try XCTUnwrap(loops.selected).start, 30 - MovieLoops.minimumLength, accuracy: 0.000000001)
        XCTAssertEqual(loops.selected?.end, 30)
        XCTAssertTrue(loops.move(id, originalStart: original.start, originalEnd: original.end, by: 24))
        XCTAssertEqual(try XCTUnwrap(loops.selected).start, 27.123456789, accuracy: 0.000000001)
        XCTAssertEqual(loops.selected?.end, 30)
        XCTAssertTrue(loops.move(id, originalStart: original.start, originalEnd: original.end, by: -100))
        XCTAssertEqual(loops.selected?.start, 0)
        XCTAssertEqual(loops.selected?.end, 5)
        XCTAssertTrue(loops.move(id, originalStart: original.start, originalEnd: original.end, by: 1.234))
        XCTAssertEqual(try XCTUnwrap(loops.selected).start, 4.357456789, accuracy: 0.000000001)
        XCTAssertEqual(try XCTUnwrap(loops.selected).duration, 5, accuracy: 0.000000001)
    }

    func testPresetsNearEndAndRemoval() throws {
        var loops = MovieLoops(sourceDuration: 12)
        XCTAssertTrue(loops.updateSelected(start: 9, end: 12))
        XCTAssertTrue(loops.resizeSelected(to: 10))
        XCTAssertEqual(loops.selected?.start, 2)
        XCTAssertEqual(loops.selected?.end, 12)
        XCTAssertTrue(loops.add(length: 5))
        let old = try XCTUnwrap(loops.selectedID)
        XCTAssertTrue(loops.removeSelected())
        XCTAssertNotEqual(loops.selectedID, old)
        XCTAssertEqual(loops.ranges.count, 1)
    }

    func testOverlappingDefaultsRemainDistinctWhenSourceIsShort() {
        var loops = MovieLoops(sourceDuration: 8)
        loops.add(length: 5); loops.add(length: 5)
        XCTAssertEqual(Set(loops.ranges.map(\.start)).count, 3)
        XCTAssertTrue(loops.ranges.allSatisfy { $0.start >= 0 && $0.end <= 8 })
        // The second loop starts at the first one's out point and runs to the end of the movie.
        XCTAssertEqual(loops.ranges[1].start, 5); XCTAssertEqual(loops.ranges[1].end, 8)
    }

    func testRemovingAnUnselectedLoopKeepsTheSelection() throws {
        var loops = MovieLoops(sourceDuration: 60)
        let first = try XCTUnwrap(loops.selectedID)
        XCTAssertTrue(loops.add(length: 5)); let second = try XCTUnwrap(loops.selectedID)
        XCTAssertTrue(loops.add(length: 5)); let third = try XCTUnwrap(loops.selectedID)
        XCTAssertTrue(loops.select(first))
        XCTAssertTrue(loops.remove(third))
        XCTAssertEqual(loops.selectedID, first)
        XCTAssertEqual(loops.ranges.map(\.id), [first, second])
        XCTAssertTrue(loops.remove(first))
        XCTAssertEqual(loops.selectedID, second, "Removing the selected loop selects its neighbour")
        XCTAssertTrue(loops.remove(second), "The last loop can go too, back to the bare movie")
        XCTAssertTrue(loops.ranges.isEmpty); XCTAssertNil(loops.selectedID)
        XCTAssertFalse(loops.remove(UUID()))
    }

    func testAddChainsEvenAShortRemainderAndFallsBackOnlyAtTheEnd() throws {
        var loops = MovieLoops(sourceDuration: 60)
        XCTAssertTrue(loops.updateSelected(start: 50, end: 59.95))
        XCTAssertTrue(loops.add(length: 5))
        XCTAssertEqual(try XCTUnwrap(loops.selected).start, 59.95, accuracy: 0.000000001)
        XCTAssertEqual(loops.selected?.end, 60)
        XCTAssertTrue(loops.add(length: 5))
        XCTAssertNotEqual(loops.selected?.start, 60, "B at the movie's end cannot chain; the loop takes an unused spot")
        XCTAssertEqual(loops.selected?.duration, 5)
    }

    func testAddChainsFromTheSelectedOutPoint() throws {
        var loops = MovieLoops(sourceDuration: 60)
        XCTAssertTrue(loops.updateSelected(start: 2, end: 9.5))
        XCTAssertTrue(loops.add(length: 5))
        XCTAssertEqual(loops.selected?.start, 9.5); XCTAssertEqual(loops.selected?.end, 14.5)
        XCTAssertTrue(loops.add(length: 5))
        XCTAssertEqual(loops.selected?.start, 14.5); XCTAssertEqual(loops.selected?.end, 19.5)
    }

    func testInvalidUpdatesLeaveRangesUnchanged() throws {
        var loops = MovieLoops(sourceDuration: 8)
        let initial = loops
        let id = try XCTUnwrap(loops.selectedID)
        XCTAssertFalse(loops.updateSelected(start: .nan, end: 4))
        XCTAssertFalse(loops.updateSelected(start: 5, end: 4))
        XCTAssertFalse(loops.move(id, originalStart: 0, originalEnd: 5, by: .infinity))
        XCTAssertFalse(loops.select(UUID()))
        XCTAssertEqual(loops, initial)
    }

    func testAMovieOpensWithNoLoopsAndTheFirstAddStartsAtThePlayhead() throws {
        var loops = MovieLoops(sourceDuration: 60, withFirstLoop: false)
        XCTAssertTrue(loops.ranges.isEmpty); XCTAssertNil(loops.selectedID)
        XCTAssertTrue(loops.add(length: 5, at: 12.25))
        XCTAssertEqual(loops.selected?.start, 12.25); XCTAssertEqual(loops.selected?.end, 17.25)
        // Later loops stair-step from the previous B; the playhead no longer matters.
        XCTAssertTrue(loops.add(length: 5, at: 40))
        XCTAssertEqual(loops.selected?.start, 17.25); XCTAssertEqual(loops.selected?.end, 22.25)
    }

    func testTheFirstLoopIsKeptInsideTheMovie() throws {
        var nearEnd = MovieLoops(sourceDuration: 60, withFirstLoop: false)
        XCTAssertTrue(nearEnd.add(length: 5, at: 58))
        XCTAssertEqual(nearEnd.selected?.start, 58); XCTAssertEqual(nearEnd.selected?.end, 60)
        var atEnd = MovieLoops(sourceDuration: 60, withFirstLoop: false)
        XCTAssertTrue(atEnd.add(length: 5, at: 60))
        XCTAssertEqual(try XCTUnwrap(atEnd.selected).start, 60 - MovieLoops.minimumLength, accuracy: 0.000000001)
        XCTAssertEqual(atEnd.selected?.end, 60)
        var wild = MovieLoops(sourceDuration: 60, withFirstLoop: false)
        XCTAssertTrue(wild.add(length: 5, at: -.infinity))
        XCTAssertEqual(wild.selected?.start, 0)
    }

    func testLoopsAreNotCapped() throws {
        var loops = MovieLoops(sourceDuration: 600, withFirstLoop: false)
        for _ in 0..<16 { XCTAssertTrue(loops.add(length: 5, at: 0)) }
        XCTAssertEqual(loops.ranges.count, 16)
        XCTAssertEqual(loops.ranges.map { $0.start }, (0..<16).map { Double($0) * 5 })
    }
}
