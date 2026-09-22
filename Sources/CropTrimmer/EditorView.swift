import SwiftUI
import AVKit
import UniformTypeIdentifiers
import CropTrimmerCore

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var editingFilename = false
    @State private var filenameDraft = ""
    @State private var filenamePlayground = ""
    @State private var filenameTask: Task<Void, Never>?
    @State private var filenameRequestID: UUID?
    @State private var colorTool: ColorTool = .auto
    @State private var referenceUsesModel = false
    @Environment(\.openSettings) private var openSettings
    @FocusState private var filenameFocused: Bool

    private enum ColorTool: String, CaseIterable {
        case auto = "Auto", reference = "Reference", looks = "Looks"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    viewer
                    Divider()
                    transport.padding(12)
                    Divider()
                    timeline.padding(16)
                }.frame(maxWidth: .infinity)
                Divider()
                inspector.frame(width: 302)
            }
            Divider()
            HStack {
                if model.isBusy { ProgressView(value: model.progress).frame(width: 100) }
                Text(model.status).lineLimit(2).font(.system(size: 12)).textSelection(.enabled)
                Spacer()
                if let source = model.source { Text("\(source.width) × \(source.height) · \(timeLabel(source.duration))").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary) }
            }.padding(.horizontal, 12).frame(minHeight: 32)
        }
        .background(Color(red: 0.105, green: 0.105, blue: 0.115))
        .preferredColorScheme(.dark)
        .onChange(of: model.source?.id) { _, _ in cancelFilenameEdit() }
        .onDisappear { cancelFilenameEdit() }
        .toolbar {
            ToolbarItem { Button(action: model.openPanel) { Label("Open Movie", systemImage: "folder") }.disabled(model.isBusy) }
            ToolbarItem { Text(model.source?.url.lastPathComponent ?? "Crop Trimmer").lineLimit(1)
                .help(model.source.map { "Double-click to rename · " + $0.url.path } ?? "Open a movie to begin")
                .onTapGesture(count: 2, perform: beginFilenameEdit) }
            ToolbarItem { Button { model.showReview = true } label: { Label("Exports (\(model.results.count))", systemImage: "square.stack") }.disabled(model.results.isEmpty) }
            ToolbarItem { Button { openSettings() } label: { Label("Settings", systemImage: "gearshape") }.help("Settings (⌘,)") }
        }
        .sheet(isPresented: $model.showReview) { ReviewView(model: model) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard !model.isBusy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.open(url) }
            }
            return true
        }
    }

    @ViewBuilder private var viewer: some View {
        if let source = model.source {
            GeometryReader { proxy in
                let cropped = model.settings.cropEnabled && !model.cropAdjusting
                let crop = model.settings.crop
                // The loop's turned picture; the crop and its overlay are measured on it.
                let picture = model.settings.pictureSize(of: source)
                let width = CGFloat(cropped ? crop.width : picture.width)
                let height = CGFloat(cropped ? crop.height : picture.height)
                let scale = min(proxy.size.width / width, proxy.size.height / height)
                ZStack {
                    Color.black
                    ZStack(alignment: .topLeading) {
                        PlayerSurface(player: model.player, rotation: model.settings.rotation)
                            .frame(width: CGFloat(picture.width) * scale, height: CGFloat(picture.height) * scale)
                            .offset(x: cropped ? -CGFloat(crop.x) * scale : 0, y: cropped ? -CGFloat(crop.y) * scale : 0)
                    }.frame(width: width * scale, height: height * scale, alignment: .topLeading).clipped()
                    if model.cropAdjusting {
                        CropOverlay(crop: $model.settings.crop, aspect: model.settings.cropAspectRatio ?? .free, sourceWidth: picture.width, sourceHeight: picture.height)
                            .frame(width: width * scale, height: height * scale).disabled(model.isBusy)
                    }
                }
            }.frame(minHeight: 230)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "film").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.secondary)
                Text("Keep the moment. Frame the action.").font(.title3)
                Text("Drop a movie here or open one to begin.").foregroundStyle(.secondary)
                Button("Open Movie…", action: model.openPanel).buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 230).background(.black)
        }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            transportButton("Back 5 seconds", "gobackward.5") { model.jump(-5) }
            transportButton("Previous loop", "backward.end") { model.selectAdjacentLoop(-1) }
                .disabled(!model.canSelectPreviousLoop)
            transportButton(model.isPlaying ? "Pause" : "Play", model.isPlaying ? "pause.fill" : "play.fill", action: model.togglePlayback)
            transportButton("Stop", "stop.fill", action: model.stop)
            transportButton("Next loop", "forward.end") { model.selectAdjacentLoop(1) }
                .disabled(!model.canSelectNextLoop)
            transportButton("Forward 5 seconds", "goforward.5") { model.jump(5) }
            playbackModeButton
            Picker("Playback speed", selection: Binding(get: { model.speed }, set: model.setSpeed)) {
                ForEach(EditSettings.speeds, id: \.self) { Text(EditSettings.speedLabel($0)).tag($0) }
            }.labelsHidden().fixedSize()
                .help(model.speedIsRendered
                      ? "Speed of Loop \(model.selectedLoopNumber) — previewed and rendered into its export"
                      : "Monitoring speed for the whole movie; nothing is rendered until a loop exists")
            Spacer(minLength: 8)
            // Fixed widths sum to under the 493 pt this row gets at the 820 pt minimum window; the timestamp
            // keeps its full width and the spacer absorbs any squeeze.
            Text(timeLabel(model.position)).font(.system(.body, design: .monospaced)).fixedSize().layoutPriority(1)
                .accessibilityLabel("Playhead \(timeLabel(model.position))")
            Button { model.muted.toggle() } label: { Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 24, height: 32).contentShape(Rectangle()) }
                .buttonStyle(.plain).help("Mute monitoring audio").padding(.leading, 6)
            Slider(value: $model.volume, in: 0...1).frame(width: 72).accessibilityLabel("Monitoring volume")
        }.disabled(model.source == nil || model.isBusy)
    }

    /// VLC-style loop button: each click cycles the mode, the icon shows the current one, right-click picks directly.
    private var playbackModeButton: some View {
        Button { model.playbackMode = model.playbackMode.next } label: {
            Image(systemName: modeSymbol(model.playbackMode)).frame(width: 32, height: 32).contentShape(Rectangle())
                .foregroundStyle(model.playbackMode == .repeatSelection ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .help("\(model.playbackMode.rawValue) — click for \(model.playbackMode.next.rawValue)")
        .accessibilityLabel("Playback mode").accessibilityValue(model.playbackMode.rawValue)
        .contextMenu {
            Picker("Playback", selection: $model.playbackMode) { ForEach(PlaybackMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline)
        }
    }

    private func modeSymbol(_ mode: PlaybackMode) -> String {
        switch mode {
        case .repeatSelection: "repeat"
        case .once: "arrow.right.to.line"
        case .allLoops: "play.square.stack"
        case .whole: "film"
        }
    }

    private func transportButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 32).contentShape(Rectangle()) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    /// Everything that is a control rather than an endpoint: the loop chips, add and delete, and
    /// the length presets. Centred between the A and B edges.
    private var loopControls: some View {
        HStack(spacing: 6) {
            if model.loops.ranges.isEmpty {
                Text("Whole movie").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(Array(model.loops.ranges.enumerated()), id: \.element.id) { index, loop in
                let isSelected = loop.id == model.loops.selectedID || model.playsAllLoops
                Button { model.selectLoop(loop.id) } label: {
                    Text(String(index + 1)).fontWeight(.semibold).frame(width: 18)
                        .foregroundStyle(isSelected ? LoopColors.text(on: loop.colorIndex) : LoopColors.onDark(loop.colorIndex))
                }
                .buttonStyle(.borderless).frame(width: 30, height: 24)
                .background(isSelected ? LoopColors.fill(loop.colorIndex) : LoopColors.fill(loop.colorIndex).opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                .accessibilityLabel("Select Loop \(index + 1)")
                .accessibilityValue(isSelected ? "Selected" : "")
                .help("Loop \(index + 1): \(timeLabel(loop.start)) – \(timeLabel(loop.end))" + (isSelected ? " · \(timeLabel(loop.duration)) selected" : ""))
            }
            Button(action: model.addLoop) { Image(systemName: "plus") }
                .help(model.loops.ranges.isEmpty ? "Add a \(Int(model.defaultLoopLength))-second loop starting at the playhead" : "Add a \(Int(model.defaultLoopLength))-second loop starting at the selected loop's B")
                .accessibilityLabel("Add loop")
            Button(action: model.removeLoop) { Image(systemName: "trash") }
                .disabled(model.loops.ranges.isEmpty)
                .help("Delete selected loop").accessibilityLabel("Delete selected loop")
            Button(action: model.playAllLoops) { Image(systemName: "play.square.stack") }
                .disabled(model.loops.ranges.isEmpty)
                .tint(model.playsAllLoops ? LoopColors.onDark(selectedColor) : .gray)
                .help("Play every loop in turn, each at its own speed, and nothing in between")
                .accessibilityLabel("Play all loops")
                .accessibilityValue(model.playsAllLoops ? "On" : "Off")
            Divider().frame(height: 16).padding(.horizontal, 2)
            ForEach([5, 10], id: \.self) { seconds in
                Button("\(seconds)s") { model.setLoopLength(Double(seconds)) }
                    .tint(abs(model.settings.duration - Double(seconds)) < 0.000001 ? LoopColors.onDark(selectedColor) : .gray)
                    .disabled(model.loops.ranges.isEmpty)
                    .help("Make this loop \(seconds) seconds; new loops also start at \(seconds) seconds")
                    .accessibilityLabel("Set loop length to \(seconds) seconds")
            }
        }
    }

    /// The selected loop's palette color, for everything that marks the selection.
    private var selectedColor: Int { model.loops.selected?.colorIndex ?? 0 }

    private var timeline: some View {
        VStack(spacing: 10) {
            // One row: A and its time hold the left edge, B and its time the right, and every
            // control sits in the middle. The two edge groups are the same width, so the centre
            // group really is centred.
            HStack(spacing: 6) {
                Button("A") { NSEvent.modifierFlags.contains(.shift) ? model.setStart() : model.recallStart() }
                    .help("Recall A · Shift-click to set A (I)")
                Text(timeLabel(model.settings.start)).monospacedDigit().font(.system(size: 12))
                Spacer(minLength: 8)
                loopControls
                Spacer(minLength: 8)
                Text(timeLabel(model.settings.end)).monospacedDigit().font(.system(size: 12))
                Button("B") { NSEvent.modifierFlags.contains(.shift) ? model.setEnd() : model.recallEnd() }
                    .help("Recall B · Shift-click to set B (O)")
            }
            Filmstrip(model: model).frame(height: CGFloat(max(1, model.loops.ranges.count)) * 24 + 66 + Filmstrip.markerBand).id(model.source?.id)
            HStack { Text("00:00.000"); Spacer(); Text("Header moves loop · Filmstrip scrubs"); Spacer(); Text(timeLabel(model.source?.duration ?? 0)) }.font(.system(size: 12)).foregroundStyle(.secondary)
        }.disabled(model.source == nil || model.isBusy)
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourceSection
                    Divider()
                    queueSection
                    Divider()
                    looksSection
                }.font(.system(size: 12)).padding(16)
            }.disabled(model.source == nil || model.isBusy)
            Divider()
            VStack(spacing: 8) {
                if model.isBusy { Button("Cancel", action: model.cancel).frame(maxWidth: .infinity) }
                else {
                    let blocked = model.source == nil || model.loops.ranges.isEmpty || model.cropAdjusting || model.hasInputErrors
                    HStack(spacing: 8) {
                        Button("Export Each (\(model.loops.ranges.count))", action: model.exportEach)
                            .frame(maxWidth: .infinity).controlSize(.large).disabled(blocked)
                            .help("One movie per loop, numbered in timeline order")
                        Button("Export All (\(model.loops.ranges.count))", action: model.exportAll)
                            .frame(maxWidth: .infinity).buttonStyle(.borderedProminent).controlSize(.large).disabled(blocked)
                            .help("Every loop chained end to end, in timeline order, as one movie")
                    }
                }
            }.padding(16)
        }.background(Color.white.opacity(0.035))
    }

    @ViewBuilder private var sourceSection: some View {
        if let source = model.source {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("SOURCE FILE", "film")
                if editingFilename {
                    HStack {
                        TextField("Filename", text: $filenameDraft)
                            .textFieldStyle(.roundedBorder).focused($filenameFocused)
                            .onSubmit(commitFilename)
                            .onExitCommand(perform: cancelFilenameEdit)
                        if !source.url.pathExtension.isEmpty {
                            Text("." + source.url.pathExtension).foregroundStyle(.secondary)
                        }
                    }
                    Text(filenamePlayground.isEmpty ? " " : filenamePlayground)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .accessibilityLabel(filenamePlayground.isEmpty ? "No sample name yet" : "Sample name: \(filenamePlayground)")
                    HStack(spacing: 8) {
                        Button(action: suggestFilename) { Image(systemName: "sparkles") }
                            .accessibilityLabel("Suggest a name with AI")
                            .help("Describe the frame with AI")
                            .disabled(filenameRequestID != nil)
                        VisionModelPicker(title: "Model", selection: $model.filenameModel)
                            .labelsHidden().frame(width: 150)
                        .disabled(filenameRequestID != nil)
                        Button {
                            filenameTask?.cancel(); filenameRequestID = nil
                            filenamePlayground = FilenameSuggestion.random()
                        } label: { Image(systemName: "die.face.5") }
                            .accessibilityLabel("Suggest a random name")
                            .help("Random name")
                        Spacer()
                        if filenameRequestID != nil {
                            ProgressView().controlSize(.small).accessibilityLabel("Suggesting filename")
                        }
                        Button { filenameDraft = filenamePlayground } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Use the sample name")
                        .help("Put the sample name in the field above")
                        .disabled(filenamePlayground.isEmpty)
                    }
                    Text("Renames the original file in its current folder.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button("Cancel", action: cancelFilenameEdit)
                        Spacer()
                        Button("Rename", action: commitFilename)
                            .disabled(filenameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    HStack(alignment: .top) {
                        Text(source.url.lastPathComponent).lineLimit(3).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            .onTapGesture(count: 2, perform: beginFilenameEdit)
                            .help("Double-click to rename " + source.url.lastPathComponent)
                        Button(action: beginFilenameEdit) { Image(systemName: "pencil") }
                            .accessibilityLabel("Rename source file")
                    }
                }
                Text("\(byteLabel(source.identity.size)) · \(source.videoCodec.uppercased())")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .accessibilityLabel("Original file: \(byteLabel(source.identity.size)), \(source.videoCodec) video")
            }
        }
    }

    private func beginFilenameEdit() {
        guard let source = model.source, !model.isBusy, !model.showReview else { return }
        model.pause()
        filenameDraft = source.url.deletingPathExtension().lastPathComponent
        filenamePlayground = ""
        editingFilename = true; filenameFocused = true
    }

    private func commitFilename() {
        if model.renameSource(to: filenameDraft) { cancelFilenameEdit() }
    }

    private func cancelFilenameEdit() {
        filenameTask?.cancel(); filenameTask = nil; filenameRequestID = nil
        filenamePlayground = ""
        editingFilename = false
    }

    private func suggestFilename() {
        let requestID = UUID()
        filenameRequestID = requestID
        filenameTask = Task { @MainActor in
            defer {
                if filenameRequestID == requestID { filenameRequestID = nil; filenameTask = nil }
            }
            do {
                let name = try await model.suggestFilename()
                guard !Task.isCancelled, filenameRequestID == requestID, editingFilename else { return }
                filenamePlayground = name
            } catch {
                guard !Task.isCancelled, filenameRequestID == requestID, editingFilename else { return }
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("QUEUE", "list.number")
                Spacer()
                Button(action: model.addLoop) { Image(systemName: "plus") }
                    .accessibilityLabel("Add queue loop")
                Button(action: model.removeLoop) { Image(systemName: "trash") }
                    .help("Delete selected loop").accessibilityLabel("Delete selected queue loop")
                    .disabled(model.loops.ranges.isEmpty)
            }
            VStack(alignment: .leading, spacing: LoopPanel.spacing) {
                ForEach(Array(model.loops.ranges.enumerated()), id: \.element.id) { index, loop in
                    QueueLoopCard(model: model, loop: loop, number: index + 1)
                }
            }
        }
    }

    private var looksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("COLOR", "paintpalette")
                Spacer()
                if model.isSuggestingColor {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Processing color correction")
                }
                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color model settings")
            }
            Picker("Color tool", selection: $colorTool) {
                ForEach(ColorTool.allCases, id: \.self) { tool in
                    Text(tool.rawValue).tag(tool)
                }
            }.pickerStyle(.segmented).labelsHidden()

            VStack(alignment: .leading, spacing: 12) {
                switch colorTool {
                case .auto:
                    Button(action: model.suggestAutomaticColorCorrection) {
                        Label("Auto correct", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(colorActionsUnavailable)
                case .reference:
                    Picker("Reference", selection: $referenceUsesModel) {
                        Text("Corrected copy of this frame").tag(false)
                        Text("Another image · AI model").tag(true)
                    }.labelsHidden().frame(maxWidth: .infinity)
                    Button {
                        if referenceUsesModel {
                            if model.colorProviderEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                openSettings()
                            } else {
                                model.suggestWithColorProvider()
                            }
                        } else {
                            model.importMatchingReference()
                        }
                    } label: {
                        Label("Choose reference…", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(colorActionsUnavailable)
                case .looks:
                    HStack {
                        Button("Save look", action: { model.saveCurrentLook() })
                            .disabled(colorActionsUnavailable || model.settings.color.isIdentity)
                        Spacer()
                        Button("Import LUT…", action: model.importCube)
                            .disabled(colorActionsUnavailable)
                    }
                    ForEach(model.savedLooks) { look in
                        HStack(spacing: 8) {
                            Button { model.applyLook(look) } label: {
                                Text(look.name).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(colorActionsUnavailable)
                            .accessibilityLabel("Apply saved look \(look.name)")
                            Button { model.deleteLook(look) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete saved look \(look.name)")
                        }
                    }
                }
            }.padding(.top, 4)
        }
    }

    private var colorActionsUnavailable: Bool {
        model.source == nil || model.isBusy || model.isSuggestingColor || model.showReview
    }

    private func sectionTitle(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }
}

private struct Filmstrip: View {
    @ObservedObject var model: EditorModel
    @State private var handleOrigin: MovieLoop?
    private let pictureHeight: CGFloat = 62
    private var selectedColor: Int { model.loops.selected?.colorIndex ?? 0 }
    /// Room above the loop headers for the playhead's marker head.
    static let markerBand: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let duration = max(model.source?.duration ?? 1, 0.001)
            let width = max(geometry.size.width, 1)
            let start = width * model.settings.start / duration
            let end = width * model.settings.end / duration
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    ForEach(Array(model.loops.ranges.enumerated()), id: \.element.id) { index, loop in
                        LoopHeader(model: model, loop: loop, number: index + 1, timelineWidth: width, sourceDuration: duration)
                    }
                    if model.loops.ranges.isEmpty { Color.clear.frame(height: 20) }
                }.padding(.top, Self.markerBand).padding(.bottom, 4)

                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                            Image(nsImage: image).resizable().scaledToFill()
                                .frame(width: width / CGFloat(max(model.thumbnails.count, 1)), height: pictureHeight).clipped()
                        }
                    }.frame(width: width, height: pictureHeight).background(.black).clipped().allowsHitTesting(false)
                    Color.black.opacity(0.55).frame(width: max(0, start)).allowsHitTesting(false)
                    Color.black.opacity(0.55).frame(width: max(0, width - end)).offset(x: end).allowsHitTesting(false)
                    // The Apple trim look: a thick rounded frame around the kept range, with the
                    // grab ends drawn as part of it rather than as separate slivers.
                    RoundedRectangle(cornerRadius: Self.handleRadius)
                        .strokeBorder(LoopColors.fill(selectedColor), lineWidth: 3)
                        .frame(width: max(Self.handleWidth * 2, end - start), height: pictureHeight)
                        .offset(x: min(start, width - max(Self.handleWidth * 2, end - start)))
                        .allowsHitTesting(false)

                    // Only the picture strip scrubs. Headers and endpoint handles
                    // own separate gestures; there is no parent drag recognizer.
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            model.pause()
                            model.seek(max(0, min(duration, value.location.x / width * duration)))
                        })
                        .accessibilityLabel("Scrub movie")
                    handle("Start", at: start, width: width, duration: duration, isStart: true, narrow: end - start < 24)
                    handle("End", at: end, width: width, duration: duration, isStart: false, narrow: end - start < 24)
                }.frame(height: pictureHeight)
                    .coordinateSpace(name: "filmstrip")
                    .accessibilityElement(children: .contain).accessibilityLabel("Movie timeline")
            }
            .overlay(alignment: .topLeading) {
                if let guide = model.snapGuide {
                    snapGuide(at: min(width, max(0, width * guide / duration)))
                }
            }
            .overlay(alignment: .topLeading) { playhead(at: min(width, max(0, width * model.position / duration))) }
        }
    }

    /// How far a dragged edge may sit from a snap target and still stick, in points.
    static let snapDistance: CGFloat = 7

    /// The Adobe-style guide: a dashed line down the whole timeline at the edge a drag stuck to.
    private func snapGuide(at x: CGFloat) -> some View {
        Rectangle()
            .fill(.white)
            .frame(width: 1)
            .overlay(Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.black.opacity(0.6)))
            .offset(x: x)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The playhead runs from the marker head down through the loop headers and the picture strip,
    /// so the current frame reads against the loops as well as the filmstrip. It never takes hits.
    private func playhead(at x: CGFloat) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).frame(height: Self.markerBand)
            Rectangle().frame(width: 2)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 1)
        .frame(width: 12)
        .offset(x: x - 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    /// How wide the grab caps are drawn, and how far past them a drag still counts. Chunky on
    /// purpose: a 6 pt sliver is hard to hit and harder to feel.
    static let handleWidth: CGFloat = 16
    static let handleRadius: CGFloat = 8
    private static let handleGrab: CGFloat = 10

    private func handle(_ name: String, at x: CGFloat, width: CGFloat, duration: Double, isStart: Bool, narrow: Bool) -> some View {
        // A short loop on a long source can be only a few screen pixels wide. Split its handle
        // targets vertically so neither cap covers the other.
        let capHeight = narrow ? pictureHeight / 2 - 2 : pictureHeight
        let leading = isStart
        return ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: leading ? Self.handleRadius : 0,
                bottomLeadingRadius: leading ? Self.handleRadius : 0,
                bottomTrailingRadius: leading ? 0 : Self.handleRadius,
                topTrailingRadius: leading ? 0 : Self.handleRadius
            )
            .fill(LoopColors.fill(selectedColor))
            .frame(width: Self.handleWidth, height: capHeight)
            // Three grip lines, the way a grabbable edge reads in Final Cut and Photos.
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(LoopColors.text(on: selectedColor).opacity(0.75))
                        .frame(width: 1.5, height: min(18, capHeight - 16))
                }
            }
            if narrow {
                Text(isStart ? "A" : "B").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LoopColors.text(on: selectedColor))
                    .offset(y: capHeight / 2 + 1)
            }
        }
        .frame(width: Self.handleWidth + Self.handleGrab * 2, height: capHeight + 6)
        .contentShape(Rectangle())
        .offset(x: (isStart ? x : x - Self.handleWidth) - Self.handleWidth / 2 - Self.handleGrab + Self.handleWidth / 2,
                y: narrow ? (isStart ? -pictureHeight / 4 : pictureHeight / 4) : 0)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("filmstrip")).onChanged { value in
            if handleOrigin == nil, let loop = model.loops.selected {
                handleOrigin = loop; model.beginLoopDrag(loop.id)
            }
            guard let original = handleOrigin else { return }
            let delta = value.translation.width / width * duration
            model.dragLoopHandle(start: isStart, original: original, by: delta, tolerance: Double(Self.snapDistance / width) * duration)
        }.onEnded { _ in handleOrigin = nil; model.endLoopDrag() })
        .help(isStart ? "Drag A to change where the loop starts, keeping B fixed. It snaps to the other loops' edges, the playhead and the movie's ends."
                      : "Drag B to change where the loop ends, keeping A fixed. The playhead shows the loop's last frame.")
        .accessibilityLabel("\(name) range handle").accessibilityValue(timeLabel(isStart ? model.settings.start : model.settings.end))
        .accessibilityAdjustableAction { direction in
            guard let original = model.loops.selected else { return }
            model.beginLoopDrag(original.id)
            let delta = direction == .increment ? 0.1 : -0.1
            model.dragLoopHandle(start: isStart, original: original, by: delta)
        }
        }

}

