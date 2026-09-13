import XCTest
@testable import CropTrimmerCore

final class MediaEngineTests: XCTestCase {
    private var directory: URL!
    private let ffmpeg = "/opt/homebrew/bin/ffmpeg"
    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: ffmpeg), "Integration fixtures require FFmpeg")
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-engine-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let directory { try? FileManager.default.removeItem(at: directory) } }

    func testBFrameCopyPlansAndVerifiesActualBoundaries() async throws {
        let url = try fixture()
        let engine = MediaEngine()
        let source = try await engine.inspect(url)
        var edit = EditSettings(source: source)
        edit.start = 1; edit.end = 3
        let plan = try await engine.plan(source: source, settings: edit)
        XCTAssertEqual(plan.method, .copy)
        XCTAssertEqual(plan.plannedStart, 1, accuracy: 0.001)
        XCTAssertEqual(plan.plannedEnd, 3.0, accuracy: 0.001)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("copy.mp4")) { _, _ in }
        XCTAssertEqual(result.method, .copy)
        XCTAssertEqual(result.actualStart, 1, accuracy: 0.001)
        XCTAssertEqual(result.actualEnd, 3.0, accuracy: 0.001)
        XCTAssertEqual(result.width, 160)
    }

    func testCropEncodesExactDimensionsAndAllEstimates() async throws {
        let engine = MediaEngine()
        let source = try await engine.inspect(fixture())
        var edit = EditSettings(source: source)
        edit.start = 0.31; edit.end = 1.73; edit.cropEnabled = true
        edit.crop = PixelRect(x: 20, y: 10, width: 80, height: 60)
        let plan = try await engine.plan(source: source, settings: edit)
        XCTAssertEqual(plan.method, .encode)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("crop.mp4")) { _, _ in }
        XCTAssertEqual(result.width, 80); XCTAssertEqual(result.height, 60)
        XCTAssertEqual(result.actualStart, 0.32, accuracy: 0.001)
        XCTAssertEqual(result.method, .encode)
        let sizes = try await engine.estimate(plan: plan) { _, _ in }
        XCTAssertEqual(sizes.count, 3)
        XCTAssertTrue(sizes.values.allSatisfy { $0 > 0 })
    }

    func testSparseKeyframesAndAmbiguousCopyFallback() async throws {
        let engine = MediaEngine()
        let source = try await engine.inspect(fixture(gop: 100))
        var edit = EditSettings(source: source)
        edit.start = 0.8; edit.end = 2.4
        let plan = try await engine.plan(source: source, settings: edit)
        XCTAssertEqual(plan.method, .encode)
        let still = directory.appendingPathComponent("still.mp4")
        try ff(["-f", "lavfi", "-i", "color=red:size=160x120:rate=25", "-t", "4", "-c:v", "libx264", "-g", "25", still.path])
        let stillSource = try await engine.inspect(still)
        edit = EditSettings(source: stillSource); edit.start = 1; edit.end = 3
        let stillPlan = try await engine.plan(source: stillSource, settings: edit)
        XCTAssertEqual(stillPlan.method, .copy)
        let result = try await engine.export(plan: stillPlan, to: directory.appendingPathComponent("fallback.mp4")) { _, _ in }
        XCTAssertEqual(result.method, .encode)
        XCTAssertTrue(result.note.contains("could not be verified"))
    }

    func testRotationIsAppliedOnceAndCropUsesUprightPixels() async throws {
        let unrotated = try fixture()
        for rotation in [0, 90, 180, 270] {
            let rotated = directory.appendingPathComponent("rotated-\(rotation).mp4")
            try ff(["-display_rotation", String(rotation), "-i", unrotated.path, "-c", "copy", rotated.path])
            let engine = MediaEngine()
            let source = try await engine.inspect(rotated)
            XCTAssertEqual(source.width, rotation % 180 == 0 ? 160 : 120)
            XCTAssertEqual(source.height, rotation % 180 == 0 ? 120 : 160)
            var edit = EditSettings(source: source)
            edit.cropEnabled = true; edit.crop = PixelRect(x: 10, y: 20, width: 60, height: 80)
            let plan = try await engine.plan(source: source, settings: edit)
            let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("upright-\(rotation).mp4")) { _, _ in }
            XCTAssertEqual(result.width, 60); XCTAssertEqual(result.height, 80)
            let actual = try await engine.inspect(result.url)
            XCTAssertEqual(actual.rotation, 0)
            let expectedPixels = try ffData(["-i", rotated.path, "-vf", "crop=60:80:10:20", "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"])
            let actualPixels = try ffData(["-i", result.url.path, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"])
            XCTAssertEqual(expectedPixels.count, 60 * 80)
            XCTAssertEqual(actualPixels.count, expectedPixels.count)
            let error = zip(expectedPixels, actualPixels).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(expectedPixels.count)
            XCTAssertLessThan(error, 4, "Upright crop must select the same pixels for rotation \(rotation)")
        }
    }

    func testVariableFrameRateRetainsPresentationIntervals() async throws {
        let url = directory.appendingPathComponent("vfr.mp4")
        try ff(["-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25", "-t", "4", "-vf", "select='if(lt(t,2),not(mod(n,2)),1)'", "-fps_mode", "vfr", "-c:v", "libx264", url.path])
        let engine = MediaEngine()
        let source = try await engine.inspect(url)
        var edit = EditSettings(source: source); edit.method = .accurate
        let plan = try await engine.plan(source: source, settings: edit)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("vfr-out.mp4")) { _, _ in }
        let sourceTimes = try timestamps(url)
        let outputTimes = try timestamps(result.url)
        XCTAssertEqual(outputTimes.count, sourceTimes.count)
        for (a, b) in zip(sourceTimes, outputTimes) { XCTAssertEqual(a, b, accuracy: 0.0001) }
        XCTAssertTrue(zip(sourceTimes, sourceTimes.dropFirst()).contains { abs($1 - $0 - 0.08) < 0.001 })
        XCTAssertTrue(zip(outputTimes, outputTimes.dropFirst()).contains { abs($1 - $0 - 0.04) < 0.001 })
    }

    func testNonzeroStartMapsToSourceVideoOrigin() async throws {
        let original = try fixture()
        let shifted = directory.appendingPathComponent("shifted.mp4")
        try ff(["-i", original.path, "-c", "copy", "-output_ts_offset", "5", shifted.path])
        let engine = MediaEngine()
        let source = try await engine.inspect(shifted)
        XCTAssertEqual(source.startTime, 5, accuracy: 0.001)
        var edit = EditSettings(source: source); edit.start = 1; edit.end = 2
        let plan = try await engine.plan(source: source, settings: edit)
        XCTAssertEqual(plan.method, .encode)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("shifted-out.mp4")) { _, _ in }
        XCTAssertEqual(result.actualStart, 1, accuracy: 0.001)
        let expectedPixels = try ffData(["-ss", "1", "-i", original.path, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"])
        let actualPixels = try ffData(["-i", result.url.path, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"])
        XCTAssertEqual(actualPixels.count, expectedPixels.count)
        let error = zip(expectedPixels, actualPixels).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(expectedPixels.count)
        XCTAssertLessThan(error, 4)
    }

    func testInFlightCancellationRemovesPartialOutput() async throws {
        let url = directory.appendingPathComponent("large.mp4")
        try ff(["-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30", "-t", "12", "-c:v", "libx264", "-preset", "ultrafast", url.path])
        let engine = MediaEngine()
        let source = try await engine.inspect(url)
        var edit = EditSettings(source: source); edit.method = .accurate
        let plan = try await engine.plan(source: source, settings: edit)
        let output = directory.appendingPathComponent("in-flight.mp4")
        let task = Task { try await engine.export(plan: plan, to: output) { _, _ in } }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: output.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), "Cancellation should exercise a running encoder")
        let start = Date()
        await engine.cancel()
        do { _ = try await task.value; XCTFail("In-flight cancellation must fail") } catch MediaError.cancelled { }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testAudioPolicyAndSourceMutation() async throws {
        let url = directory.appendingPathComponent("audio.mp4")
        try ff(["-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25", "-f", "lavfi", "-i", "sine=frequency=500:sample_rate=48000",
                "-f", "lavfi", "-i", "sine=frequency=900:sample_rate=48000", "-t", "4", "-map", "0:v", "-map", "1:a", "-map", "2:a", "-c:v", "libx264", "-g", "25", "-c:a", "aac", url.path])
        let engine = MediaEngine()
        let source = try await engine.inspect(url)
        XCTAssertEqual(source.audioCount, 2)
        var edit = EditSettings(source: source); edit.start = 0.3; edit.end = 2.7; edit.method = .accurate
        let plan = try await engine.plan(source: source, settings: edit)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("audio-out.mp4")) { _, _ in }
        let output = try await engine.inspect(result.url)
        XCTAssertEqual(output.audioCount, 1)
        edit.method = .fast; edit.start = 1; edit.end = 3
        let copyPlan = try await engine.plan(source: source, settings: edit)
        let copied = try await engine.export(plan: copyPlan, to: directory.appendingPathComponent("audio-copy.mp4")) { _, _ in }
        let copiedSource = try await engine.inspect(copied.url)
        XCTAssertEqual(copiedSource.audioCount, 2)
        let audio = try ffData(["-i", copied.url.path, "-map", "0:a:0", "-vn", "-f", "s16le", "-c:a", "pcm_s16le", "-"])
        let audioSeconds = Double(audio.count) / 2 / 48_000
        XCTAssertEqual(audioSeconds, copied.duration, accuracy: 0.03, "Audio tail should reach presentation B within one AAC packet")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: url.path)
        do {
            _ = try await engine.plan(source: source, settings: edit)
            XCTFail("Changed source must fail")
        } catch MediaError.sourceChanged { }
    }

    func testCancellationRemovesOwnedOutput() async throws {
        let engine = MediaEngine()
        let source = try await engine.inspect(fixture())
        var edit = EditSettings(source: source); edit.method = .accurate
        let plan = try await engine.plan(source: source, settings: edit)
        let output = directory.appendingPathComponent("cancel.mp4")
        let task = Task { try await engine.export(plan: plan, to: output) { _, _ in } }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled task must fail") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testEmbeddedCoverArtIsIgnoredForInspectionAndExport() async throws {
        // FFmpeg's MP4 muxer stores cover art as an extra video stream flagged attached_pic.
        let cover = directory.appendingPathComponent("cover.png")
        try ff(["-f", "lavfi", "-i", "color=blue:size=64x64", "-frames:v", "1", cover.path])
        let url = directory.appendingPathComponent("art.mp4")
        try ff(["-i", cover.path, "-i", fixture().path, "-map", "0", "-map", "1", "-c:v:0", "png", "-c:v:1", "copy", "-disposition:v:0", "attached_pic", url.path])
        let engine = MediaEngine()
        let source = try await engine.inspect(url)
        XCTAssertEqual(source.width, 160); XCTAssertEqual(source.height, 120)
        XCTAssertEqual(source.videoCodec, "h264")
        var edit = EditSettings(source: source)
        edit.start = 1; edit.end = 3
        let plan = try await engine.plan(source: source, settings: edit)
        XCTAssertEqual(plan.method, .copy)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("art-copy.mp4")) { _, _ in }
        XCTAssertEqual(result.width, 160)
        XCTAssertEqual(result.actualStart, 1, accuracy: 0.001)
        XCTAssertEqual(result.actualEnd, 3, accuracy: 0.001)
        edit.cropEnabled = true; edit.crop = PixelRect(x: 20, y: 10, width: 80, height: 60)
        let encoded = try await engine.export(plan: try await engine.plan(source: source, settings: edit), to: directory.appendingPathComponent("art-crop.mp4")) { _, _ in }
        XCTAssertEqual(encoded.width, 80); XCTAssertEqual(encoded.height, 60)
    }

    private func fixture(gop: Int = 25) throws -> URL {
        let url = directory.appendingPathComponent("source-\(gop).mp4")
        try ff(["-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25", "-t", "4", "-c:v", "libx264", "-g", String(gop), "-sc_threshold", "0", "-pix_fmt", "yuv420p", url.path])
        return url
    }
    private func timestamps(_ url: URL) throws -> [Double] {
        let data = try ffData(["-copyts", "-i", url.path, "-an", "-fps_mode", "passthrough", "-enc_time_base", "-1", "-f", "framemd5", "-"])
        var base = 0.0
        var result: [Double] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            if line.hasPrefix("#tb 0:") {
                let parts = line.dropFirst(7).trimmingCharacters(in: .whitespaces).split(separator: "/")
                base = Double(parts[0])! / Double(parts[1])!
            } else if !line.hasPrefix("#") {
                let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 6, let time = Double(parts[2]) { result.append(time * base) }
            }
        }
        return result
    }
    private func ffData(_ arguments: [String]) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-nostdin"] + arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let result = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MediaError.failed("Fixture inspection failed") }
        return result
    }
    private func ff(_ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"] + arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MediaError.failed("Fixture generation failed") }
    }
}
