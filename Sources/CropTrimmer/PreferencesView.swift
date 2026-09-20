import AppKit
import SwiftUI
import CropTrimmerCore

/// The app's Settings window (⌘,): General preferences, which operations name an export, and a
/// reference list of every shortcut.
struct PreferencesView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        TabView(selection: $model.preferencesTab) {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(EditorModel.PreferencesTab.general)
            ColorSettingsView(model: model)
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(EditorModel.PreferencesTab.ai)
            FilenameSettingsView(model: model)
                .tabItem { Label("File Names", systemImage: "textformat") }
                .tag(EditorModel.PreferencesTab.filenames)
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(EditorModel.PreferencesTab.shortcuts)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.preferencesIsOpen = true }
        .onDisappear { model.preferencesIsOpen = false }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Form {
            Section {
                Picker("New loops default to", selection: $model.defaultLoopLength) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }.pickerStyle(.radioGroup)
                    .help("The length of a loop added with +. The transport's 5s/10s buttons also change this for the rest of the session.")
            } header: { Text("Loops") }

            Section {
                HStack {
                    Text("Default size")
                    Spacer()
                    // No placeholder: a Form gives a TextField's title its own label column, and
                    // "Width"/"Height" wrapped to two lines beside the value. The row already
                    // says what these are, and the accessibility labels carry it for VoiceOver.
                    TextField("", value: $model.defaultCropWidth, format: .number)
                        .labelsHidden().frame(width: 64).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Default crop width in pixels")
                    Text("×").foregroundStyle(.secondary)
                    TextField("", value: $model.defaultCropHeight, format: .number)
                        .labelsHidden().frame(width: 64).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Default crop height in pixels")
                }
            } header: { Text("Crop") } footer: {
                Text("The size a new crop starts at. Colour and naming models live on the AI page.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

/// Which operations name an export. Every toggle changes the sample underneath as it is flipped,
/// so the effect is read rather than guessed.
private struct FilenameSettingsView: View {
    @ObservedObject var model: EditorModel

    private var sample: String {
        OutputPublisher.baseName(
            sourceURL: URL(fileURLWithPath: "/Movies/Holiday.mp4"),
            cropped: true, trimmed: true, loopNumber: 2, speed: 0.5,
            options: model.filenameOptions
        ) + ".mp4"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Loop number", isOn: $model.filenameOptions.includeLoopNumber)
                Toggle("Trim", isOn: $model.filenameOptions.includeTrim)
                Toggle("Crop", isOn: $model.filenameOptions.includeCrop)
                Toggle("Speed", isOn: $model.filenameOptions.includeSpeed)
                VisionModelPicker(title: "Naming model", selection: $model.filenameModel)
                    .help("The OpenRouter model that describes a frame when you ask for a suggested name.")
            } header: {
                Text("Name exports after")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A part appears only when the export actually used it.")
                    HStack(spacing: 6) {
                        Text("Example").foregroundStyle(.secondary)
                        Text(sample).monospaced()
                    }
                    Text("Exports are saved beside the original. A number is appended if that name is taken, so the original is never replaced.")
                        .foregroundStyle(.secondary)
                }.font(.system(size: 12))
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct ShortcutRow: Identifiable {
    let id = UUID()
    let keys: String
    let action: String
}

private struct ShortcutGroup: Identifiable {
    let id = UUID()
    let title: String
    let rows: [ShortcutRow]
}

private struct ShortcutsSettingsView: View {
    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Playback", rows: [
            ShortcutRow(keys: "Space", action: "Play / Pause"),
            ShortcutRow(keys: "← / →", action: "Move the playhead 1 second"),
            ShortcutRow(keys: "⇧ + ← / →", action: "Move the playhead 5 seconds"),
            ShortcutRow(keys: "⌥ + ← / →", action: "Move the playhead 0.2 seconds"),
        ]),
        ShortcutGroup(title: "Trim points", rows: [
            ShortcutRow(keys: "I  /  ⌘I", action: "Set the start (A) to the playhead — with no loop yet, starts one there"),
            ShortcutRow(keys: "O  /  ⌘⇧O", action: "Set the end (B) to the playhead"),
            ShortcutRow(keys: "Click A / B", action: "Recall that point"),
            ShortcutRow(keys: "⇧-click A / B", action: "Store the playhead there"),
        ]),
        ShortcutGroup(title: "Loops", rows: [
            ShortcutRow(keys: "⌘1 … ⌘9", action: "Select that loop (the first nine; the rest from the timeline or queue)"),
            ShortcutRow(keys: "← / → (header)", action: "Move a focused loop header 0.1 second"),
            ShortcutRow(keys: "⇧ + ← / → (header)", action: "Move a focused loop header 1 second"),
            ShortcutRow(keys: "⌫ (header)", action: "Delete a focused loop"),
        ]),
        ShortcutGroup(title: "File", rows: [
            ShortcutRow(keys: "⌘O", action: "Open Movie"),
            ShortcutRow(keys: "⌘E", action: "Export Selected Loop"),
            ShortcutRow(keys: "⌘,", action: "Settings"),
        ]),
        ShortcutGroup(title: "Help", rows: [
            ShortcutRow(keys: "?", action: "Show this list"),
        ]),
    ]

    var body: some View {
        Form {
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        LabeledContent {
                            Text(row.action)
                        } label: {
                            Text(row.keys).monospaced().frame(width: 140, alignment: .leading)
                        }
                    }
                } header: { Text(group.title) }
            }
            Text("A loop header must have keyboard focus (click it once) for its own arrow-key and Delete shortcuts to apply; otherwise the arrow keys move the playhead.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