private struct LoopHeader: View {
    @ObservedObject var model: EditorModel
    let loop: MovieLoop
    let number: Int
    let timelineWidth: CGFloat
    let sourceDuration: Double
    @State private var dragOrigin: MovieLoop?
    @FocusState private var focused: Bool
    private var selected: Bool { model.loops.selectedID == loop.id || model.playsAllLoops }

    /// The drawn bar spans exactly A…B, so loops chained end to end sit flush on the timeline.
    private var spanWidth: CGFloat { min(timelineWidth, max(2, timelineWidth * CGFloat(loop.duration / sourceDuration))) }
    private var spanLeft: CGFloat { min(timelineWidth * CGFloat(loop.start / sourceDuration), timelineWidth - spanWidth) }

    /// The grab area never gets narrower than 44 pt, however short the loop is drawn.
    private var barWidth: CGFloat { min(timelineWidth, max(44, spanWidth)) }

    private var barLeft: CGFloat {
        max(0, min(spanLeft + spanWidth / 2 - barWidth / 2, timelineWidth - barWidth))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.035)).allowsHitTesting(false)
            interactiveHeader.offset(x: barLeft)
        }.frame(height: 20).coordinateSpace(name: "loopHeaders")
    }

    private var headerLabel: some View {
        ZStack(alignment: .leading) {
            Color.clear
            HStack(spacing: 5) {
                if spanWidth >= 44 { Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(90)) }
                if spanWidth >= 20 { Text(spanWidth > 75 ? "Loop \(number)" : String(number)).font(.system(size: 12, weight: .semibold)) }
            }
            .frame(width: spanWidth, height: 20)
            .foregroundStyle(selected ? LoopColors.text(on: loop.colorIndex) : LoopColors.onDark(loop.colorIndex))
            .background(selected ? LoopColors.fill(loop.colorIndex) : LoopColors.fill(loop.colorIndex).opacity(0.2), in: RoundedRectangle(cornerRadius: min(3, spanWidth / 2)))
            .overlay(RoundedRectangle(cornerRadius: min(3, spanWidth / 2)).stroke(focused ? Color.white : LoopColors.fill(loop.colorIndex).opacity(selected ? 0 : 0.55), lineWidth: 1))
            .offset(x: spanLeft - barLeft)
        }
        .frame(width: barWidth, height: 20)
        .contentShape(Rectangle())
    }

    /// Split from `interactiveHeader` so the type checker does not choke on one long chain.
    private var headerWithGesturesAndFocus: some View {
        headerLabel
            .gesture(moveGesture)
            .focusable().focused($focused)
            .onChange(of: model.loops.selectedID) { _, id in focused = id == loop.id }
            .onAppear { focused = model.loops.selectedID == loop.id }
            .onChange(of: focused) { _, isFocused in model.setLoopHeaderFocused(loop.id, focused: isFocused) }
            .onDisappear { model.setLoopHeaderFocused(loop.id, focused: false) }
    }

    private var interactiveHeader: some View {
        headerWithGesturesAndFocus
            .onKeyPress(.leftArrow, phases: .down) { press in moveByKeyboard(press.modifiers.contains(.shift) ? -1 : -0.1); return .handled }
            .onKeyPress(.rightArrow, phases: .down) { press in moveByKeyboard(press.modifiers.contains(.shift) ? 1 : 0.1); return .handled }
            .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { _ in model.removeLoop(loop.id); return .handled }
            .contextMenu {
                Button("Delete Loop \(number)", systemImage: "trash", role: .destructive) { model.removeLoop(loop.id) }
            }
            .accessibilityLabel("Move Loop \(number)")
            .accessibilityValue("\(timeLabel(loop.start)) to \(timeLabel(loop.end)), \(timeLabel(loop.duration)) long" + (selected ? ", selected" : ""))
            .accessibilityAdjustableAction { direction in moveByKeyboard(direction == .increment ? 0.1 : -0.1) }
            .help("Drag this header to move the whole loop; it snaps to the other loops' edges, the playhead and the movie's ends, marked by a dashed guide. With this header focused: arrow keys move it 0.1s, Shift-arrow 1s, Delete removes it. Click elsewhere first and the arrow keys move the playhead instead. Drag the filmstrip below to scrub.")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("loopHeaders"))
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = loop; focused = true
                    model.beginLoopDrag(loop.id)
                }
                guard let original = dragOrigin else { return }
                let delta = Double(value.translation.width / timelineWidth) * sourceDuration
                model.moveLoop(loop.id, originalStart: original.start, originalEnd: original.end, by: delta,
                               tolerance: Double(Filmstrip.snapDistance / timelineWidth) * sourceDuration)
            }
            .onEnded { value in
                dragOrigin = nil; model.endLoopDrag()
                if value.translation.width == 0 && value.translation.height == 0 { model.selectLoop(loop.id) }
            }
    }

    private func moveByKeyboard(_ delta: Double) {
        model.selectLoop(loop.id, seekToStart: false)
        model.nudgeSelectedLoop(by: delta)
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    /// Clockwise degrees, a multiple of 90. The view is given the turned picture's shape.
    var rotation = 0
    func makeNSView(context: Context) -> PlayerLayerView { let view = PlayerLayerView(); view.videoLayer.player = player; view.rotation = rotation; return view }
    func updateNSView(_ view: PlayerLayerView, context: Context) { view.videoLayer.player = player; view.rotation = rotation }
}
final class PlayerLayerView: NSView {
    let videoLayer = AVPlayerLayer()
    var rotation = 0 { didSet { if rotation != oldValue { needsLayout = true } } }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true; videoLayer.videoGravity = .resizeAspect; layer?.addSublayer(videoLayer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    /// The layer keeps the upright picture's shape and turns about its centre to fill the view. The turn is
    /// set instantly: the SwiftUI frame around it changes shape in one step, so an animated turn would lag it.
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let sideways = rotation % 180 != 0
        videoLayer.setAffineTransform(.identity)
        videoLayer.bounds = CGRect(origin: .zero, size: sideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size)
        videoLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        // AppKit's layer space has y pointing up, so a clockwise turn is a negative angle.
        videoLayer.setAffineTransform(CGAffineTransform(rotationAngle: -CGFloat(rotation) * .pi / 180))
        CATransaction.commit()
    }
}

