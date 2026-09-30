import XCTest
@testable import CropTrimmerCore

/// What the joined picture actually contains. The filtergraph's wording can look right and still
/// render the wrong thing, so these run the real engine over real movies and read real pixels.
final class JoinedPictureTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: TestTools.ffmpeg))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-join-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let directory { try? FileManager.default.removeItem(at: directory) } }

    /// A loop smaller than the joined frame keeps its own size and sits on black — it is not blown up
    /// to fill the frame. The dialog promises exactly this when the owner picks a frame, and a
    /// frame-sized scale target quietly broke it: a 320 × 240 loop filled a 640 × 480 clip with
    /// upscaled pixels and no bars at all.
    func testASmallerLoopIsCentredOnBlackRatherThanEnlarged() async throws {
        let small = try movie(named: "small", color: "red", size: "320x240")
        let big = try movie(named: "big", color: "blue", size: "640x480")
        let engine = MediaEngine()
        let source = try await engine.inspect(big)
        let out = directory.appendingPathComponent("joined.mp4")
        let request = JoinRequest(segments: [small, big], width: 640, height: 480, quality: .high,
                                  expectedDuration: 2, settings: EditSettings(source: source), source: source)
        let result = try await engine.join(request, to: out) { _, _ in }

        XCTAssertEqual(result.segments, 2)
        XCTAssertEqual(result.width, 640); XCTAssertEqual(result.height, 480)
        // The colours are read from the fixtures rather than written down, so nothing here depends on
        // how a given FFmpeg renders "red" into limited-range YUV.
        let red = try pixel(small, at: (160, 120), seconds: 0.5)
        let blue = try pixel(big, at: (320, 240), seconds: 0.5)
        XCTAssertNotEqual(red, black); XCTAssertNotEqual(blue, black)
        // Halfway through the first loop: its picture is 320 × 240 in the middle of a 640 × 480 frame,
        // so (10, 10) is padding and the centre is the loop.
        XCTAssertEqual(try pixel(out, at: (10, 10), seconds: 0.5), black, "the corner must be padding, not enlarged picture")
        XCTAssertEqual(try pixel(out, at: (320, 240), seconds: 0.5), red, "the loop itself is unchanged in the middle")
        // The loop that already matches the frame fills it, corner included.
        XCTAssertEqual(try pixel(out, at: (10, 10), seconds: 1.5), blue, "a loop the size of the frame still fills it")
    }

    /// The bars go on the axis that has room, and the loop keeps its shape.
    func testATallerLoopIsBarredAtTheSidesNotStretched() async throws {
        let portrait = try movie(named: "portrait", color: "green", size: "240x480")
        let landscape = try movie(named: "landscape", color: "blue", size: "640x480")
        let engine = MediaEngine()
        let source = try await engine.inspect(landscape)
        let out = directory.appendingPathComponent("joined-portrait.mp4")
        let request = JoinRequest(segments: [portrait, landscape], width: 640, height: 480, quality: .high,
                                  expectedDuration: 2, settings: EditSettings(source: source), source: source)
        _ = try await engine.join(request, to: out) { _, _ in }

        let green = try pixel(portrait, at: (120, 240), seconds: 0.5)
        XCTAssertNotEqual(green, black)
        XCTAssertEqual(try pixel(out, at: (10, 240), seconds: 0.5), black, "left of a 240-wide loop is padding")
        XCTAssertEqual(try pixel(out, at: (630, 240), seconds: 0.5), black, "and so is the right")
        XCTAssertEqual(try pixel(out, at: (320, 10), seconds: 0.5), green, "but it reaches the full height it already had")
        XCTAssertEqual(try pixel(out, at: (320, 470), seconds: 0.5), green, "top and bottom alike")
    }

    // MARK: fixtures

    private let black = "000000"

    private func movie(named name: String, color: String, size: String) throws -> URL {
        let url = directory.appendingPathComponent(name + ".mp4")
        try run([ "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=\(color):s=\(size):r=30:d=1",
                  "-c:v", "libx264", "-pix_fmt", "yuv420p", url.path])
        return url
    }

    /// The rendered colour at one point, as lowercase hex RRGGBB.
    private func pixel(_ url: URL, at point: (Int, Int), seconds: Double) throws -> String {
        let data = try run(["-v", "error", "-ss", String(seconds), "-i", url.path,
                            "-vf", "crop=1:1:\(point.0):\(point.1),format=rgb24",
                            "-frames:v", "1", "-f", "rawvideo", "-"])
        return data.prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult private func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: TestTools.ffmpeg)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "ffmpeg failed: " + arguments.joined(separator: " "))
        return data
    }
}
