import XCTest
import AVFoundation
@testable import CropTrimmerCore

final class ModelTests: XCTestCase {
    func testNativePlaybackCanNormalizeNonzeroVideoOrigin() async throws {
        let executable = URL(fileURLWithPath: TestTools.ffmpeg)
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: executable.path))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process(); process.executableURL = executable
        process.arguments = ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=10", "-t", "2", "-c:v", "libx264", "-output_ts_offset", "5", url.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let range = try await track.load(.timeRange)
        XCTAssertEqual(range.start.seconds, 0, accuracy: 0.01)
        XCTAssertEqual(range.duration.seconds, 7, accuracy: 0.01)
        let origin = try await NativeTimeline.videoOrigin(in: asset)
        XCTAssertEqual(origin, 5, accuracy: 0.01)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: CMTime(seconds: origin, preferredTimescale: 60000))
        XCTAssertEqual(first.actualTime.seconds, origin, accuracy: 0.01)
    }

    func testTimeFormattingHandlesUntrustedValues() {
        XCTAssertEqual(timeLabel(.infinity), "00:00.000")
        XCTAssertEqual(timeLabel(.nan), "00:00.000")
        XCTAssertEqual(timeLabel(-10), "00:00.000")
        XCTAssertEqual(timeLabel(61.125), "01:01.125")
        XCTAssertFalse(timeLabel(Double.greatestFiniteMagnitude).isEmpty)
    }
    func testCropConstrainedToEvenSourcePixels() {
        let crop = PixelRect(x: -10, y: 901, width: 641, height: 361).constrained(toWidth: 960, height: 540)
        XCTAssertEqual(crop, PixelRect(x: 0, y: 180, width: 640, height: 360))
        let full = PixelRect(x: 900, y: 901, width: Int.max, height: Int.max).constrained(toWidth: 961, height: 541)
        XCTAssertEqual(full, PixelRect(x: 0, y: 0, width: 960, height: 540))
    }
    func testInvalidEditDoesNotOverflow() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = MediaSource(url: url, identity: try SourceIdentity(url: url), duration: 8, width: 960, height: 540, encodedWidth: 960, encodedHeight: 540, rotation: 0, fps: 30, videoCodec: "h264", audioCount: 0, subtitleCount: 0, format: "mp4")
        var settings = EditSettings(source: source)
        settings.cropEnabled = true
        settings.crop = .init(x: Int.max, y: 0, width: Int.max, height: 20)
        XCTAssertThrowsError(try settings.validate(source: source))
        settings.cropEnabled = false; settings.start = .nan
        XCTAssertThrowsError(try settings.validate(source: source))
        settings.start = 7; settings.end = 6
        XCTAssertThrowsError(try settings.validate(source: source))
    }

    func testPlaybackModeButtonCyclesThroughEveryModeOnce() {
        var mode = PlaybackMode.repeatSelection
        var seen: [PlaybackMode] = []
        for _ in PlaybackMode.allCases { seen.append(mode); mode = mode.next }
        XCTAssertEqual(mode, .repeatSelection)
        XCTAssertEqual(Set(seen), Set(PlaybackMode.allCases))
        XCTAssertEqual(PlaybackMode.repeatSelection.next, .once)
    }

    func testSpeedIsOneOfTheMenuRatesAndSetsTheOutputLength() throws {
        var source = EditSettings(); source.start = 10; source.end = 20
        XCTAssertEqual(source.speed, 1)
        XCTAssertEqual(source.outputDuration, 10)
        var half = source; half.speed = 0.5
        XCTAssertEqual(half.outputDuration, 20, "Half speed takes twice as long to play")
        var eight = source; eight.speed = 8
        XCTAssertEqual(eight.outputDuration, 1.25)
        XCTAssertEqual(EditSettings.speeds.first, 0.1); XCTAssertEqual(EditSettings.speeds.last, 8)
        XCTAssertTrue(EditSettings.speeds.contains(1))
    }

    func testSpeedOutsideTheMenuIsRefused() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("fixture".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let media = MediaSource(url: url, identity: try SourceIdentity(url: url), duration: 30, width: 320, height: 240, encodedWidth: 320, encodedHeight: 240, rotation: 0, fps: 25, videoCodec: "h264", audioCount: 1, subtitleCount: 0, format: "mp4")
        var edit = EditSettings(source: media); edit.end = 10
        edit.speed = 3
        XCTAssertThrowsError(try edit.validate(source: media))
        edit.speed = 0
        XCTAssertThrowsError(try edit.validate(source: media))
        edit.speed = 0.25
        XCTAssertNoThrow(try edit.validate(source: media))
    }

    func testSpeedSurvivesACodingRoundTripAndOlderSettingsDefaultToNormal() throws {
        var edit = EditSettings(); edit.start = 1; edit.end = 5; edit.speed = 0.25
        let restored = try JSONDecoder().decode(EditSettings.self, from: JSONEncoder().encode(edit))
        XCTAssertEqual(restored.speed, 0.25)
        let old = try JSONDecoder().decode(EditSettings.self, from: Data(#"{"start":0,"end":5,"cropEnabled":false,"crop":{"x":0,"y":0,"width":16,"height":16},"method":"Automatic","quality":"Balanced"}"#.utf8))
        XCTAssertEqual(old.speed, 1)
    }
}
