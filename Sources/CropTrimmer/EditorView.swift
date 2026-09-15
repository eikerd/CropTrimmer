import SwiftUI
import AVKit
import UniformTypeIdentifiers
import CropTrimmerCore

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @State private var editingFilename = false
    @State private var filenameDraft = ""
    @FocusState private var filenameFocused: Bool

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
                Text(model.status).lineLimit(2).font(.caption).textSelection(.enabled)
                Spacer()
                if let source = model.source { Text("\(source.width) × \(source.height) · \(timeLabel(source.duration))").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }.padding(.horizontal, 12).frame(minHeight: 32)
        }
        .background(Color(red: 0.105, green: 0.105, blue: 0.115))
        .preferredColorScheme(.dark)
        .onChange(of: model.source?.id) { _, _ in editingFilename = false }
        .toolbar {
            ToolbarItem { Button(action: model.openPanel) { Label("Open Movie", systemImage: "folder") }.disabled(model.isBusy) }
            ToolbarItem { Text(model.source?.url.lastPathComponent ?? "Crop Trimmer").lineLimit(1)
                .help(model.source.map { "Double-click to rename · " + $0.url.path } ?? "Open a movie to begin")
                .onTapGesture(count: 2, perform: beginFilenameEdit) }
            ToolbarItem { Button { model.showReview = true } label: { Label("Exports (\(model.results.count))", systemImage: "square.stack") }.disabled(model.results.isEmpty) }
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
                let width = CGFloat(cropped ? crop.width : source.width)
                let height = CGFloat(cropped ? crop.height : source.height)
                let scale = min(proxy.size.width / width, proxy.size.height / height)
                ZStack {
                    Color.black
                    ZStack(alignment: .topLeading) {
                        PlayerSurface(player: model.player)
                            .frame(width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
                            .offset(x: cropped ? -CGFloat(crop.x) * scale : 0, y: cropped ? -CGFloat(crop.y) * scale : 0)
                    }.frame(width: width * scale, height: height * scale, alignment: .topLeading).clipped()
                    if model.cropAdjusting {
                        CropOverlay(crop: $model.settings.crop, aspect: model.settings.cropAspectRatio ?? .free, sourceWidth: source.width, sourceHeight: source.height)
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
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                transportButton("Back 5 seconds", "gobackward.5") { model.jump(-5) }
                transportButton("Previous loop", "backward.end") { model.selectAdjacentLoop(-1) }
                    .disabled(!model.canSelectPreviousLoop)
                transportButton(model.isPlaying ? "Pause" : "Play", model.isPlaying ? "pause.fill" : "play.fill", action: model.togglePlayback)
                transportButton("Stop", "stop.fill", action: model.stop)
                transportButton("Next loop", "forward.end") { model.selectAdjacentLoop(1) }
                    .disabled(!model.canSelectNextLoop)
                transportButton("Forward 5 seconds", "goforward.5") { model.jump(5) }
                Spacer(minLength: 0)
                Text(timeLabel(model.position)).font(.system(.body, design: .monospaced)).accessibilityLabel("Playhead \(timeLabel(model.position))")
            }
            HStack {
                Picker("Playback", selection: $model.playbackMode) { ForEach(PlaybackMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(maxWidth: 180)
                Spacer()
                Button { model.muted.toggle() } label: { Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") }.buttonStyle(.plain).help("Mute monitoring audio")
                Slider(value: $model.volume, in: 0...1).frame(width: 80).accessibilityLabel("Monitoring volume")
            }
        }.disabled(model.source == nil || model.isBusy)
    }

    private func transportButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 36, height: 32).contentShape(Rectangle()) }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private var timeline: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("LOOPS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(model.loops.ranges.enumerated()), id: \.element.id) { index, loop in
                    Button { model.selectLoop(loop.id) } label: {
                        Text(String(index + 1)).fontWeight(.semibold).frame(width: 18)
                    }
                    .tint(loop.id == model.loops.selectedID ? .yellow : .gray)
                    .background(loop.id == model.loops.selectedID ? Color.yellow.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("Select Loop \(index + 1)")
                    .accessibilityValue(loop.id == model.loops.selectedID ? "Selected" : "")
                    .help("Loop \(index + 1): \(timeLabel(loop.start)) – \(timeLabel(loop.end))")
                }
                Button(action: model.addLoop) { Image(systemName: "plus") }
                    .disabled(model.loops.ranges.count >= MovieLoops.maximumCount)
                    .help("Add a \(Int(model.defaultLoopLength))-second loop, up to three loops")
                    .accessibilityLabel("Add loop")
                Button(action: model.removeLoop) { Image(systemName: "minus") }
                    .disabled(model.loops.ranges.count < 2)
                    .help("Remove selected loop").accessibilityLabel("Remove selected loop")
                Spacer(minLength: 6)
                Text("Length").font(.caption).foregroundStyle(.secondary)
                ForEach([5, 10], id: \.self) { seconds in
                    Button("\(seconds)s") { model.setLoopLength(Double(seconds)) }
                        .tint(abs(model.settings.duration - Double(seconds)) < 0.000001 ? .yellow : .gray)
                        .help("Make this loop \(seconds) seconds; new loops also start at \(seconds) seconds")
                        .accessibilityLabel("Set loop length to \(seconds) seconds")
                }
            }.controlSize(.small)
            HStack {
                Button("A") { NSEvent.modifierFlags.contains(.shift) ? model.setStart() : model.recallStart() }.help("Recall A · Shift-click to set A (I)")
                Text(timeLabel(model.settings.start)).monospacedDigit()
                Spacer()
                Text("Loop \(model.selectedLoopNumber) · \(timeLabel(model.settings.duration)) selected").foregroundStyle(.yellow).monospacedDigit()
                Spacer()
                Text(timeLabel(model.settings.end)).monospacedDigit()
                Button("B") { NSEvent.modifierFlags.contains(.shift) ? model.setEnd() : model.recallEnd() }.help("Recall B · Shift-click to set B (O)")
            }.font(.caption)
            Filmstrip(model: model).frame(height: CGFloat(max(1, model.loops.ranges.count)) * 24 + 66).id(model.source?.id)
            HStack { Text("00:00.000"); Spacer(); Text("Header moves loop · Filmstrip scrubs"); Spacer(); Text(timeLabel(model.source?.duration ?? 0)) }.font(.caption2).foregroundStyle(.secondary)
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
                    Button("Export Queue (\(model.loops.ranges.count))", action: model.exportQueue)
                        .frame(maxWidth: .infinity).buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.source == nil || model.cropAdjusting || model.hasInputErrors)
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
                            .onExitCommand { editingFilename = false }
                        if !source.url.pathExtension.isEmpty {
                            Text("." + source.url.pathExtension).foregroundStyle(.secondary)
                        }
                    }
                    Text("Renames the original file in its current folder.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Cancel") { editingFilename = false }
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
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Original file: \(byteLabel(source.identity.size)), \(source.videoCodec) video")
            }
        }
    }

    private func beginFilenameEdit() {
        guard let source = model.source, !model.isBusy, !model.showReview else { return }
        model.pause()
        filenameDraft = source.url.deletingPathExtension().lastPathComponent
        editingFilename = true; filenameFocused = true
    }

    private func commitFilename() {
        if model.renameSource(to: filenameDraft) { editingFilename = false }
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("QUEUE", "list.number")
                Spacer()
                Button(action: model.addLoop) { Image(systemName: "plus") }
                    .accessibilityLabel("Add queue loop")
                    .disabled(model.loops.ranges.count >= MovieLoops.maximumCount)
                Button(action: model.removeLoop) { Image(systemName: "minus") }
                    .accessibilityLabel("Remove queue loop")
                    .disabled(model.loops.ranges.count < 2)
            }
            ForEach(Array(model.loops.ranges.enumerated()), id: \.element.id) { index, loop in
                QueueLoopCard(model: model, loop: loop, number: index + 1)
            }
        }
    }

    private var looksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("SAVED LOOKS", "paintpalette")
            Button("Save selected color correction") { model.saveCurrentLook() }
                .disabled(model.source == nil || model.settings.color.isIdentity)
                .accessibilityLabel("Save selected color correction as a look")
            ForEach(model.savedLooks) { look in
                HStack(spacing: 4) {
                    Button(look.name) { model.applyLook(look) }
                        .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Apply saved look \(look.name)")
                    Button { model.deleteLook(look) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help("Delete saved look \(look.name)")
                        .accessibilityLabel("Delete saved look \(look.name)")
                }
            }
        }
    }

    private func sectionTitle(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }
}

