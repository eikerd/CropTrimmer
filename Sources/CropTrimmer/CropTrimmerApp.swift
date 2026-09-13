import AppKit
import SwiftUI
import CropTrimmerCore

@main
struct CropTrimmerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = EditorModel()
    var body: some Scene {
        Window("Crop Trimmer", id: "editor") {
            EditorView(model: model)
                .frame(minWidth: 820, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear { delegate.model = model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
                .onOpenURL { model.open($0) }
                .alert("Crop Trimmer", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK", role: .cancel) { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
        .defaultSize(width: 1160, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Movie…", action: model.openPanel).keyboardShortcut("o", modifiers: .command).disabled(model.isBusy)
            }
            CommandMenu("Movie") {
                Button("Play / Pause", action: model.togglePlayback).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Stop", action: model.stop).disabled(model.source == nil || model.isBusy || model.showReview)
                Divider()
                Button("Set Start (I)", action: model.setStart).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Set End (O)", action: model.setEnd).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Go to Start", action: model.recallStart).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Go to End", action: model.recallEnd).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Reset Range", action: model.resetRange).disabled(model.source == nil || model.isBusy || model.showReview)
                Divider()
                ForEach(Array(model.loops.ranges.enumerated()), id: \.element.id) { index, loop in
                    Button("Select Loop \(index + 1)") { model.selectLoop(loop.id) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(model.isBusy || model.showReview)
                }
                Button("Add Loop", action: model.addLoop).disabled(model.source == nil || model.isBusy || model.showReview || model.loops.ranges.count >= MovieLoops.maximumCount)
                Button("Remove Selected Loop", action: model.removeLoop).disabled(model.isBusy || model.showReview || model.loops.ranges.count < 2)
                Divider()
                Button("Adjust Crop", action: model.beginCrop).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Export Selected Loop", action: model.export).keyboardShortcut("e", modifiers: .command).disabled(model.plan == nil || model.isBusy || model.showReview || model.cropAdjusting || model.hasInputErrors)
                Button("Export Queue", action: model.exportQueue).disabled(model.source == nil || model.isBusy || model.showReview || model.cropAdjusting || model.hasInputErrors)
                Button("Show Exports") { model.showReview = true }.disabled(model.results.isEmpty || model.isBusy)
            }
            CommandGroup(replacing: .help) {
                Button("Crop Trimmer Help") {
                    let alert = NSAlert()
                    alert.messageText = "Trim the time. Crop the picture."
                    alert.informativeText = "Drop a movie or press ⌘O. Add up to three loops with + and choose 5s or 10s presets. Drag a yellow header to move a whole loop; drag A to reposition it with the same length, or B to resize it. The filmstrip below scrubs independently. Playback uses the selected loop. Select a Queue entry to change its own crop and export settings. Export one loop or the whole queue, with sequential loop numbers in filenames. Click A or B to recall an endpoint; Shift-click to store it. I and O set endpoints; Space plays or pauses. Previous and Next select adjacent loops, preserving playback state. Transport buttons finish crop adjustment; five-second jumps pause and seek. Crop selects source pixels and requires encoding. Exports are saved beside the original with a unique appended name. The original is never overwritten."
                    alert.runModal()
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var model: EditorModel? {
        didSet { for window in NSApp.windows where window.canBecomeMain { window.delegate = self } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isBusy else { model?.shutdown(); return .terminateNow }
        let alert = NSAlert(); alert.messageText = "An operation is still running"
        alert.informativeText = "Keep working, or cancel the operation and quit. Your original movie is unchanged."
        alert.addButton(withTitle: "Keep Working"); alert.addButton(withTitle: "Cancel and Quit")
        if alert.runModal() == .alertSecondButtonReturn {
            model.cancel()
            Task { @MainActor in
                while model.isBusy { try? await Task.sleep(for: .milliseconds(100)) }
                model.shutdown(); NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateCancel
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model?.isBusy == true else { return true }
        NSApp.terminate(nil); return false
    }
}
