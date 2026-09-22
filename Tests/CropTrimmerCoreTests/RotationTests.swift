import XCTest
@testable import CropTrimmerCore

final class RotationTests: XCTestCase {
    private var url: URL!
    private var source: MediaSource!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("fixture".utf8).write(to: url)
        source = MediaSource(url: url, identity: try SourceIdentity(url: url), duration: 30, width: 1920, height: 1080, encodedWidth: 1920, encodedHeight: 1080, rotation: 0, fps: 25, videoCodec: "h264", audioCount: 1, subtitleCount: 0, format: "mp4")
    }
    override func tearDownWithError() throws { if let url { try? FileManager.default.removeItem(at: url) } }

    func testRotateButtonCyclesQuarterTurnsBackToUpright() {
        var edit = EditSettings(source: source)
        var seen: [Int] = []
        for _ in EditSettings.rotations { seen.append(edit.rotation); edit = edit.turnedClockwise(source: source) }
        XCTAssertEqual(seen, [0, 90, 180, 270])
        XCTAssertEqual(edit.rotation, 0)
    }

    func testQuarterTurnsSwapThePictureSize() {
        var edit = EditSettings(source: source)
        for (rotation, width, height) in [(0, 1920, 1080), (90, 1080, 1920), (180, 1920, 1080), (270, 1080, 1920)] {
            edit.rotation = rotation
            let size = edit.pictureSize(of: source)
            XCTAssertEqual(size.width, width, "rotation \(rotation)"); XCTAssertEqual(size.height, height, "rotation \(rotation)")
        }
    }

    func testCropTurnsWithThePictureAndFourTurnsRestoreIt() throws {
        var edit = EditSettings(source: source)
        edit.cropEnabled = true
        edit.crop = PixelRect(x: 100, y: 40, width: 640, height: 360)
        let original = edit
        edit = edit.turnedClockwise(source: source)
        // A clockwise quarter turn sends the picture's top-left corner to the top-right: (x, y) lands at (1080 - y, x).
        XCTAssertEqual(edit.crop, PixelRect(x: 1080 - 40 - 360, y: 100, width: 360, height: 640))
        XCTAssertNoThrow(try edit.validate(source: source))
        for _ in 0..<3 {
            edit = edit.turnedClockwise(source: source)
            XCTAssertNoThrow(try edit.validate(source: source))
        }
        XCTAssertEqual(edit, original, "Cycling the button must not wear the crop down")
    }

    func testTheDefaultWholeFrameCropStaysWholeThroughEveryTurn() throws {
        var edit = EditSettings(source: source)
        for _ in 0..<4 {
            edit = edit.turnedClockwise(source: source)
            let size = edit.pictureSize(of: source)
            XCTAssertEqual(edit.crop, PixelRect(width: size.width, height: size.height), "rotation \(edit.rotation)")
        }
    }

    func testCropIsMeasuredOnTheTurnedPicture() throws {
        var edit = EditSettings(source: source)
        edit.rotation = 90; edit.cropEnabled = true
        edit.crop = PixelRect(x: 0, y: 0, width: 1080, height: 1920)
        XCTAssertNoThrow(try edit.validate(source: source))
        edit.rotation = 0
        XCTAssertThrowsError(try edit.validate(source: source), "A portrait crop does not fit the upright landscape picture")
    }

    func testRotationOutsideTheButtonIsRefused() {
        var edit = EditSettings(source: source)
        for rotation in [45, 360, -90, 91] {
            edit.rotation = rotation
            XCTAssertThrowsError(try edit.validate(source: source), "rotation \(rotation)")
        }
        edit.rotation = 270
        XCTAssertNoThrow(try edit.validate(source: source))
    }

    func testLockedRatiosTurnWithThePicture() throws {
        var edit = EditSettings(source: source)
        edit.cropEnabled = true; edit.cropAspectRatio = .widescreen; edit.lastLockedCropAspectRatio = .widescreen
        let turned = edit.turnedClockwise(source: source)
        XCTAssertEqual(turned.cropAspectRatio, .portrait, "A 16:9 frame turned on its side is a 9:16 frame")
        XCTAssertEqual(turned.lastLockedCropAspectRatio, .portrait)
        XCTAssertEqual(turned.crop, PixelRect(width: 1080, height: 1920))
        XCTAssertEqual(turned.turnedClockwise(source: source).cropAspectRatio, .widescreen)

        for aspect in [CropAspectRatio.original, .square, .free] {
            edit.cropAspectRatio = aspect
            XCTAssertEqual(edit.turnedClockwise(source: source).cropAspectRatio, aspect, "\(aspect) reads the same either way up")
        }

        // The menu has no upright 4:3, 1.85:1 or 2.39:1, so those unlock; the lock button still remembers them.
        for aspect in [CropAspectRatio.classic, .cinema, .scope] {
            edit.cropAspectRatio = aspect; edit.lastLockedCropAspectRatio = aspect
            let unlocked = edit.turnedClockwise(source: source)
            XCTAssertEqual(unlocked.cropAspectRatio, .free, "\(aspect)")
            XCTAssertEqual(unlocked.lastLockedCropAspectRatio, aspect)
        }
    }

    func testRotationSurvivesACodingRoundTripAndOlderSettingsStayUpright() throws {
        var edit = EditSettings(); edit.start = 1; edit.end = 5; edit.rotation = 270
        let restored = try JSONDecoder().decode(EditSettings.self, from: JSONEncoder().encode(edit))
        XCTAssertEqual(restored.rotation, 270)
        let old = try JSONDecoder().decode(EditSettings.self, from: Data(#"{"start":0,"end":5,"cropEnabled":false,"crop":{"x":0,"y":0,"width":16,"height":16},"method":"Automatic","quality":"Balanced"}"#.utf8))
        XCTAssertEqual(old.rotation, 0)
    }

    func testFilterTurnsClockwise() {
        XCTAssertNil(MediaEngine.rotationFilter(0))
        XCTAssertEqual(MediaEngine.rotationFilter(90), "transpose=clock")
        XCTAssertEqual(MediaEngine.rotationFilter(180), "hflip,vflip")
        XCTAssertEqual(MediaEngine.rotationFilter(270), "transpose=cclock")
    }
}
