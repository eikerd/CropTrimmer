import XCTest
@testable import CropTrimmerCore

/// Export All chains every loop into one clip. These cover the two decisions that clip makes on its
/// own — the frame it renders into, and the filtergraph that gets segments into that frame — plus
/// the name the single file ends up with.
final class JoinedExportTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("Beach Clip.mov")
        try Data("fixture".utf8).write(to: url)
    }
    override func tearDownWithError() throws { if let url { try? FileManager.default.removeItem(at: url) } }

    // MARK: the frame

    func testFrameOfMatchingLoopsIsThatSameFrame() {
        let sizes = [(width: 1280, height: 720), (width: 1280, height: 720)]
        XCTAssertEqual(MediaEngine.joinFrame(sizes, mode: .fitAll).map(Pair.init), Pair(1280, 720))
        XCTAssertEqual(MediaEngine.joinFrame(sizes, mode: .matchFirst).map(Pair.init), Pair(1280, 720))
    }

    func testFitAllHoldsEveryLoopAtFullSize() {
        let sizes = [(width: 1280, height: 720), (width: 1920, height: 800)]
        XCTAssertEqual(MediaEngine.joinFrame(sizes, mode: .fitAll).map(Pair.init), Pair(1920, 800))
    }

    /// A turned loop beside an upright one is the case the owner is asked about: fitting both whole
    /// needs a square, while matching the first keeps that loop's own frame and shrinks the other.
    func testPortraitBesideLandscape() {
        let sizes = [(width: 1920, height: 1080), (width: 1080, height: 1920)]
        XCTAssertEqual(MediaEngine.joinFrame(sizes, mode: .fitAll).map(Pair.init), Pair(1920, 1920))
        XCTAssertEqual(MediaEngine.joinFrame(sizes, mode: .matchFirst).map(Pair.init), Pair(1920, 1080))
    }

    /// H.264's 4:2:0 chroma cannot encode an odd frame, and an uncropped loop of an odd-sized
    /// source carries odd dimensions straight through.
    func testOddSizesRoundUpToEven() {
        XCTAssertEqual(MediaEngine.joinFrame([(width: 641, height: 481)], mode: .fitAll).map(Pair.init), Pair(642, 482))
        XCTAssertEqual(MediaEngine.joinFrame([(width: 641, height: 481)], mode: .matchFirst).map(Pair.init), Pair(642, 482))
    }

    func testNoLoopsHasNoFrame() {
        XCTAssertNil(MediaEngine.joinFrame([], mode: .fitAll))
    }

    // MARK: the filtergraph

    func testEverySegmentIsConformedAndConcatenated() {
        let graph = MediaEngine.joinFilterGraph(count: 3, width: 1920, height: 1080, fps: 30, audio: true)
        for index in 0..<3 {
            XCTAssertTrue(graph.contains("[\(index):v:0]scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease"), graph)
            XCTAssertTrue(graph.contains("pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black"), graph)
            XCTAssertTrue(graph.contains("[\(index):a:0]aformat="), graph)
        }
        XCTAssertTrue(graph.contains("[v0][a0][v1][a1][v2][a2]concat=n=3:v=1:a=1[vout][aout]"), graph)
    }

    /// A silent source produces silent segments; asking concat for an audio stream that no segment
    /// has fails the whole join, so the audio half of the graph has to disappear with it.
    func testSilentSourceJoinsWithoutAudio() {
        let graph = MediaEngine.joinFilterGraph(count: 2, width: 640, height: 480, fps: 25, audio: false)
        XCTAssertFalse(graph.contains("aformat"))
        XCTAssertTrue(graph.contains("[v0][v1]concat=n=2:v=1:a=0[vout]"), graph)
        XCTAssertFalse(graph.contains("[aout]"))
    }

    /// One rate for the clip: a loop carrying a speed leaves its segment with the source's frame
    /// count over a shorter span, and concat cannot interleave two timebases.
    func testOneFrameRateAcrossEverySegment() {
        let graph = MediaEngine.joinFilterGraph(count: 2, width: 640, height: 480, fps: 29.97, audio: false)
        XCTAssertEqual(graph.components(separatedBy: "fps=29.970000000").count - 1, 2, graph)
    }

    // MARK: the name

    func testJoinedClipIsNamedForAllItsLoops() {
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: url, cropped: true, trimmed: true, joined: true),
                       "Beach Clip - all loops - trim crop")
    }

    func testJoinedNameFollowsTheLoopNumberPreference() {
        var options = FilenameOptions.standard
        options.includeLoopNumber = false
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: url, cropped: false, trimmed: true, options: options, joined: true),
                       "Beach Clip - trim")
    }

    func testAnOrdinaryExportKeepsItsLoopNumber() {
        XCTAssertEqual(OutputPublisher.baseName(sourceURL: url, cropped: false, trimmed: true, loopNumber: 2),
                       "Beach Clip - loop 02 - trim")
    }

    // MARK: the question the owner is asked

    func testMatchingLoopsAreNotAsked() {
        let sizes = [(width: 1280, height: 720), (width: 1280, height: 720)]
        XCTAssertNil(JoinFramePrompt(sizes: sizes, fit: (1280, 720), matched: (1280, 720)),
                     "Nothing to decide, so the export is not stopped to decide it")
    }

    func testTheQuestionNamesEveryLoopAndWhatEachAnswerProduces() throws {
        let sizes = [(width: 1920, height: 1080), (width: 1080, height: 1920)]
        let prompt = try XCTUnwrap(JoinFramePrompt(sizes: sizes, fit: (1920, 1920), matched: (1920, 1080)))
        XCTAssertEqual(prompt.message, "These loops are not all the same size.")
        XCTAssertTrue(prompt.detail.hasPrefix("Loop 1 is 1920 × 1080, Loop 2 is 1080 × 1920."), prompt.detail)
        XCTAssertTrue(prompt.detail.contains("centred on black"), prompt.detail)
        XCTAssertEqual(prompt.fitTitle, "Fit Every Loop · 1920 × 1920")
        XCTAssertEqual(prompt.matchTitle, "Match Loop 1 · 1920 × 1080")
    }

    /// The scale target is bounded by each segment's own size, so a segment already inside the frame
    /// is untouched. Scaling to the frame itself would enlarge every smaller loop until it touched an
    /// edge, which is the opposite of the "centred on black" the owner is promised.
    func testTheGraphNeverEnlargesASegment() {
        let graph = MediaEngine.joinFilterGraph(count: 1, width: 1920, height: 1080, fps: 30, audio: false)
        XCTAssertTrue(graph.contains("scale='min(1920,iw)':'min(1080,ih)'"), graph)
        XCTAssertFalse(graph.contains("scale=1920:1080"), "a bare frame-sized scale target upscales smaller segments: " + graph)
        XCTAssertTrue(graph.contains("force_divisible_by=2"), "odd scaled sizes would pad at odd offsets: " + graph)
    }

    // MARK: joining honours what the encoder may not touch

    /// Loops that all resolve to a stream copy never reach `encodedPlan`, where this check normally
    /// lives — but the join encodes regardless, so it has to make the check itself.
    func testJoiningRefusesASourceNoEncodeMayTouch() async throws {
        let source = MediaSource(url: url, identity: try SourceIdentity(url: url), duration: 30,
                                 width: 1920, height: 1080, encodedWidth: 1920, encodedHeight: 1080,
                                 rotation: 0, fps: 30, videoCodec: "hevc", audioCount: 0, subtitleCount: 0,
                                 format: "mov", encodingRestriction: "Encoding is not supported for HDR or wide-color video.")
        let request = JoinRequest(segments: [url, url], width: 1920, height: 1080, quality: .high,
                                  expectedDuration: 4, settings: EditSettings(source: source), source: source)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            _ = try await MediaEngine().join(request, to: out) { _, _ in }
            XCTFail("An HDR source must not be quietly converted by Export All")
        } catch {
            XCTAssertEqual((error as? MediaError)?.errorDescription, "Encoding is not supported for HDR or wide-color video.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path), "nothing is written when the join is refused")
    }

    /// Odd dimensions are the one restriction a join resolves on its own: the frame is even by
    /// construction and every segment is padded into it.
    func testJoiningAcceptsAnOddSizedSource() async throws {
        let source = MediaSource(url: url, identity: try SourceIdentity(url: url), duration: 30,
                                 width: 641, height: 481, encodedWidth: 641, encodedHeight: 481,
                                 rotation: 0, fps: 30, videoCodec: "h264", audioCount: 0, subtitleCount: 0,
                                 format: "mov", encodingRestriction: MediaEngine.oddDimensionRestriction)
        let request = JoinRequest(segments: [url, url], width: 642, height: 482, quality: .high,
                                  expectedDuration: 4, settings: EditSettings(source: source), source: source)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            _ = try await MediaEngine().join(request, to: out) { _, _ in }
        } catch {
            // It fails later, on the fixture that is not a real movie — but never on the restriction.
            XCTAssertNotEqual((error as? MediaError)?.errorDescription, MediaEngine.oddDimensionRestriction)
        }
    }

    /// Comparing tuples through XCTAssertEqual needs a nominal type.
    private struct Pair: Equatable {
        let width: Int, height: Int
        init(_ size: (width: Int, height: Int)) { width = size.width; height = size.height }
        init(_ width: Int, _ height: Int) { self.width = width; self.height = height }
    }
}
