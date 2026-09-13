import SwiftUI
import CropTrimmerCore

/// A queue entry can be edited without changing which loop is playing.
struct QueueLoopCard: View {
    @ObservedObject var model: EditorModel
    let loop: MovieLoop
    let number: Int
    @State private var showAdvanced = false
    @State private var cropRevision = UUID()
    @State private var timeRevision = UUID()

    private var selected: Bool { model.loops.selectedID == loop.id }
    private var edit: EditSettings { model.loops.ranges.first { $0.id == loop.id }?.settings ?? loop.settings }
    private var locked: Bool { edit.cropAspectRatio != nil && edit.cropAspectRatio != .free }
    private var adjusting: Bool { selected && model.cropAdjusting }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            timeRow
            cropRow
            if edit.cropEnabled {
                cropControls
                exportOptions
            } else {
                Text("Trim only · \(edit.method.rawValue)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                DisclosureGroup("Advanced export options", isExpanded: $showAdvanced) {
                    exportOptions.padding(.top, 5)
                }.font(.system(size: 10))
            }
            ForEach((model.queueInputErrors[loop.id] ?? [:]).keys.sorted(), id: \.self) { key in
                Text(model.queueInputErrors[loop.id]?[key] ?? "")
                    .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            outputDetails
            footer
        }
        .font(.system(size: 11)).controlSize(.mini).padding(8)
        .background(selected ? Color.yellow.opacity(0.15) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.yellow.opacity(0.35) : .clear))
        .disabled(model.isBusy || model.source == nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loop \(number)" + (selected ? ", selected" : ""))
        .contextMenu { Button("Set loop to whole movie", action: resetRange) }
    }

    private var timeRow: some View {
        HStack(spacing: 4) {
            Button { model.selectLoop(loop.id) } label: {
                Text(String(format: "Loop %02d", number)).fontWeight(.semibold).fixedSize()
            }.buttonStyle(.plain).help("Preview Loop \(number)")
                .accessibilityLabel("Select queue Loop \(number)")
            timeField("Start", label: "A", start: true)
            timeField("End", label: "B", start: false)
            HStack(spacing: 2) {
                Text("D").foregroundStyle(.secondary)
                Text(queueSeconds(edit.duration)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            }.help("Duration in seconds").accessibilityLabel("Duration \(queueSeconds(edit.duration)) seconds")
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

    private var cropRow: some View {
        HStack(spacing: 6) {
            Toggle("Crop", isOn: Binding(get: { edit.cropEnabled }, set: { enabled in
                update { $0.cropEnabled = enabled }
                if !enabled {
                    clearCropDrafts()
                    if adjusting { model.doneCrop() }
                }
            })).toggleStyle(.checkbox)
            Spacer(minLength: 0)
            if edit.cropEnabled {
                Button(adjusting ? "Done" : "Adjust") {
                    if adjusting { model.doneCrop() }
                    else { model.selectLoop(loop.id, seekToStart: false); model.beginCrop() }
                }.help("Adjust Loop \(number)'s crop in the preview")
                Button("Reset", action: resetCrop)
            }
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
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("Crop dimensions \(edit.crop.width) by \(edit.crop.height) pixels")
                .help("Source pixels; drag crop corners to resize")
        }.font(.system(size: 10))
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

    private var exportOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Picker("Method", selection: setting(\.method)) {
                    ForEach(ExportMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Loop \(number) export method")
                Picker("Quality", selection: setting(\.quality)) {
                    ForEach(Quality.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Loop \(number) encoding quality")
                    .disabled(!edit.cropEnabled && edit.method == .fast)
            }

        }
    }

    @ViewBuilder private var outputDetails: some View {
        if let source = model.source {
            DisclosureGroup("Output details") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source: \(source.videoCodec), \(source.audioCount) audio track(s), \(source.subtitleCount) subtitle track(s).")
                    Text("Fast trim copies video and all audio tracks. Re-encoding uses H.264 video and the first audio track as AAC.")
                    Text("Subtitles, chapters and attachments are not retained. Automatic trim may re-encode when clean stream copying is unavailable.")
                    Text("Size estimates sample this loop; the final size can differ with motion and detail.")
                    if let restriction = source.encodingRestriction { Text(restriction).foregroundStyle(.orange) }
                }.font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
            }.font(.system(size: 10))
            if source.subtitleCount > 0 || (source.audioCount > 1 && (edit.cropEnabled || edit.method != .fast)) {
                Text("Some tracks may be omitted; see output details.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let source = model.source {
                let proposed = model.queuePlans[loop.id]
                let filename = OutputPublisher.baseName(sourceURL: source.url, cropped: edit.cropEnabled,
                    trimmed: edit.start > 0.001 || edit.end < source.duration - 0.001, loopNumber: number)
                    + "." + (proposed?.fileExtension ?? "mp4")
                Text(filename).font(.system(size: 10)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("Planned output filename. An extra number is added if it already exists.")
                if let proposed {
                    Text(proposed.method == .copy
                         ? "\(source.videoCodec.uppercased()) · stream copy planned"
                         : "H.264 · \(edit.quality.rawValue) · \(source.audioCount > 0 ? "AAC audio" : "no audio")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    if proposed.method == .copy {
                        let bytes = Int64(Double(source.identity.size) * proposed.duration / source.duration)
                        Text("Estimated size ≈ \(byteLabel(bytes))")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .help("Quick estimate from source size and planned duration; final size can differ.")
                    } else {
                        HStack {
                            Text(model.queueEstimates[loop.id]?[edit.quality].map { "Estimated size ≈ " + byteLabel($0) } ?? "Size not estimated")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer(minLength: 2)
                            Button(model.queueEstimates[loop.id] == nil ? "Estimate" : "Refresh") { model.estimateLoop(loop.id) }
                                .disabled(model.hasErrors(for: loop.id) || model.cropAdjusting)
                                .help("Sample this loop to estimate encoded file size")
                        }
                    }
                } else if let error = model.queuePlanErrors[loop.id] {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                } else {
                    Text("Checking output encoding and size…").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button { model.exportLoop(loop.id) } label: {
                Label("Export Loop \(number)", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }.disabled(model.hasErrors(for: loop.id) || model.cropAdjusting)
        }
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
