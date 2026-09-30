import AppKit
import SwiftUI
import XCTest
@testable import CropTrimmer
import CropTrimmerCore

/// Not a test of behaviour: renders the real editor with a movie and loops open, so a visual
/// change can be looked at before it is committed. Skipped unless RENDER_SHOT names a file.
final class RenderShotTests: XCTestCase {
    @MainActor
    func testRenderEditor() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_SHOT"] else { throw XCTSkip("RENDER_SHOT not set") }
        guard let movie = ProcessInfo.processInfo.environment["RENDER_MOVIE"] else { throw XCTSkip("RENDER_MOVIE not set") }
        _ = NSApplication.shared
        let model = EditorModel()
        defer { model.shutdown() }
        model.open(URL(fileURLWithPath: movie))
        let deadline = Date().addingTimeInterval(20)
        while model.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNotNil(model.source, model.errorMessage ?? "open failed")
        model.addLoop(); model.settings.start = 1; model.settings.end = 4
        model.addLoop(); model.settings.start = 6; model.settings.end = 9.5
        model.addLoop(); model.settings.start = 12; model.settings.end = 15
        while model.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .milliseconds(1200))
        let renderer = ImageRenderer(content: EditorView(model: model).frame(width: 1160, height: 820).preferredColorScheme(.dark))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return XCTFail("nothing rendered")
        }
        try png.write(to: URL(fileURLWithPath: out))
    }

    /// The Exports sheet showing a joined clip: it has no single "before" to stand beside it, so the
    /// Original pane is absent and the exported picture takes the width.
    @MainActor
    func testRenderJoinedReview() async throws {
        guard let out = ProcessInfo.processInfo.environment["RENDER_REVIEW"] else { throw XCTSkip("RENDER_REVIEW not set") }
        let ffmpeg = TestTools.ffmpeg
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: ffmpeg))
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-review-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Sunset Drive.mp4")
        let process = Process(); process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30",
                             "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "20",
                             "-c:v", "libx264", "-g", "30", "-pix_fmt", "yuv420p", "-c:a", "aac", url.path]
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        let model = EditorModel()
        defer { model.shutdown() }
        model.open(url)
        var deadline = Date().addingTimeInterval(20)
        while model.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        model.addLoop(); model.settings.start = 1; model.settings.end = 4
        model.addLoop(); model.settings.start = 8; model.settings.end = 11.5
        deadline = Date().addingTimeInterval(20)
        while model.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        model.exportAll()
        deadline = Date().addingTimeInterval(120)
        while model.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.results.first?.segments, 2)
        try await Task.sleep(for: .milliseconds(2500))
        let renderer = ImageRenderer(content: ReviewView(model: model).preferredColorScheme(.dark))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return XCTFail("nothing rendered")
        }
        try png.write(to: URL(fileURLWithPath: out))
    }
}
