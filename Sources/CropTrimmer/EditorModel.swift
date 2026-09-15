import AppKit
import AVFoundation
import Combine
import CropTrimmerCore
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    @Published var source: MediaSource?
    @Published var settings = EditSettings() { didSet { settingsChanged(from: oldValue) } }
    @Published private(set) var loops = MovieLoops()
    @Published private(set) var defaultLoopLength: Double = 5
    var selectedLoopNumber: Int { (loops.ranges.firstIndex { $0.id == loops.selectedID } ?? 0) + 1 }
    @Published var position: Double = 0
    @Published var isPlaying = false
    @Published var playbackMode: PlaybackMode = .repeatSelection { didSet { updateBoundaryObserver() } }
    @Published var volume: Double = 1 { didSet { player.volume = Float(volume) } }
    @Published var muted = false { didSet { player.isMuted = muted } }
    @Published var cropAdjusting = false
    @Published var isBusy = false
    @Published var status = "Drop a movie to get started"
    @Published var progress: Double = 0
    @Published var plan: ExportPlan?
    @Published var estimates: [Quality: Int64] = [:]
    @Published var results: [ExportResult] = []
    @Published var showReview = false { didSet { if showReview { pause() } } }
    @Published var errorMessage: String?
    @Published private(set) var isSuggestingColor = false
    @Published var queueInputErrors: [UUID: [String: String]] = [:]
    @Published var queuePlans: [UUID: ExportPlan] = [:]
    @Published var queuePlanErrors: [UUID: String] = [:]
    @Published var queueEstimates: [UUID: [Quality: Int64]] = [:]
    var hasInputErrors: Bool { !timeInputErrors.isEmpty || queueInputErrors.values.contains { !$0.isEmpty } }
    func hasErrors(for id: UUID) -> Bool {
        !(queueInputErrors[id] ?? [:]).isEmpty || (loops.selectedID == id && !timeInputErrors.isEmpty)
    }
    @Published var timeInputErrors: [String: String] = [:]
    @Published var timeInputRevision = UUID()
    @Published var thumbnails: [NSImage] = []
    @Published private(set) var savedLooks: [SavedLook] = []
    let player = AVPlayer()
    let engine = MediaEngine()
    let lookStore = SavedLookStore()
    private var openingTask: Task<Void, Never>?
    private var planningTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var jobTask: Task<Void, Never>?
    private var colorSuggestionTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var scopedURL: URL?
    private var isResetting = false
    private var playbackOrigin: Double = 0
    private var looping = false
    private var wantsPlayback = false
    private var playbackRevision: UInt64 = 0
    private var generation = UUID()
    private var jobID: UUID?
    private var colorPreviewTask: Task<Void, Never>?

    init() {
        reloadLooks()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 60000), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.seconds.isFinite else { return }
                self.position = max(0, time.seconds - self.playbackOrigin)
                self.isPlaying = self.player.timeControlStatus == .playing
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                if self.playbackMode == .repeatSelection { self.loopSelection() }
                else { self.pause() }
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, self.source != nil, !self.showReview, !self.isBusy,
                      NSApp.keyWindow?.attachedSheet == nil,
                      !(NSApp.keyWindow is NSPanel),
                      !(NSApp.keyWindow?.firstResponder is NSTextView),
                      event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "i": self.setStart(); return true
                case "o": self.setEnd(); return true
                case " ":
                    // A focused AppKit control (button, popup, slider, field) owns Space for activation.
                    guard !(NSApp.keyWindow?.firstResponder is NSControl) else { return false }
                    self.togglePlayback(); return true
                default: return false
                }
            }
            return handled ? nil : event
        }
    }

    func reloadLooks() {
        Task { @MainActor in
            if let values = try? await lookStore.looks() { savedLooks = values }
        }
    }

    func saveCurrentLook(named name: String? = nil) {
        let fallback = "Look \(savedLooks.count + 1)"
        let trimmed = (name ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let look = SavedLook(name: trimmed, color: settings.color)
        Task { @MainActor in
            do { try await lookStore.save(look); reloadLooks() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func applyLook(_ look: SavedLook, to loopID: UUID? = nil) {
        let id = loopID ?? loops.selectedID
        guard let id, let current = loops.ranges.first(where: { $0.id == id })?.settings else { return }
        var next = current; next.color = look.color
        _ = updateLoop(id: id, settings: next)
    }

    func deleteLook(_ look: SavedLook) {
        Task { @MainActor in
            do { try await lookStore.delete(id: look.id); reloadLooks() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func importCube() {
        guard !isBusy, !showReview else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.data]; panel.allowsMultipleSelection = false
        panel.message = "Choose a supported 3D .cube color table."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let lut = try ColorLUT(cubeText: String(contentsOf: url, encoding: .utf8))
                    var next = self?.settings ?? EditSettings()
                    next.color = ColorSettings(enabled: true, baseLUT: lut)
                    if let self, let id = self.loops.selectedID { _ = self.updateLoop(id: id, settings: next) }
                } catch { self?.errorMessage = error.localizedDescription }
            }
        }
    }

    func suggestAutomaticColorCorrection() {
        guard !isBusy, !showReview, !isSuggestingColor, let source,
              let loop = loops.selected else { return }
        let requestedGeneration = generation
        let loopID = loop.id
        let sampledTime = loop.start + loop.duration / 2
        isSuggestingColor = true
        status = "Analyzing a representative frame…"
        colorSuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSuggestingColor = false; self.colorSuggestionTask = nil }
            do {
                let suggestion = try await Task.detached(priority: .userInitiated) {
                    try await AutomaticColorSuggestion.suggest(url: source.url, time: sampledTime)
                }.value
                try Task.checkCancellation()
                guard self.generation == requestedGeneration,
                      self.loops.selectedID == loopID,
                      self.loops.ranges.first(where: { $0.id == loopID })?.settings == loop.settings else { return }
                var next = loop.settings
                next.color = ColorSettings(enabled: true, baseLUT: suggestion.fit.lut)
                guard self.updateLoop(id: loopID, settings: next) == nil else { return }
                let errorLabel = String(format: "%.3f", suggestion.fit.meanError)
                self.status = "Automatic correction suggested · \(suggestion.sampleCount) samples · mean error \(errorLabel)"
            } catch is CancellationError {
                self.status = "Automatic correction cancelled"
            } catch {
                self.errorMessage = error.localizedDescription
                self.status = "Automatic correction unavailable"
            }
        }
    }

    func importMatchingReference() {
        guard !isBusy, !showReview, !isSuggestingColor, let source,
              let loop = loops.selected else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a corrected image of the same frame and composition."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let requestedGeneration = self?.generation ?? UUID()
            let loopID = loop.id
            let sampledTime = loop.start + loop.duration / 2
            self?.isSuggestingColor = true
            self?.status = "Fitting the matching reference frame…"
            self?.colorSuggestionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.isSuggestingColor = false; self.colorSuggestionTask = nil }
                do {
                    let suggestion = try await Task.detached(priority: .userInitiated) {
                        try await AutomaticColorSuggestion.suggest(url: source.url, time: sampledTime, referenceURL: url)
                    }.value
                    try Task.checkCancellation()
                    guard self.generation == requestedGeneration,
                          self.loops.selectedID == loopID,
                          self.loops.ranges.first(where: { $0.id == loopID })?.settings == loop.settings else { return }
                    var next = loop.settings
                    next.color = ColorSettings(enabled: true, baseLUT: suggestion.fit.lut)
                    guard self.updateLoop(id: loopID, settings: next) == nil else { return }
                    let errorLabel = String(format: "%.3f", suggestion.fit.meanError)
                    self.status = "Reference correction suggested · mean error \(errorLabel)"
                } catch is CancellationError {
                    self.status = "Reference correction cancelled"
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.status = "Reference correction unavailable"
                }
            }
        }
    }

    func openPanel() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a movie to trim or crop. The original stays untouched."
        panel.begin { [weak self] response in
            Task { @MainActor in if response == .OK, let url = panel.url { self?.open(url) } }
        }
    }

    func open(_ url: URL) { loadMovie(url) }

    @discardableResult
    func renameSource(to baseName: String) -> Bool {
        guard let source, !isBusy, !showReview else { return false }
        do {
            let renamed = try SourceRenamer.rename(sourceURL: source.url, identity: source.identity, baseName: baseName)
            guard renamed.path != source.url.path else { return true }
            let savedLoops = loops; let savedPosition = position
            for index in results.indices {
                if results[index].sourceURL == source.url { results[index].sourceURL = renamed }
                if results[index].url == source.url { results[index].url = renamed }
            }
            loadMovie(renamed, preserving: (savedLoops, savedPosition, source.identity))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadMovie(_ url: URL, preserving snapshot: (loops: MovieLoops, position: Double, identity: SourceIdentity)? = nil) {
        guard !isBusy else { status = "Finish or cancel the current operation before opening another movie."; return }
        guard url.isFileURL else { errorMessage = "Drop a local movie file."; return }
        openingTask?.cancel(); planningTask?.cancel(); thumbnailTask?.cancel(); colorSuggestionTask?.cancel()
        pause(); player.replaceCurrentItem(with: nil)
        generation = UUID(); let requestedGeneration = generation
        scopedURL?.stopAccessingSecurityScopedResource(); scopedURL = nil
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        isBusy = true; status = "Analyzing \(url.lastPathComponent)…"; progress = 0; errorMessage = nil
        timeInputErrors = [:]; timeInputRevision = UUID()
        queueInputErrors = [:]; queueEstimates = [:]; queuePlans = [:]; queuePlanErrors = [:]
        source = nil; loops = MovieLoops(); plan = nil; thumbnails = []; estimates = [:]; position = 0; cropAdjusting = false
        openingTask = Task {
            do {
                let inspected = try await engine.inspect(url)
                try Task.checkCancellation()
                let asset = AVURLAsset(url: url)
                let playable = try await asset.load(.isPlayable)
                try Task.checkCancellation()
                guard playable else { throw MediaError.unavailable("This movie cannot play in the native macOS viewer. This MVP supports movies playable by AVFoundation, such as compatible MP4 and MOV files.") }
                let origin = try await NativeTimeline.videoOrigin(in: asset)
                try Task.checkCancellation()
                guard generation == requestedGeneration else { return }
                if let snapshot {
                    guard inspected.identity == snapshot.identity else { throw MediaError.sourceChanged }
                    for loop in snapshot.loops.ranges { try loop.settings.validate(source: inspected) }
                }
                playbackOrigin = origin
                source = inspected
                isResetting = true
                loops = snapshot?.loops ?? MovieLoops(sourceDuration: inspected.duration, defaultLength: defaultLoopLength, settings: EditSettings(source: inspected))
                settings = loops.selected?.settings ?? EditSettings(source: inspected)
                isResetting = false
                player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                seek(snapshot?.position ?? 0)
                refreshColorPreview(for: requestedGeneration)
                player.volume = Float(volume); player.isMuted = muted
                isBusy = false; status = "Ready · \(inspected.width) × \(inspected.height) · \(timeLabel(inspected.duration))"
                updateBoundaryObserver(); schedulePlan(); loadThumbnails(asset: asset, source: inspected)
            } catch {
                guard generation == requestedGeneration else { return }
                isBusy = false
                if error is CancellationError {
                    status = snapshot == nil ? "Opening cancelled" : "Renamed to \(url.lastPathComponent) · reload cancelled"
                }
                else {
                    errorMessage = snapshot == nil ? error.localizedDescription : "The file was renamed to \(url.lastPathComponent), but could not be reloaded: \(error.localizedDescription)"
                    status = "Could not open \(url.lastPathComponent)"
                }
            }
        }
    }

    private func settingsChanged(from old: EditSettings) {
        guard !isResetting, settings != old else { return }
        loops.updateSelected(settings: settings)
        var previousWithoutQuality = old; previousWithoutQuality.quality = settings.quality
        if previousWithoutQuality != settings {
            estimates = [:]
            if let id = loops.selectedID { queueEstimates[id] = nil }
        }
        if !settings.cropEnabled { cropAdjusting = false; timeInputErrors = timeInputErrors.filter { !$0.key.hasPrefix("Crop ") } }
        updateBoundaryObserver()
        refreshColorPreview(for: generation)
        schedulePlan()
    }

    private func refreshColorPreview(for expectedGeneration: UUID) {
        colorPreviewTask?.cancel()
        guard let item = player.currentItem else { return }
        let asset = item.asset
        let correction = settings.color
        let capturedPosition = position
        let capturedRevision = playbackRevision
        guard !correction.isIdentity else {
            item.videoComposition = nil
            return
        }
        colorPreviewTask = Task { @MainActor [weak self] in
            do {
                let lut = try await Task.detached(priority: .userInitiated) { try ColorLUT.compile(settings: correction) }.value
                try Task.checkCancellation()
                guard let self, self.generation == expectedGeneration, self.player.currentItem === item else { return }
                item.videoComposition = ColorPlaybackRenderer.videoComposition(asset: asset, lut: lut)
                guard self.player.timeControlStatus != .playing, self.playbackRevision == capturedRevision else { return }
                await self.player.seek(to: CMTime(seconds: capturedPosition + self.playbackOrigin, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
            } catch { }
        }
    }

    private func schedulePlan(preserveStatus: Bool = false) {
        planningTask?.cancel()
        guard let source, !isBusy else { plan = nil; return }
        let snapshot = loops.ranges; let id = generation
        queuePlans = queuePlans.filter { key, value in
            value.source.id == source.id && snapshot.contains { $0.id == key && $0.settings == value.settings }
        }
        queuePlanErrors = [:]
        plan = loops.selectedID.flatMap { queuePlans[$0] }
        if !preserveStatus { status = plan?.explanation ?? "Checking export methods…" }
        planningTask = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            for loop in snapshot {
                guard !Task.isCancelled, generation == id, !isBusy else { return }
                if queuePlans[loop.id] != nil { continue }
                do {
                    let proposed = try await engine.plan(source: source, settings: loop.settings)
                    try Task.checkCancellation()
                    guard generation == id, loops.ranges.contains(where: { $0.id == loop.id && $0.settings == loop.settings }) else { return }
                    queuePlans[loop.id] = proposed
                    if loops.selectedID == loop.id {
                        plan = proposed
                        if !preserveStatus { status = proposed.explanation }
                    }
                } catch is CancellationError { return }
                catch {
                    guard generation == id, !Task.isCancelled else { return }
                    queuePlanErrors[loop.id] = error.localizedDescription
                    if loops.selectedID == loop.id && !preserveStatus { status = error.localizedDescription }
                }
            }
        }
    }

    func seek(_ seconds: Double) {
        guard let source else { return }
        let seconds = max(0, min(source.duration, seconds))
        playbackRevision &+= 1
        position = seconds
        player.seek(to: CMTime(seconds: seconds + playbackOrigin, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func pause() { wantsPlayback = false; playbackRevision &+= 1; player.pause(); isPlaying = false }
    func togglePlayback() {
        guard source != nil, !isBusy, !showReview else { return }
        cropAdjusting = false
        if wantsPlayback { pause(); return }
        if playbackMode != .whole && (position < settings.start || position >= settings.end - 0.001) { seek(settings.start) }
        else if let source, position >= source.duration - 0.001 { seek(0) }
        wantsPlayback = true; player.play(); isPlaying = true
    }
    func stop() { guard !isBusy, !showReview else { return }; cropAdjusting = false; pause(); seek(playbackMode == .whole ? 0 : settings.start) }
    func step(_ direction: Int) {
        guard !isBusy, !showReview else { return }
        cropAdjusting = false; pause()
        guard let item = player.currentItem else { return }
        if direction < 0 && !item.canStepBackward { status = "This movie does not support backward frame stepping."; return }
        if direction > 0 && !item.canStepForward { status = "This movie does not support forward frame stepping."; return }
        item.step(byCount: direction < 0 ? -1 : 1)
    }
    func jump(_ seconds: Double) { guard !isBusy, !showReview else { return }; cropAdjusting = false; pause(); seek(position + seconds) }
    func recallStart() { pause(); seek(settings.start) }
    func recallEnd() { pause(); seek(settings.end) }
    func setStart() {
        guard !isBusy, position < settings.end else { status = "Start must be before the end."; return }
        settings.start = position
    }
    func setEnd() {
        guard !isBusy, position > settings.start, let source else { status = "End must be after the start."; return }
        settings.end = min(position, source.duration)
    }
    func resetRange() { guard !isBusy, let source else { return }; timeInputErrors = [:]; timeInputRevision = UUID(); settings.start = 0; settings.end = source.duration }
    func selectLoop(_ id: UUID, seekToStart: Bool = true) {
        guard !isBusy, !showReview, source != nil, loops.ranges.contains(where: { $0.id == id }) else { return }
        pause()
        if loops.selectedID != id {
            let cached = queueEstimates[id]
            loops.select(id)
            clearInputDrafts()
            applySelectedLoop()
            queueEstimates[id] = cached
            estimates = cached ?? [:]
        }
        if seekToStart { seek(settings.start) }
    }

    @discardableResult
    func updateLoop(id: UUID, settings edit: EditSettings) -> String? {
        guard !isBusy, !showReview, let source else { return "Finish the current operation before editing." }
        do { try edit.validate(source: source) } catch { return error.localizedDescription }
        guard let old = loops.ranges.first(where: { $0.id == id })?.settings,
              loops.update(id: id, settings: edit) else { return "This loop is no longer available." }
        var comparable = old; comparable.quality = edit.quality
        if comparable != edit { queueEstimates[id] = nil }
        if loops.selectedID == id { settings = edit }
        else { schedulePlan(preserveStatus: true) }
        return nil
    }

    var canSelectPreviousLoop: Bool { selectedLoopNumber > 1 }
    var canSelectNextLoop: Bool { selectedLoopNumber < loops.ranges.count }

    func selectAdjacentLoop(_ direction: Int) {
        guard !isBusy, !showReview, source != nil,
              direction == -1 || direction == 1,
              let index = loops.ranges.firstIndex(where: { $0.id == loops.selectedID }) else { return }
        let destination = index + direction
        guard loops.ranges.indices.contains(destination) else { return }
        let resume = wantsPlayback
        selectLoop(loops.ranges[destination].id)
        // Loop navigation always gives transport a selection-based context.
        if playbackMode == .whole { playbackMode = .repeatSelection }
        if resume { togglePlayback() }
    }

    func addLoop() {
        guard !isBusy, !showReview, source != nil, loops.ranges.count < MovieLoops.maximumCount else { return }
        pause()
        guard loops.add(length: defaultLoopLength) else { return }
        clearInputDrafts(); applySelectedLoop(); seek(settings.start)
    }

    func removeLoop() {
        guard !isBusy, !showReview, loops.ranges.count > 1 else { return }
        pause()
        let removedID = loops.selectedID
        guard loops.removeSelected() else { return }
        if let removedID { queueInputErrors[removedID] = nil; queueEstimates[removedID] = nil }
        let selectedID = loops.selectedID
        let cached = selectedID.flatMap { queueEstimates[$0] }
        clearInputDrafts(); applySelectedLoop(); seek(settings.start)
        if let selectedID { queueEstimates[selectedID] = cached; estimates = cached ?? [:] }
    }

    func setLoopLength(_ seconds: Double) {
        guard !isBusy, !showReview, source != nil, seconds == 5 || seconds == 10 else { return }
        pause(); defaultLoopLength = seconds
        loops.resizeSelected(to: seconds)
        clearInputDrafts(); applySelectedLoop()
    }

    func beginLoopDrag(_ id: UUID) {
        guard !isBusy, !showReview, loops.ranges.contains(where: { $0.id == id }) else { return }
        selectLoop(id, seekToStart: false)
        clearInputDrafts()
    }

    func moveLoop(_ id: UUID, originalStart: Double, originalEnd: Double, by delta: Double) {
        guard !isBusy, !showReview, source != nil else { return }
        guard loops.move(id, originalStart: originalStart, originalEnd: originalEnd, by: delta) else { return }
        applySelectedLoop()
    }

    func dragLoopHandle(start: Bool, original: MovieLoop, by delta: Double) {
        guard !isBusy, !showReview, let source, delta.isFinite,
              loops.selectedID == original.id else { return }
        if start {
            moveLoop(original.id, originalStart: original.start, originalEnd: original.end, by: delta)
        } else {
            let minimum = min(0.001, source.duration)
            var edit = settings
            edit.end = min(source.duration, max(original.end + delta, edit.start + minimum))
            settings = edit
        }
    }

    func nudgeSelectedLoop(by seconds: Double) {
        guard let loop = loops.selected, !isBusy, !showReview else { return }
        beginLoopDrag(loop.id)
        moveLoop(loop.id, originalStart: loop.start, originalEnd: loop.end, by: seconds)
    }

    private func applySelectedLoop() {
        guard let loop = loops.selected else { return }
        cropAdjusting = false
        estimates = [:]
        settings = loop.settings
        schedulePlan()
    }

    private func clearInputDrafts() { timeInputErrors = [:]; timeInputRevision = UUID() }

    func setCropAspectRatio(_ aspect: CropAspectRatio) {
        guard !isBusy, let source else { return }
        pause(); clearInputDrafts()
        var edit = settings
        edit.cropAspectRatio = aspect
        if aspect != .free { edit.lastLockedCropAspectRatio = aspect }
        edit.crop = CropGeometry.fitted(edit.crop, aspect: aspect, sourceWidth: source.width, sourceHeight: source.height)
        settings = edit
    }

    func toggleCropAspectLock() {
        let locked = settings.cropAspectRatio != nil && settings.cropAspectRatio != .free
        setCropAspectRatio(locked ? .free : (settings.lastLockedCropAspectRatio ?? .original))
    }

    func beginCrop() { guard !isBusy else { return }; pause(); settings.cropEnabled = true; cropAdjusting = true }
    func doneCrop() { pause(); cropAdjusting = false }
    func resetCrop() {
        guard !isBusy, let source else { return }
        timeInputErrors = [:]; timeInputRevision = UUID()
        settings.crop = CropGeometry.fitted(PixelRect(width: source.width, height: source.height), aspect: settings.cropAspectRatio ?? .free, sourceWidth: source.width, sourceHeight: source.height)
    }

    private func updateBoundaryObserver() {
        if let boundaryObserver { player.removeTimeObserver(boundaryObserver); self.boundaryObserver = nil }
        guard source != nil, playbackMode != .whole, settings.end > settings.start else { return }
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: CMTime(seconds: settings.end + playbackOrigin, preferredTimescale: 60000))], queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.wantsPlayback else { return }
                if self.playbackMode == .repeatSelection { self.loopSelection() }
                else { self.pause(); self.seek(self.settings.end) }
            }
        }
    }
    private func loopSelection() {
        guard !looping, wantsPlayback, !isBusy, !cropAdjusting, !showReview, source != nil, playbackMode == .repeatSelection else { return }
        looping = true
        let revision = playbackRevision; let sourceGeneration = generation
        player.seek(to: CMTime(seconds: settings.start + playbackOrigin, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                self.looping = false
                if finished && self.wantsPlayback && self.playbackRevision == revision && self.generation == sourceGeneration && !self.isBusy && !self.showReview && !self.cropAdjusting && self.playbackMode == .repeatSelection { self.player.play(); self.isPlaying = true }
            }
        }
    }

    private func loadThumbnails(asset: AVAsset, source: MediaSource) {
        thumbnailTask?.cancel()
        let origin = playbackOrigin
        thumbnailTask = Task {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 120)
            var frames: [NSImage] = []
            for index in 0..<12 {
                guard !Task.isCancelled else { generator.cancelAllCGImageGeneration(); return }
                let time = CMTime(seconds: origin + source.duration * (Double(index) + 0.5) / 12, preferredTimescale: 60000)
                if let result = try? await generator.image(at: time) {
                    frames.append(NSImage(cgImage: result.image, size: .zero))
                }
            }
            guard self.source?.id == source.id, !Task.isCancelled else { return }
            thumbnails = frames
        }
    }

    func estimate() { if let id = loops.selectedID { estimateLoop(id) } }

    func estimateLoop(_ loopID: UUID) {
        guard !isBusy, !showReview, !hasErrors(for: loopID), let source,
              let edit = loops.ranges.first(where: { $0.id == loopID })?.settings else { return }
        pause(); planningTask?.cancel()
        let id = UUID(); jobID = id; isBusy = true; progress = 0; status = "Estimating loop sizes…"
        jobTask = Task {
            do {
                let proposed = try await engine.plan(source: source, settings: edit)
                try Task.checkCancellation()
                if proposed.method == .copy {
                    status = "Fast trim copies source quality; compression estimates are not needed."
                } else {
                    let values = try await engine.estimate(plan: proposed) { [weak self] value, message in
                        Task { @MainActor in guard self?.jobID == id else { return }; self?.progress = value; self?.status = message }
                    }
                    try Task.checkCancellation()
                    queueEstimates[loopID] = values
                    if loops.selectedID == loopID { estimates = values }
                    status = "Approximate sizes ready"
                }
            } catch { handleJobError(error) }
            finishJob(id)
            schedulePlan(preserveStatus: true)
        }
    }

    func export() { beginExportQueue(all: false) }
    func exportLoop(_ id: UUID) { beginExportQueue(all: false, loopID: id) }
    func exportQueue() { beginExportQueue(all: true) }

    private func beginExportQueue(all: Bool, loopID: UUID? = nil) {
        guard let source, !isBusy, !showReview, !cropAdjusting else { return }
        let target = loopID ?? loops.selectedID
        guard all ? !hasInputErrors : target.map({ !hasErrors(for: $0) }) == true else { return }
        let entries = loops.ranges.enumerated().compactMap { index, loop -> (Int, EditSettings)? in
            all || loop.id == target ? (index + 1, loop.settings) : nil
        }
        guard !entries.isEmpty else { return }
        let directory = source.url.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: directory.path) {
            startExportQueue(source: source, entries: entries, directory: directory)
        } else {
            let sourceGeneration = generation
            let snapshot = loops
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.prompt = "Export Here"; panel.message = "The original folder is not writable. Choose where to save the new movies."
            panel.begin { [weak self] response in
                Task { @MainActor in
                    guard let self, response == .OK, let directory = panel.url,
                          self.generation == sourceGeneration, self.loops == snapshot else { return }
                    self.startExportQueue(source: source, entries: entries, directory: directory)
                }
            }
        }
    }

    private func startExportQueue(source: MediaSource, entries: [(Int, EditSettings)], directory: URL) {
        guard !isBusy, !showReview else { return }
        pause(); planningTask?.cancel(); isBusy = true; progress = 0; status = "Preparing queue…"
        let id = UUID(); jobID = id
        jobTask = Task {
            let scoped = directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
            var completed = 0
            do {
                // Validate every entry before producing any files.
                var plans: [(Int, ExportPlan)] = []
                for (number, edit) in entries {
                    try Task.checkCancellation()
                    status = "Checking Loop \(number)…"
                    plans.append((number, try await engine.plan(source: source, settings: edit)))
                }
                for (number, plan) in plans {
                    try Task.checkCancellation()
                    let offset = completed
                    let temp = OutputPublisher.temporaryURL(in: directory, extension: plan.fileExtension)
                    defer { OutputPublisher.discard(temporaryURL: temp) }
                    var result = try await engine.export(plan: plan, to: temp) { [weak self] value, message in
                        Task { @MainActor in
                            guard self?.jobID == id else { return }
                            self?.progress = (Double(offset) + value) / Double(entries.count)
                            self?.status = "Loop \(number) · \(message)"
                        }
                    }
                    try Task.checkCancellation()
                    guard try SourceIdentity(url: source.url) == source.identity else { throw MediaError.sourceChanged }
                    let trimmed = plan.settings.start > 0.001 || plan.settings.end < source.duration - 0.001
                    let published = try OutputPublisher.publish(temporaryURL: temp, sourceURL: source.url, cropped: plan.settings.cropEnabled, trimmed: trimmed, directory: directory, extension: plan.fileExtension, loopNumber: number)
                    result.url = published; results.append(result); completed += 1
                }
                progress = 1; status = "Saved \(completed) loop\(completed == 1 ? "" : "s") to \(directory.lastPathComponent)"
                showReview = true
            } catch {
                handleJobError(error)
                if completed > 0 { status += " · \(completed) completed export(s) kept" }
            }
            finishJob(id)
            schedulePlan(preserveStatus: true)
        }
    }
    private func handleJobError(_ error: Error) {
        if error is CancellationError || (error as? MediaError)?.errorDescription == MediaError.cancelled.errorDescription { status = "Cancelled · your edit is preserved" }
        else { errorMessage = error.localizedDescription; status = "Operation failed · your edit is preserved" }
    }
    private func finishJob(_ id: UUID) { guard jobID == id else { return }; jobID = nil; isBusy = false; jobTask = nil }
    func cancel() {
        status = "Cancelling…"; openingTask?.cancel(); jobTask?.cancel(); colorSuggestionTask?.cancel()
        Task { await engine.cancel() }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func shutdown() {
        openingTask?.cancel(); planningTask?.cancel(); thumbnailTask?.cancel(); jobTask?.cancel(); colorSuggestionTask?.cancel()
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        if let boundaryObserver { player.removeTimeObserver(boundaryObserver); self.boundaryObserver = nil }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        scopedURL?.stopAccessingSecurityScopedResource()
    }
}
