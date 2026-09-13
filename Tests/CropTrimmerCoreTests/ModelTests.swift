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
}