func queueSeconds(_ seconds: Double) -> String {
    String(format: "%.1f", (seconds * 10).rounded(.towardZero) / 10)
}

struct TimeInput: View {
    let title: String
    @Binding var value: Double
    @Binding var error: String?
    let validate: (Double) -> String?
    @State private var text = ""
    @FocusState private var editing: Bool
    @State private var expectedProgrammaticText: String?

    var body: some View {
        TextField(title, text: $text)
            .multilineTextAlignment(.trailing).monospacedDigit().textFieldStyle(.roundedBorder)
            .focused($editing)
            .onAppear { syncDraft(value) }
            .onSubmit { if error == nil { syncDraft(value) } }
            .onChange(of: editing) { _, active in if !active && error == nil { syncDraft(value) } }
            .onChange(of: text) { _, draft in
                if draft == expectedProgrammaticText { expectedProgrammaticText = nil; return }
                expectedProgrammaticText = nil
                guard let number = Double(draft.trimmingCharacters(in: .whitespaces)), number.isFinite else {
                    error = "\(title): enter a finite number of seconds."
                    return
                }
                if let reason = validate(number) { error = reason; return }
                error = nil
                value = number
            }
            .onChange(of: value) { _, number in
                if Double(text) != number { error = nil; syncDraft(number) }
            }
    }

    private func syncDraft(_ number: Double) {
        let formatted = queueSeconds(number)
        guard text != formatted else { return }
        expectedProgrammaticText = formatted
        text = formatted
    }
}

struct CropInput: View {
    let title: String
    let value: Int
    @Binding var error: String?
    let commit: (Int) -> String?
    @State private var text = ""
    @State private var programmaticText: String?
    var body: some View {
        TextField(title, text: $text)
            .monospacedDigit().textFieldStyle(.roundedBorder)
            .onAppear { syncDraft() }
            .onChange(of: value) { _, _ in error = nil; syncDraft() }
            .onChange(of: text) { _, draft in
                if draft == programmaticText { programmaticText = nil; return }
                programmaticText = nil
                guard let number = Int(draft.trimmingCharacters(in: .whitespaces)) else {
                    error = "Crop \(title): enter a whole number of pixels."
                    return
                }
                error = commit(number)
            }
    }
    private func syncDraft() {
        let new = String(value)
        if text != new { programmaticText = new; text = new }
    }
}
