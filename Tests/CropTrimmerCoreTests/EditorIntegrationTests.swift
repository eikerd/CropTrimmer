import AppKit
import AVFoundation
import XCTest
@testable import CropTrimmer
import CropTrimmerCore

final class EditorIntegrationTests: XCTestCase {
    @MainActor
    private func waitUntil(_ condition: () -> Bool, timeout: Double = 15) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "Timed out waiting for editor state")
    }

    @MainActor
    func testPlaybackStaysOnThroughEditsAndOpeningAnotherMovie() async throws {
        _ = NSApplication.shared
        let ffmpeg = TestTools.ffmpeg
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: ffmpeg))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-sticky-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var movies: [URL] = []
        for name in ["First.mp4", "Second.mp4"] {
            let url = directory.appendingPathComponent(name)
            let process = Process(); process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25", "-t", "12", "-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p", url.path]
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
            movies.append(url)
        }
        let model = EditorModel()
        defer { model.shutdown() }
        model.open(movies[0])
        try await waitUntil { !model.isBusy && model.player.currentItem?.status == .readyToPlay }
        model.togglePlayback()
        try await waitUntil { model.isPlaying }

        model.setLoopLength(10)
        XCTAssertTrue(model.isPlaying, "Changing loop length keeps playing")
        model.setLoopLength(5)
        XCTAssertTrue(model.isPlaying)
        XCTAssertGreaterThanOrEqual(model.position, model.settings.start)
        XCTAssertLessThan(model.position, model.settings.end, "A shorter loop keeps playing inside its new range")
        model.addLoop()
        XCTAssertTrue(model.isPlaying, "Adding a loop keeps playing")
        model.selectAdjacentLoop(-1)
        XCTAssertTrue(model.isPlaying, "Switching loops keeps playing")
        model.removeLoop()
        XCTAssertTrue(model.isPlaying, "Deleting a loop keeps playing")
        model.jump(1)
        XCTAssertTrue(model.isPlaying, "Jumping keeps playing")

        model.open(movies[1])
        try await waitUntil { !model.isBusy && model.source?.url.lastPathComponent == "Second.mp4" }
        try await waitUntil { model.isPlaying }

        model.stop()
        XCTAssertFalse(model.isPlaying, "Stop still stops")
        model.open(movies[0])
        try await waitUntil { !model.isBusy && model.source?.url.lastPathComponent == "First.mp4" }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(model.isPlaying, "A stopped player stays stopped when another movie opens")
    }

    @MainActor
    func testTransportAndIndependentQueueExports() async throws {
        _ = NSApplication.shared
        let ffmpeg = TestTools.ffmpeg
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: ffmpeg))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-editor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Fixture.mp4")
        let process = Process(); process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25", "-t", "12", "-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p", url.path]
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let model = EditorModel()
        defer { model.shutdown() }
        model.open(url)
        try await waitUntil { !model.isBusy }
        XCTAssertNotNil(model.source, model.errorMessage ?? "Open failed")
        try await waitUntil { model.player.currentItem?.status == .readyToPlay }
        // A movie opens bare: no default loop, the whole timeline in play.
        XCTAssertTrue(model.loops.ranges.isEmpty)
        // Nothing to plan with no loops, so the status must not stall mid-sentence.
        try await waitUntil { !model.status.contains("Checking export methods") }
        XCTAssertTrue(model.status.hasPrefix("Ready"), model.status)
        XCTAssertEqual(model.settings.start, 0); XCTAssertEqual(model.settings.end, model.source?.duration)
        // + puts the first loop's A at the playhead.
        model.seek(2); model.addLoop()
        XCTAssertEqual(model.loops.selected?.start, 2); XCTAssertEqual(model.loops.selected?.end, 7)
        XCTAssertEqual(model.position, 2)
        model.settings.start = 1; model.settings.end = 3
        let handleOriginal = try XCTUnwrap(model.loops.selected)
        model.beginLoopDrag(handleOriginal.id)
        // A trims the start with B held still, and the playhead follows A.
        model.dragLoopHandle(start: true, original: handleOriginal, by: 0.5)
        XCTAssertEqual(model.settings.start, 1.5)
        XCTAssertEqual(model.settings.end, 3)
        XCTAssertEqual(model.position, 1.5)
        // Repeated drag events use the captured range, not the last event's result.
        model.dragLoopHandle(start: true, original: handleOriginal, by: -0.5)
        XCTAssertEqual(model.settings.start, 0.5)
        XCTAssertEqual(model.settings.end, 3)
        XCTAssertEqual(model.position, 0.5)
        model.dragLoopHandle(start: true, original: handleOriginal, by: 100)
        XCTAssertEqual(model.settings.end, 3)
        XCTAssertLessThan(model.settings.start, 3)
        model.dragLoopHandle(start: true, original: handleOriginal, by: -100)
        XCTAssertEqual(model.settings.start, 0)
        XCTAssertEqual(model.settings.end, 3)
        // Moving the whole loop by its header keeps the playhead on A, and pushing it
        // past the end shortens it to the movie's end.
        let moved = try XCTUnwrap(model.loops.selected)
        model.moveLoop(moved.id, originalStart: moved.start, originalEnd: moved.end, by: 4)
        XCTAssertEqual(model.settings.start, 4); XCTAssertEqual(model.settings.end, 7)
        XCTAssertEqual(model.position, 4)
        model.moveLoop(moved.id, originalStart: moved.start, originalEnd: moved.end, by: 11)
        XCTAssertEqual(model.settings.start, 11); XCTAssertEqual(model.settings.end, 12)
        XCTAssertEqual(model.position, 11)
        model.moveLoop(moved.id, originalStart: moved.start, originalEnd: moved.end, by: 0)
        XCTAssertEqual(model.settings.start, 0); XCTAssertEqual(model.settings.end, 3)
        model.dragLoopHandle(start: false, original: try XCTUnwrap(model.loops.selected), by: 1)
        XCTAssertEqual(model.settings.start, 0)
        XCTAssertEqual(model.settings.end, 4)
        XCTAssertEqual(model.position, 3.999, accuracy: 0.000001, "Dragging B shows the loop's last frame")
        model.settings.start = 1; model.settings.end = 3
        model.recallStart()
        try await waitUntil { abs(model.player.currentTime().seconds - 1) < 0.05 }
        model.step(1)
        try await waitUntil { model.position > 1.02 }
        let stepped = model.position
        model.step(-1)
        try await waitUntil { model.position < stepped - 0.02 }
        model.jump(5)
        try await waitUntil { model.position > 5.9 }
        model.jump(-5)
        try await waitUntil { model.position < 1.1 }
        model.beginCrop()
        model.togglePlayback()
        XCTAssertFalse(model.cropAdjusting)
        try await waitUntil { model.isPlaying && model.position > 1.2 }
        model.setSpeed(0.5)
        XCTAssertEqual(model.player.rate, 0.5, "A new speed applies at once while playing")
        XCTAssertEqual(model.loops.selected?.settings.speed, 0.5, "The speed belongs to the loop, so the export carries it")
        XCTAssertTrue(model.speedIsRendered)
        model.setSpeed(3)
        XCTAssertEqual(model.speed, 0.5, "Speeds outside the menu are refused")
        model.setSpeed(1)
        model.togglePlayback()
        XCTAssertFalse(model.isPlaying)
        model.stop()
        try await waitUntil { abs(model.player.currentTime().seconds - 1) < 0.05 }
        // Paused navigation to B must not trigger repeat playback.
        model.recallEnd()
        try await waitUntil { abs(model.player.currentTime().seconds - 3) < 0.05 }
        XCTAssertFalse(model.isPlaying)
        model.settings.end = 1.4
        model.playbackMode = .once
        model.togglePlayback()
        try await waitUntil { !model.isPlaying && abs(model.position - 1.4) < 0.05 }
        model.playbackMode = .repeatSelection
        model.togglePlayback()
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertTrue(model.isPlaying)
        XCTAssertGreaterThanOrEqual(model.position, 1)
        XCTAssertLessThan(model.position, 1.45)
        model.stop()
        model.playbackMode = .whole
        model.stop()
        try await waitUntil { model.player.currentTime().seconds < 0.05 }
        model.muted = true; model.volume = 0.4
        XCTAssertTrue(model.player.isMuted)
        XCTAssertEqual(model.player.volume, 0.4, accuracy: 0.001)
        model.settings.end = 3
        let first = try XCTUnwrap(model.loops.selectedID)
        model.settings.cropEnabled = true
        model.settings.crop = PixelRect(width: 80, height: 60)
        model.setCropAspectRatio(.square)
        XCTAssertEqual(model.settings.crop.width, model.settings.crop.height)
        let lockedCrop = model.settings.crop
        model.toggleCropAspectLock()
        XCTAssertEqual(model.settings.cropAspectRatio, .free)
        XCTAssertEqual(model.settings.crop, lockedCrop)
        model.toggleCropAspectLock()
        XCTAssertEqual(model.settings.cropAspectRatio, .square)
        XCTAssertEqual(model.settings.crop, lockedCrop)

        model.resetCrop()
        XCTAssertEqual(model.settings.crop, PixelRect(x: 20, width: 120, height: 120))
        model.setCropAspectRatio(.free)
        model.settings.crop = PixelRect(width: 80, height: 60)
        model.settings.method = .accurate; model.settings.quality = .high
        let firstSettings = model.settings
        model.addLoop()
        let second = try XCTUnwrap(model.loops.selectedID)
        model.settings.cropEnabled = false; model.settings.quality = .smaller
        let secondSettings = model.settings
        let secondPosition = model.position
        var inactiveEdit = firstSettings
        inactiveEdit.quality = .balanced
        inactiveEdit.start = 1.2
        XCTAssertNil(model.updateLoop(id: first, settings: inactiveEdit))
        XCTAssertEqual(model.loops.selectedID, second)
        XCTAssertEqual(model.settings, secondSettings)
        XCTAssertEqual(model.position, secondPosition)
        XCTAssertEqual(model.loops.ranges.first { $0.id == first }?.settings, inactiveEdit)
        try await waitUntil { model.queuePlans[first]?.settings == inactiveEdit && model.queuePlans[second]?.settings == secondSettings }
        XCTAssertEqual(model.queuePlans[first]?.method, .encode)
        XCTAssertEqual(model.queuePlans[first]?.fileExtension, "mp4")
        XCTAssertEqual(model.loops.selectedID, second)
        var invalidEdit = inactiveEdit; invalidEdit.end = 0
        XCTAssertNotNil(model.updateLoop(id: first, settings: invalidEdit))
        XCTAssertEqual(model.loops.ranges.first { $0.id == first }?.settings, inactiveEdit)
        model.queueInputErrors[first] = ["Start": "Invalid draft"]
        XCTAssertTrue(model.hasInputErrors)
        XCTAssertFalse(model.hasErrors(for: second))
        model.exportLoop(first)
        XCTAssertFalse(model.isBusy)
        model.queueInputErrors[first] = nil
        XCTAssertNil(model.updateLoop(id: first, settings: firstSettings))
        model.estimateLoop(first)
        try await waitUntil({ !model.isBusy }, timeout: 40)
        XCTAssertEqual(model.queueEstimates[first]?.count, 3)
        XCTAssertEqual(model.loops.selectedID, second)
        model.selectLoop(first)
        XCTAssertEqual(model.queueEstimates[first]?.count, 3)
        model.selectLoop(second)
        model.addLoop()
        let third = try XCTUnwrap(model.loops.selectedID)
        XCTAssertFalse(model.canSelectNextLoop)
        model.selectAdjacentLoop(1)
        XCTAssertEqual(model.loops.selectedID, third)
        model.selectAdjacentLoop(-1)
        XCTAssertEqual(model.loops.selectedID, second)
        XCTAssertEqual(model.settings, secondSettings)
        XCTAssertEqual(model.position, secondSettings.start)
        XCTAssertEqual(model.playbackMode, .repeatSelection)
        XCTAssertFalse(model.isPlaying)
        model.selectAdjacentLoop(-1)
        XCTAssertEqual(model.loops.selectedID, first)
        XCTAssertEqual(model.settings, firstSettings)
        XCTAssertFalse(model.canSelectPreviousLoop)
        model.selectAdjacentLoop(-1)
        XCTAssertEqual(model.loops.selectedID, first)
        model.togglePlayback()
        try await waitUntil { model.isPlaying }
        model.selectAdjacentLoop(1)
        XCTAssertEqual(model.loops.selectedID, second)
        try await waitUntil { model.isPlaying && model.position >= secondSettings.start && model.position < secondSettings.end }
        model.stop()
        model.selectAdjacentLoop(1)
        XCTAssertEqual(model.loops.selectedID, third)
        model.removeLoop()
        XCTAssertEqual(model.loops.ranges.map(\.id), [first, second])
        let extra = { model.addLoop(); return model.loops.selectedID! }()
        model.selectLoop(first)
        model.removeLoop(extra)
        XCTAssertEqual(model.loops.ranges.map(\.id), [first, second], "Deleting an unselected loop removes that loop, not the selected one")
        XCTAssertEqual(model.loops.selectedID, first, "and keeps the selection")
        XCTAssertEqual(model.position, firstSettings.start, "and leaves the playhead where it was")
        model.selectLoop(first)
        XCTAssertEqual(model.settings, firstSettings)
        model.selectLoop(second)
        XCTAssertEqual(model.settings, secondSettings)
        model.exportQueue()
        XCTAssertTrue(model.isBusy)
        model.selectLoop(first)
        XCTAssertEqual(model.loops.selectedID, second, "Queue edits freeze during export")
        try await waitUntil({ !model.isBusy }, timeout: 40)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.results.count, 2)
        XCTAssertEqual(model.results.map(\.settings), [firstSettings, secondSettings])
        XCTAssertEqual(model.results.map(\.width), [80, 160])
        XCTAssertEqual(model.results.map { $0.url.lastPathComponent }, ["Fixture - loop 01 - trim crop.mp4", "Fixture - loop 02 - trim.mp4"])
        model.showReview = false
        model.exportQueue()
        model.cancel()
        try await waitUntil { !model.isBusy && model.plan != nil }
        XCTAssertEqual(model.results.count, 2)
        XCTAssertTrue(model.status.contains("Cancelled"), model.status)
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(contents.contains { $0.hasPrefix(".croptrimmer-") })
        let queueBeforeRename = model.loops
        let settingsBeforeRename = model.settings
        let identityBeforeRename = try XCTUnwrap(model.source).identity
        XCTAssertTrue(model.renameSource(to: "Short"))
        try await waitUntil { !model.isBusy && model.plan != nil }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.source?.url.lastPathComponent, "Short.mp4")
        XCTAssertEqual(model.source?.identity, identityBeforeRename)
        XCTAssertEqual(model.loops, queueBeforeRename)
        XCTAssertEqual(model.settings, settingsBeforeRename)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(model.results.allSatisfy { $0.sourceURL.lastPathComponent == "Short.mp4" })
        XCTAssertTrue(model.results.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
        let currentAsset = model.player.currentItem?.asset as? AVURLAsset
        XCTAssertEqual(currentAsset?.url.lastPathComponent, "Short.mp4")
        model.selectLoop(first)
        model.exportLoop(second)
        try await waitUntil({ !model.isBusy }, timeout: 40)
        XCTAssertEqual(model.loops.selectedID, first)
        XCTAssertEqual(model.results.last?.url.lastPathComponent, "Short - loop 02 - trim.mp4")
        let exportedURL = try XCTUnwrap(model.results.last).url
        model.showReview = false
        model.open(exportedURL)
        try await waitUntil { !model.isBusy && model.source != nil }
        XCTAssertTrue(model.renameSource(to: "Reopened"))
        try await waitUntil { !model.isBusy && model.source != nil }
        XCTAssertEqual(model.results.last?.url.lastPathComponent, "Reopened.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(model.results.last).url.path))
    }

    /// The playhead rides on A while a loop is dragged, so it must not also be a snap target:
    /// otherwise every update finds a target exactly where the drag just put the playhead, and the
    /// loop sticks instead of following the pointer.
    @MainActor
    func testDraggingDoesNotSnapToThePlayheadThatFollowsIt() async throws {
        _ = NSApplication.shared
        let ffmpeg = TestTools.ffmpeg
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: ffmpeg))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-drag-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Drag.mp4")
        let process = Process(); process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25", "-t", "30", "-c:v", "libx264", "-g", "25", "-pix_fmt", "yuv420p", url.path]
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        let model = EditorModel()
        defer { model.shutdown() }
        model.open(url)
        try await waitUntil { !model.isBusy && model.source != nil }

        // One loop in open space, far from 0, the movie's end and the playhead's starting point.
        model.seek(0)
        model.addLoop()
        let loop = try XCTUnwrap(model.loops.selected)
        XCTAssertNil(model.updateLoop(id: loop.id, settings: {
            var edit = loop.settings; edit.start = 10; edit.end = 11; return edit
        }()))
        let original = try XCTUnwrap(model.loops.selected)
        model.beginLoopDrag(original.id)
        var lastStart = original.start
        for step in 0...4 {
            let delta = 1.0 + Double(step) * 0.3
            model.moveLoop(original.id, originalStart: original.start, originalEnd: original.end, by: delta, tolerance: 0.5)
            let start = try XCTUnwrap(model.loops.selected).start
            XCTAssertGreaterThan(start, lastStart, "The loop stopped following the pointer at step \(step)")
            lastStart = start
        }
        // Released, the playhead is a target again: the next drag can snap to where it sits.
        model.endLoopDrag()
        let parked = model.position
        let second = try XCTUnwrap(model.loops.selected)
        model.beginLoopDrag(second.id)
        model.moveLoop(second.id, originalStart: second.start, originalEnd: second.end, by: 3, tolerance: 0.5)
        XCTAssertEqual(try XCTUnwrap(model.loops.selected).start, parked + 3, accuracy: 0.000001)
        model.endLoopDrag()
    }
}
