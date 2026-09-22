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
}