private struct Filmstrip: View {
    @ObservedObject var model: EditorModel
    @State private var handleOrigin: MovieLoop?
    private let pictureHeight: CGFloat = 62

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
                }.padding(.bottom, 4)

                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                            Image(nsImage: image).resizable().scaledToFill()
                                .frame(width: width / CGFloat(max(model.thumbnails.count, 1)), height: pictureHeight).clipped()
                        }
                    }.frame(width: width, height: pictureHeight).background(.black).clipped().allowsHitTesting(false)
                    Color.black.opacity(0.55).frame(width: max(0, start)).allowsHitTesting(false)
                    Color.black.opacity(0.55).frame(width: max(0, width - end)).offset(x: end).allowsHitTesting(false)
                    Rectangle().stroke(.yellow, lineWidth: 2)
                        .frame(width: max(0, end - start), height: pictureHeight).offset(x: start).allowsHitTesting(false)

                    // Only the picture strip scrubs. Headers and endpoint handles
                    // own separate gestures; there is no parent drag recognizer.
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            model.pause()
                            model.seek(max(0, min(duration, value.location.x / width * duration)))
                        })
                        .accessibilityLabel("Scrub movie")
                    Rectangle().fill(.white).frame(width: 1.5)
                        .offset(x: min(width, max(0, width * model.position / duration))).allowsHitTesting(false)
                    handle("Start", at: start, width: width, duration: duration, isStart: true, narrow: end - start < 24)
                    handle("End", at: end, width: width, duration: duration, isStart: false, narrow: end - start < 24)
                }.frame(height: pictureHeight)
                    .coordinateSpace(name: "filmstrip")
                    .accessibilityElement(children: .contain).accessibilityLabel("Movie timeline")
            }
        }
    }
    private func handle(_ name: String, at x: CGFloat, width: CGFloat, duration: Double, isStart: Bool, narrow: Bool) -> some View {
        // A short loop on a long source can be only a few screen pixels wide.
        // Split its handle targets vertically so neither handle covers the other.
        RoundedRectangle(cornerRadius: 2).fill(.yellow)
            .frame(width: narrow ? 18 : 6, height: narrow ? pictureHeight / 2 - 2 : pictureHeight)
            .overlay {
                if narrow { Text(isStart ? "A" : "B").font(.system(size: 9, weight: .bold)).foregroundStyle(.black) }
            }
            .padding(.horizontal, narrow ? 1 : 7).contentShape(Rectangle())
            .offset(x: narrow ? max(0, min(x - 10, width - 20)) : x - 10,
                    y: narrow ? (isStart ? -pictureHeight / 4 : pictureHeight / 4) : 0)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("filmstrip")).onChanged { value in
                if handleOrigin == nil, let loop = model.loops.selected {
                    handleOrigin = loop; model.beginLoopDrag(loop.id)
                }
                guard let original = handleOrigin else { return }
                let delta = value.translation.width / width * duration
                model.dragLoopHandle(start: isStart, original: original, by: delta)
            }.onEnded { _ in handleOrigin = nil })
            .help(isStart ? "Drag A to reposition the loop, keeping its length. B moves with it." : "Drag B to change the loop length, keeping A fixed.")
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
    private var selected: Bool { model.loops.selectedID == loop.id }

    private var barWidth: CGFloat {
        let span = timelineWidth * CGFloat(loop.duration / sourceDuration)
        return min(timelineWidth, max(44, span))
    }

    private var barLeft: CGFloat {
        let midpoint = timelineWidth * CGFloat((loop.start + loop.end) / sourceDuration) / 2
        return max(0, min(midpoint - barWidth / 2, timelineWidth - barWidth))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.035)).allowsHitTesting(false)
            interactiveHeader.offset(x: barLeft)
        }.frame(height: 20).coordinateSpace(name: "loopHeaders")
    }

    private var headerLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(90))
            Text(barWidth > 75 ? "Loop \(number)" : String(number)).font(.system(size: 10, weight: .semibold))
        }
        .frame(width: barWidth, height: 20)
        .foregroundStyle(selected ? Color.black : Color.yellow)
        .background(selected ? Color.yellow : Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(focused ? Color.white : Color.yellow.opacity(selected ? 0 : 0.45), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var interactiveHeader: some View {
        headerLabel
            .gesture(moveGesture)
            .focusable().focused($focused)
            .onChange(of: model.loops.selectedID) { _, id in focused = id == loop.id }
            .onAppear { focused = selected }
            .onKeyPress(.leftArrow, phases: .down) { press in moveByKeyboard(press.modifiers.contains(.shift) ? -1 : -0.1); return .handled }
            .onKeyPress(.rightArrow, phases: .down) { press in moveByKeyboard(press.modifiers.contains(.shift) ? 1 : 0.1); return .handled }
            .accessibilityLabel("Move Loop \(number)")
            .accessibilityValue("\(timeLabel(loop.start)) to \(timeLabel(loop.end)), \(timeLabel(loop.duration)) long" + (selected ? ", selected" : ""))
            .accessibilityAdjustableAction { direction in moveByKeyboard(direction == .increment ? 0.1 : -0.1) }
            .help("Drag this yellow header to move the whole loop. Arrow keys move 0.1s; Shift-arrow moves 1s. Drag the filmstrip below to scrub.")
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
                model.moveLoop(loop.id, originalStart: original.start, originalEnd: original.end, by: delta)
            }
            .onEnded { value in
                dragOrigin = nil
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
    func makeNSView(context: Context) -> PlayerLayerView { let view = PlayerLayerView(); view.videoLayer.player = player; return view }
    func updateNSView(_ view: PlayerLayerView, context: Context) { view.videoLayer.player = player }
}
final class PlayerLayerView: NSView {
    let videoLayer = AVPlayerLayer()
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true; videoLayer.videoGravity = .resizeAspect; layer?.addSublayer(videoLayer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func layout() { super.layout(); videoLayer.frame = bounds }
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
