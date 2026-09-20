import AppKit
import SwiftUI
import CropTrimmerCore

@main
struct CropTrimmerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = EditorModel()
    @Environment(\.openSettings) private var openSettings
    var body: some Scene {
        Window("Crop Trimmer", id: "editor") {
            EditorView(model: model)
                .frame(minWidth: 820, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.model = model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
                    model.openPreferences = { openSettings() }
                }
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
                Button("Set Start (I)", action: model.setStart).keyboardShortcut("i", modifiers: .command).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Set End (O)", action: model.setEnd).keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Go to Start", action: model.recallStart).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Go to End", action: model.recallEnd).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Reset Range", action: model.resetRange).disabled(model.source == nil || model.isBusy || model.showReview || model.loops.ranges.isEmpty)
                Divider()
                ForEach(Array(model.loops.ranges.enumerated()), id: \.element.id) { index, loop in
                    let number = index + 1
                    // ⌘1…⌘9 only: KeyEquivalent takes one Character, and Character("10") traps.
                    // Loops past the ninth are selected from the timeline or the queue.
                    Button("Select Loop \(number)") { model.selectLoop(loop.id) }
                        .modifier(OptionalDigitShortcut(number: number))
                        .disabled(model.isBusy || model.showReview)
                }
                Button("Add Loop", action: model.addLoop).disabled(model.source == nil || model.isBusy || model.showReview)
                Button("Remove Selected Loop", action: model.removeLoop).disabled(model.isBusy || model.showReview || model.loops.ranges.isEmpty)
                Divider()
                Button("Adjust Crop", action: model.beginCrop).disabled(model.source == nil || model.isBusy || model.showReview || model.loops.ranges.isEmpty)
                Button("Export Selected Loop", action: model.export).keyboardShortcut("e", modifiers: .command).disabled(model.plan == nil || model.isBusy || model.showReview || model.cropAdjusting || model.loops.selectedID.map(model.hasErrors(for:)) ?? true)
                Button("Export Queue", action: model.exportQueue).disabled(model.source == nil || model.isBusy || model.showReview || model.cropAdjusting || model.hasInputErrors || model.loops.ranges.isEmpty)
                Button("Show Exports") { model.showReview = true }.disabled(model.results.isEmpty || model.isBusy)
            }
            CommandGroup(replacing: .help) {
                Button("Crop Trimmer Help") {
                    let alert = NSAlert()
                    alert.messageText = "Trim the time. Crop the picture."
                    alert.informativeText = "Drop a movie or press ⌘O. A movie opens with no loops and plays whole. The first + (or I) starts a loop at the playhead; every later + starts one at the selected loop's B point, stair-stepping down the timeline with no limit on how many. 5s/10s set the length. Delete loops with the trash buttons, the last one included. Each loop has its own color in the queue and on the timeline; click its swatch to change it. Drag a loop's header to move the whole loop; drag A to change where it starts, or B to change where it ends. The playhead follows A, or shows the last frame while B is dragged. The filmstrip below scrubs independently. The mode button cycles A–B repeat, play once, play all loops and whole movie, and the speed menu beside it sets the selected loop's own speed, 0.1× to 8×, which is both previewed and rendered into that loop's export. Dragging a loop or its A/B handles snaps to the other loops' edges, the playhead and the movie's ends, marked by a dashed guide. Playback uses the selected loop and keeps going through edits and file changes. Select a Queue entry to change its own crop and export settings. Export one loop or the whole queue, with sequential loop numbers in filenames. Click A or B to recall an endpoint; Shift-click to store it. I and O set endpoints; Space plays or pauses. Previous and Next select adjacent loops, preserving playback state. Transport buttons finish crop adjustment; Stop, frame stepping, export and crop adjustment pause playback. Crop selects source pixels and requires encoding. Exports are saved beside the original with a unique appended name. The original is never overwritten."
                    alert.runModal()
                }
                Button("Keyboard Shortcuts…") { model.preferencesTab = .shortcuts; openSettings() }
            }
        }
        Settings {
            PreferencesView(model: model)
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

/// ⌘1…⌘9 for the first nine loops and nothing for the rest, so an uncapped queue cannot reach
/// `KeyEquivalent(Character("10"))`, which traps on a multi-character string.
private struct OptionalDigitShortcut: ViewModifier {
    let number: Int
    func body(content: Content) -> some View {
        if (1...9).contains(number), let digit = String(number).first {
            content.keyboardShortcut(KeyEquivalent(digit), modifiers: .command)
        } else {
            content
        }
    }
}
