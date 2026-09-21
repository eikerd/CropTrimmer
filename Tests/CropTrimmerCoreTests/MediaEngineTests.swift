import XCTest
@testable import CropTrimmerCore

final class MediaEngineTests: XCTestCase {
    private var directory: URL!
    private let ffmpeg = TestTools.ffmpeg
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

    func testColorCorrectionForcesEncodingAndChangesPixels() async throws {
        let engine = MediaEngine()
        let source = try await engine.inspect(fixture())
        var edit = EditSettings(source: source)
        edit.method = .fast
        edit.color = ColorSettings(enabled: true, gamma: 2, saturation: 0)
        let plan = try await engine.plan(source: source, settings: edit)
        XCTAssertEqual(plan.method, .encode)
        XCTAssertNotNil(plan.colorLUT)
        let output = try await engine.export(plan: plan, to: directory.appendingPathComponent("color.mp4")) { _, _ in }
        XCTAssertEqual(output.method, .encode)
        XCTAssertTrue(output.note.contains("Encoded"))
        let original = try ffData(["-i", source.url.path, "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"])
        let graded = try ffData(["-i", output.url.path, "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"])
        XCTAssertEqual(original.count, graded.count)
        var channelSpread = 0
        var originalChannelSpread = 0
        var originalMin = UInt8.max, originalMax = UInt8.min
        var gradedMin = UInt8.max, gradedMax = UInt8.min
        for index in stride(from: 0, to: graded.count, by: 3) {
            originalMin = min(originalMin, original[index]); originalMax = max(originalMax, original[index])
            gradedMin = min(gradedMin, graded[index]); gradedMax = max(gradedMax, graded[index])
            originalChannelSpread += abs(Int(original[index]) - Int(original[index + 1]))
            originalChannelSpread += abs(Int(original[index + 1]) - Int(original[index + 2]))
            channelSpread += abs(Int(graded[index]) - Int(graded[index + 1]))
            channelSpread += abs(Int(graded[index + 1]) - Int(graded[index + 2]))
        }
        XCTAssertGreaterThan(originalChannelSpread, 0, "The source fixture must remain chromatic enough to exercise saturation")
        XCTAssertGreaterThan(Int(originalMax) - Int(originalMin), 8, "The source fixture must retain a spatial value range")
        XCTAssertGreaterThan(Int(gradedMax) - Int(gradedMin), 8, "Saturation must not flatten the graded image to a uniform gray")
        XCTAssertLessThan(channelSpread, graded.count / 8, "Saturation zero should produce a near-monochrome export")
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

    func testVideoStartingAfterTheContainerEncodesFromTheChosenFrame() async throws {
        // Audio at 0 and a first picture a few frames later is what phones and screen recorders write.
        let original = try fixture()
        let delayed = directory.appendingPathComponent("delayed.mp4")
        try ff(["-itsoffset", "0.2", "-i", original.path, "-f", "lavfi", "-i", "sine=frequency=440:duration=4.2",
                "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", delayed.path])
        let engine = MediaEngine()
        let source = try await engine.inspect(delayed)
        XCTAssertEqual(source.startTime, 0.2, accuracy: 0.001)
        XCTAssertEqual(source.seekOffset, 0.2, accuracy: 0.001)
        XCTAssertNil(source.encodingRestriction)
        var edit = EditSettings(source: source); edit.start = 1; edit.end = 2
        let plan = try await engine.plan(source: source, settings: edit)
        XCTAssertEqual(plan.method, .encode)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("delayed-out.mp4")) { _, _ in }
        XCTAssertEqual(result.actualStart, 1, accuracy: 0.001)
        XCTAssertEqual(result.actualEnd, 2, accuracy: 0.001)
        XCTAssertEqual(result.duration, 1, accuracy: 0.08)
        // One second into the picture, not one second into the container (which is the frame at 0.8).
        let expectedPixels = try ffData(["-ss", "1", "-i", original.path, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"])
        let earlyPixels = try ffData(["-ss", "0.8", "-i", original.path, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"])
        let actualPixels = try ffData(["-i", result.url.path, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-"])
        XCTAssertEqual(actualPixels.count, expectedPixels.count)
        func distance(_ a: Data, _ b: Data) -> Double { zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count) }
        XCTAssertLessThan(distance(expectedPixels, actualPixels), 4)
        XCTAssertLessThan(distance(expectedPixels, actualPixels), distance(earlyPixels, actualPixels))
    }

    func testAudioStartingAfterThePictureNeedsNoSeekOffset() async throws {
        // The reverse case: the picture is the container's earliest stream, so nothing is added.
        let original = try fixture()
        let late = directory.appendingPathComponent("late-audio.mp4")
        try ff(["-i", original.path, "-itsoffset", "0.3", "-f", "lavfi", "-i", "sine=frequency=440:duration=3.5",
                "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", late.path])
        let engine = MediaEngine()
        let source = try await engine.inspect(late)
        XCTAssertEqual(source.seekOffset, 0, accuracy: 0.001)
        XCTAssertNil(source.encodingRestriction)
        var edit = EditSettings(source: source); edit.start = 1; edit.end = 2; edit.method = .accurate
        let plan = try await engine.plan(source: source, settings: edit)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("late-audio-out.mp4")) { _, _ in }
        XCTAssertEqual(result.actualStart, 1, accuracy: 0.001)
        XCTAssertEqual(result.actualEnd, 2, accuracy: 0.001)
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

    func testSpeedForcesEncodingAndChangesTheRenderedLength() async throws {
        let engine = MediaEngine()
        let source = try await engine.inspect(fixture())
        var edit = EditSettings(source: source)
        edit.start = 0; edit.end = 2; edit.speed = 0.5
        let plan = try await engine.plan(source: source, settings: edit)
        XCTAssertEqual(plan.method, .encode, "A speed change cannot be a stream copy")
        XCTAssertTrue(plan.explanation.lowercased().contains("speed"), plan.explanation)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("half.mp4")) { _, _ in }
        let times = try timestamps(result.url)
        let last = try XCTUnwrap(times.last), first = try XCTUnwrap(times.first)
        let rendered = last - first
        XCTAssertEqual(rendered, 4, accuracy: 0.15, "Two seconds at half speed render as four")
        // The frames are spread, not duplicated: the source's 50 frames still carry the movie.
        XCTAssertEqual(times.count, 50, accuracy: 2)
    }

    func testEightTimesSpeedRendersShorterAndKeepsAudio() async throws {
        let engine = MediaEngine()
        let url = directory.appendingPathComponent("with-audio.mp4")
        try ff(["-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "4", "-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", url.path])
        let source = try await engine.inspect(url)
        var edit = EditSettings(source: source)
        edit.start = 0; edit.end = 4; edit.speed = 8
        let plan = try await engine.plan(source: source, settings: edit)
        let result = try await engine.export(plan: plan, to: directory.appendingPathComponent("fast.mp4")) { _, _ in }
        let probed = try await engine.inspect(result.url)
        XCTAssertEqual(probed.duration, 0.5, accuracy: 0.15, "Four seconds at 8x render as half a second")
        XCTAssertEqual(probed.audioCount, 1, "Audio is sped up, not dropped")
    }
}
