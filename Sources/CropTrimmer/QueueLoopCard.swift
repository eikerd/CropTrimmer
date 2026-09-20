import SwiftUI
import CropTrimmerCore

/// A queue entry can be edited without changing which loop is playing. It is laid out flat and
/// always expanded — color correction, crop, export — with the explanatory text in tooltips on the
/// controls it describes rather than in its own block.
struct QueueLoopCard: View {
    @ObservedObject var model: EditorModel
    let loop: MovieLoop
    let number: Int
    @State private var cropRevision = UUID()
    @State private var timeRevision = UUID()

    private var selected: Bool { model.loops.selectedID == loop.id }
    private var edit: EditSettings { model.loops.ranges.first { $0.id == loop.id }?.settings ?? loop.settings }
    private var locked: Bool { edit.cropAspectRatio != nil && edit.cropAspectRatio != .free }
    private var adjusting: Bool { selected && model.cropAdjusting }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            timeRow
            speedRow
            ColorControlsView(model: model, loopID: loop.id, number: number)
            cropSection
            exportSection
            ForEach((model.queueInputErrors[loop.id] ?? [:]).keys.sorted(), id: \.self) { key in
                Text(model.queueInputErrors[loop.id]?[key] ?? "")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 12))
        .modifier(LoopPanel(selected: selected, colorIndex: loop.colorIndex))
        .disabled(model.isBusy || model.source == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loop \(number)" + (selected ? ", selected" : ""))
        .contextMenu {
            Button("Set loop to whole movie", action: resetRange)
            Button("Delete Loop \(number)", systemImage: "trash", role: .destructive) { model.removeLoop(loop.id) }
        }
    }

    private var timeRow: some View {
        HStack(spacing: 4) {
            LoopColorSwatch(colorIndex: loop.colorIndex, number: number) { model.setLoopColor(loop.id, to: $0) }
            Button { model.selectLoop(loop.id) } label: {
                Text(String(format: "Loop %02d", number)).fontWeight(.semibold).fixedSize()
            }.buttonStyle(.plain).help("Preview Loop \(number)")
                .accessibilityLabel("Select queue Loop \(number)")
            timeField("Start", label: "A", start: true)
            timeField("End", label: "B", start: false)
            HStack(spacing: 2) {
                Text("D").foregroundStyle(.secondary)
                Text(queueSeconds(edit.duration)).monospacedDigit().lineLimit(1)
            }.help("Duration in seconds").accessibilityLabel("Duration \(queueSeconds(edit.duration)) seconds")
            Button { model.removeLoop(loop.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Delete Loop \(number)").accessibilityLabel("Delete Loop \(number)")
        }
    }

    /// The loop's own speed: the same number the preview plays at and the export renders at.
    private var speedRow: some View {
        HStack(spacing: 4) {
            Text("Speed").foregroundStyle(.secondary)
            Picker("Speed", selection: Binding(get: { edit.speed }, set: { value in update { $0.speed = value } })) {
                ForEach(EditSettings.speeds, id: \.self) { Text(EditSettings.speedLabel($0)).tag($0) }
            }.labelsHidden().fixedSize()
                .accessibilityLabel("Loop \(number) speed")
                .help("Plays and renders Loop \(number) at this speed. The export runs \(queueSeconds(edit.outputDuration))s.")
            Spacer(minLength: 0)
        }
    }

    private func timeField(_ title: String, label: String, start: Bool) -> some View {
        HStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            TimeInput(title: title, value: Binding(get: { start ? edit.start : edit.end }, set: { value in
                update { if start { $0.start = value } else { $0.end = value } }
            }), error: errorBinding(title)) { proposed in
                guard let source = model.source, proposed >= 0, proposed <= source.duration else { return "\(title) must be within the movie." }
                guard start ? proposed < edit.end : proposed > edit.start else { return "Start must be before end." }
                return nil
            }.id(timeRevision).frame(minWidth: 35, maxWidth: .infinity)
                .accessibilityLabel("Loop \(number) \(title) in seconds")
        }
    }

    private var cropSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Toggle("Crop", isOn: Binding(get: { edit.cropEnabled }, set: { enabled in
                    update { $0.cropEnabled = enabled }
                    if !enabled {
                        clearCropDrafts()
                        if adjusting { model.doneCrop() }
                    }
                })).toggleStyle(.checkbox)
                    .help("Crop selects source pixels and always re-encodes.")
                Spacer(minLength: 0)
                if edit.cropEnabled {
                    Button(adjusting ? "Done" : "Adjust") {
                        if adjusting { model.doneCrop() }
                        else { model.selectLoop(loop.id, seekToStart: false); model.beginCrop() }
                    }.help("Adjust Loop \(number)'s crop in the preview")
                    Button("Reset", action: resetCrop)
                }
            }
            if edit.cropEnabled { cropControls }
        }
    }

    private var cropControls: some View {
        HStack(spacing: 3) {
            Picker("Aspect ratio", selection: Binding(get: { edit.cropAspectRatio ?? .free }, set: setAspect)) {
                ForEach(CropAspectRatio.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 60).accessibilityLabel("Loop \(number) aspect ratio")
            coordinate("X", \.x)
            coordinate("Y", \.y)
            Button { setAspect(locked ? .free : (edit.lastLockedCropAspectRatio ?? .original)) } label: {
                Image(systemName: locked ? "lock.fill" : "lock.open")
                    .frame(width: 14, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).help(locked ? "Unlock proportions" : "Lock proportions")
                .accessibilityLabel("Loop \(number): " + (locked ? "Unlock crop aspect ratio" : "Lock crop aspect ratio"))
            Text("\(edit.crop.width) × \(edit.crop.height)")
                .monospacedDigit().lineLimit(1).fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Crop dimensions \(edit.crop.width) by \(edit.crop.height) pixels")
                .help("Source pixels; drag crop corners to resize")
        }
    }

    private func coordinate(_ title: String, _ key: WritableKeyPath<PixelRect, Int>) -> some View {
        HStack(spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            CropInput(title: title, value: edit.crop[keyPath: key], error: errorBinding("Crop " + title)) { value in
                guard let source = model.source else { return "Open a movie first." }
                var next = edit
                next.crop[keyPath: key] = value
                guard next.crop == next.crop.constrained(toWidth: source.width, height: source.height) else {
                    return "Crop \(title): use even pixel values inside the source picture."
                }
                return model.updateLoop(id: loop.id, settings: next)
            }.id(cropRevision).frame(minWidth: 24, maxWidth: 35)
                .accessibilityLabel("Loop \(number) crop \(title)")
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Picker("Method", selection: setting(\.method)) {
                    ForEach(ExportMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().help(methodHelp).accessibilityLabel("Loop \(number) export method")
                Picker("Quality", selection: setting(\.quality)) {
                    ForEach(Quality.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().help(qualityHelp).accessibilityLabel("Loop \(number) encoding quality")
                    .disabled(!edit.cropEnabled && edit.color.isIdentity && edit.method == .fast)
            }
            HStack(spacing: 5) {
                if let size = sizeLabel {
                    Text(size).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                        .help("Estimates sample this loop; the final size can differ with motion and detail.")
                }
                Spacer(minLength: 0)
                if model.queuePlans[loop.id]?.method == .encode {
                    Button(model.queueEstimates[loop.id] == nil ? "Estimate" : "Refresh") { model.estimateLoop(loop.id) }
                        .disabled(model.hasErrors(for: loop.id) || model.cropAdjusting)
                        .help("Sample this loop to estimate its encoded file size")
                }
                Button { model.exportLoop(loop.id) } label: { Label("Export Loop \(number)", systemImage: "square.and.arrow.up") }
                    .disabled(model.hasErrors(for: loop.id) || model.cropAdjusting)
                    .help(exportHelp)
            }
            if let error = model.queuePlanErrors[loop.id] {
                Text(error).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The size beside the Export button: the quick source-size estimate for a stream copy, the sampled
    /// estimate for an encode once it exists, or "Checking…" while the plan is still being made.
    private var sizeLabel: String? {
        guard let source = model.source else { return nil }
        guard let plan = model.queuePlans[loop.id] else { return model.queuePlanErrors[loop.id] == nil ? "Checking…" : nil }
        if plan.method == .copy {
            return "≈ " + byteLabel(Int64(Double(source.identity.size) * plan.duration / source.duration))
        }
        return model.queueEstimates[loop.id]?[edit.quality].map { "≈ " + byteLabel($0) }
    }

    /// What the chosen method means, what is planned right now, and what this movie loses on re-encode.
    private var methodHelp: String {
        var lines: [String]
        switch edit.method {
        case .automatic: lines = ["Automatic: copies the streams when the planned boundaries land within 0.25 s of A and B, otherwise re-encodes."]
        case .fast: lines = ["Fast trim: copies video and every audio track without re-encoding; boundaries move to nearby keyframes, and the export fails rather than re-encoding if the copy cannot be verified."]
        case .accurate: lines = ["Accurate trim: re-encodes for frame-exact boundaries."]
        }
        if edit.cropEnabled { lines.append("Crop always re-encodes.") }
        else if !edit.color.isIdentity { lines.append("Color correction always re-encodes.") }
        lines.append("Re-encoding writes H.264 video and the first audio track as AAC; subtitles, chapters and attachments are not kept.")
        if let source = model.source {
            if let plan = model.queuePlans[loop.id] {
                lines.append(plan.method == .copy ? "Planned now: \(source.videoCodec.uppercased()) stream copy."
                                                  : "Planned now: H.264 · \(edit.quality.rawValue) · \(source.audioCount > 0 ? "AAC audio" : "no audio").")
            }
            if source.audioCount > 1 || source.subtitleCount > 0 {
                lines.append("This movie has \(source.audioCount) audio and \(source.subtitleCount) subtitle track(s); only the first audio track survives a re-encode.")
            }
            if let restriction = source.encodingRestriction { lines.append(restriction) }
        }
        return lines.joined(separator: "\n")
    }

    private var qualityHelp: String {
        "\(edit.quality.rawValue): software H.264 at CRF \(edit.quality.crf) with AAC audio at 192 kb/s. Applies only when the export re-encodes."
    }

    private var exportHelp: String {
        guard let source = model.source else { return "" }
        let filename = OutputPublisher.baseName(sourceURL: source.url, cropped: edit.cropEnabled,
            trimmed: edit.start > 0.001 || edit.end < source.duration - 0.001, loopNumber: number)
            + "." + (model.queuePlans[loop.id]?.fileExtension ?? "mp4")
        return "Saves \(filename) beside the original. An extra number is added if that name exists."
    }

    private func errorBinding(_ key: String) -> Binding<String?> {
        Binding(get: { model.queueInputErrors[loop.id]?[key] }, set: { value in
            var errors = model.queueInputErrors[loop.id] ?? [:]
            errors[key] = value
            model.queueInputErrors[loop.id] = errors.isEmpty ? nil : errors
        })
    }

    private func setting<Value>(_ key: WritableKeyPath<EditSettings, Value>) -> Binding<Value> {
        Binding(get: { edit[keyPath: key] }, set: { value in update { $0[keyPath: key] = value } })
    }

    private func update(_ change: (inout EditSettings) -> Void) {
        var next = edit
        change(&next)
        let reason = model.updateLoop(id: loop.id, settings: next)
        errorBinding("Settings").wrappedValue = reason
    }

    private func setAspect(_ aspect: CropAspectRatio) {
        guard let source = model.source else { return }
        update {
            $0.cropAspectRatio = aspect
            if aspect != .free { $0.lastLockedCropAspectRatio = aspect }
            $0.crop = CropGeometry.fitted($0.crop, aspect: aspect, sourceWidth: source.width, sourceHeight: source.height)
        }
        clearCropDrafts()
    }

    private func resetRange() {
        guard let source = model.source else { return }
        update { $0.start = 0; $0.end = source.duration }
        errorBinding("Start").wrappedValue = nil
        errorBinding("End").wrappedValue = nil
        timeRevision = UUID()
    }

    private func resetCrop() {
        guard let source = model.source else { return }
        update {
            $0.crop = CropGeometry.fitted(PixelRect(width: source.width, height: source.height), aspect: $0.cropAspectRatio ?? .free,
                                        sourceWidth: source.width, sourceHeight: source.height)
        }
        clearCropDrafts()
    }

    private func clearCropDrafts() {
        errorBinding("Crop X").wrappedValue = nil
        errorBinding("Crop Y").wrappedValue = nil
        cropRevision = UUID()
    }
}

/// Each loop sits on a panel tinted in its own color, like an Ableton clip; the selected loop's
/// tint is stronger and outlined in the same color.
struct LoopPanel: ViewModifier {
    static let spacing: CGFloat = 10
    let selected: Bool
    let colorIndex: Int
    func body(content: Content) -> some View {
        content.padding(.horizontal, 8).padding(.vertical, 10)
            .background(LoopColors.fill(colorIndex).opacity(selected ? 0.26 : 0.14), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? LoopColors.onDark(colorIndex) : Color.clear, lineWidth: 1.5))
    }
}
