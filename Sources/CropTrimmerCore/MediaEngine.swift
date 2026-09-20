import Foundation
import Darwin

/// FFmpeg is isolated behind an actor. No shell is involved, and all outputs are private until
/// the storage service publishes a validated result. Copy timing is verified against source pixels.
public actor MediaEngine {
    private var processes: [UUID: Process] = [:]
    private var cancellation: UInt64 = 0
    public init() {}

    public func cancel() async {
        cancellation &+= 1
        for process in processes.values where process.isRunning { process.terminate() }
    }

    public func inspect(_ url: URL) async throws -> MediaSource {
        guard url.isFileURL else { throw MediaError.invalid("Open a local movie file.") }
        let identity = try SourceIdentity(url: url)
        let object = try await probe(url)
        let streams = object["streams"] as? [[String: Any]] ?? []
        // Cover art is muxed as a video stream flagged attached_pic and may precede the movie.
        // Every FFmpeg/ffprobe invocation below uses the `V` specifier, which skips such streams.
        let pictures = streams.filter { ($0["codec_type"] as? String) == "video" }
        let movies = pictures.filter { (($0["disposition"] as? [String: Any])?["attached_pic"] as? Int ?? 0) == 0 }
        guard !pictures.isEmpty, !movies.isEmpty else {
            throw MediaError.invalid(pictures.isEmpty ? "This file does not contain a supported movie picture."
                                                      : "Every video stream is an attached image, not a movie.")
        }
        guard let video = movies.first, let w = video["width"] as? Int, let h = video["height"] as? Int, w >= 2, h >= 2 else {
            throw MediaError.invalid("This file does not contain a supported movie picture.")
        }
        let format = object["format"] as? [String: Any] ?? [:]
        let start = number(video["start_time"]) ?? number(format["start_time"]) ?? 0
        let duration = number(video["duration"]) ?? number(format["duration"]) ?? 0
        guard duration.isFinite, duration > 0, start.isFinite else { throw MediaError.invalid("The movie has no usable duration.") }
        let side = video["side_data_list"] as? [[String: Any]] ?? []
        let rotationValue = side.compactMap { number($0["rotation"]) }.first
            ?? number((video["tags"] as? [String: Any])?["rotate"]) ?? 0
        let rotation = ((Int(rotationValue.rounded()) % 360) + 360) % 360
        let containerStart = number(format["start_time"]) ?? start
        let seekOffset = containerStart.isFinite ? start - containerStart : 0
        var restrictions: [String] = []
        if abs(rotationValue - rotationValue.rounded()) > 0.01 || rotation % 90 != 0 { restrictions.append("non-right-angle rotation") }
        let sar = video["sample_aspect_ratio"] as? String ?? "1:1"
        if !["1:1", "0:1", "N/A"].contains(sar) { restrictions.append("non-square pixels") }
        let field = video["field_order"] as? String ?? "unknown"
        if !["unknown", "progressive"].contains(field) { restrictions.append("interlaced video") }
        let transfer = video["color_transfer"] as? String ?? "unknown"
        let primaries = video["color_primaries"] as? String ?? "unknown"
        let matrix = video["color_space"] as? String ?? "unknown"
        let range = video["color_range"] as? String ?? "unknown"
        if ["smpte2084", "arib-std-b67"].contains(transfer) || ["bt2020", "smpte431", "smpte432"].contains(primaries) {
            restrictions.append("HDR or wide-color video")
        }
        let pixel = video["pix_fmt"] as? String ?? "unknown"
        if pixel.hasPrefix("yuva") || pixel.hasPrefix("gbrap") || ["rgba", "bgra", "argb", "abgr", "pal8"].contains(pixel) {
            restrictions.append("alpha/transparency")
        }
        if w % 2 != 0 || h % 2 != 0 { restrictions.append("odd full-frame dimensions (choose an even crop)") }
        let upright = rotation == 90 || rotation == 270
        guard try SourceIdentity(url: url) == identity else { throw MediaError.sourceChanged }
        return MediaSource(url: url, identity: identity, duration: duration,
                           width: upright ? h : w, height: upright ? w : h,
                           encodedWidth: w, encodedHeight: h, rotation: rotation,
                           fps: ratio(video["avg_frame_rate"] as? String) ?? ratio(video["r_frame_rate"] as? String) ?? 0,
                           videoCodec: video["codec_name"] as? String ?? "unknown",
                           audioCount: streams.filter { ($0["codec_type"] as? String) == "audio" }.count,
                           subtitleCount: streams.filter { ($0["codec_type"] as? String) == "subtitle" }.count,
                           format: format["format_name"] as? String ?? "unknown", startTime: start, seekOffset: seekOffset,
                           encodingRestriction: restrictions.isEmpty ? nil : "Encoding is not supported for " + restrictions.joined(separator: ", ") + ".",
                           color: SourceColorDescription(pixelFormat: pixel, primaries: primaries, transfer: transfer, matrix: matrix, range: range))
    }

    public func plan(source: MediaSource, settings: EditSettings) async throws -> ExportPlan {
        try settings.validate(source: source)
        let hasColor = !settings.color.isIdentity
        let hasSpeed = abs(settings.speed - 1) > 0.000001
        try unchanged(source)
        if settings.cropEnabled || settings.method == .accurate || hasColor || hasSpeed {
            let reason = hasSpeed ? "Playing at \(EditSettings.speedLabel(settings.speed)) speed requires re-encoding." : (hasColor ? "Color correction requires re-encoding." : (settings.cropEnabled ? "Cropping requires re-encoding." : "Accurate trim uses source presentation timing."))
            return try encodedPlan(source, settings, reason: reason)
        }
        do {
            let candidate = try await copyPlan(source, settings)
            if settings.method == .fast || (abs(candidate.startShift) <= 0.25 && abs(candidate.endShift) <= 0.25) { return candidate }
            return try encodedPlan(source, settings, reason: "Nearby keyframes cannot meet the 0.25-second tolerance at both boundaries.")
        } catch {
            if Task.isCancelled || isCancellation(error) { throw MediaError.cancelled }
            if settings.method == .fast { throw error }
            return try encodedPlan(source, settings, reason: "A verifiable fast trim is unavailable. " + error.localizedDescription)
        }
    }

    public func estimate(plan: ExportPlan, progress: @escaping @Sendable (Double, String) -> Void) async throws -> [Quality: Int64] {
        try unchanged(plan.source)
        guard plan.method == .encode else { return [:] }
        let length = min(3, plan.settings.duration)
        let start = plan.settings.start + (plan.settings.duration - length) / 2
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-estimate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var result: [Quality: Int64] = [:]
        for (index, quality) in Quality.allCases.enumerated() {
            try Task.checkCancellation()
            let output = directory.appendingPathComponent(quality.rawValue + ".mp4")
            var settings = plan.settings
            settings.start = start; settings.end = start + length; settings.quality = quality
            let sample = try encodedPlan(plan.source, settings, reason: "Estimate sample")
            let lutFile = try writeLUTIfNeeded(for: sample, output: output)
            defer { if let lutFile { try? FileManager.default.removeItem(at: lutFile) } }
            _ = try await run("ffmpeg", arguments: encodeArguments(sample, output: output, lutFile: lutFile), duration: sample.outputDuration) { fraction, _ in
                progress((Double(index) + fraction) / 3, "Estimating " + quality.rawValue.lowercased())
            }
            let bytes = try SourceIdentity(url: output).size
            result[quality] = Int64((Double(bytes) * plan.settings.duration / length).rounded())
        }
        try unchanged(plan.source)
        progress(1, "Approximate sizes ready")
        return result
    }

    public func export(plan: ExportPlan, to temporaryURL: URL, progress: @escaping @Sendable (Double, String) -> Void) async throws -> ExportResult {
        try plan.settings.validate(source: plan.source)
        try unchanged(plan.source)
        guard temporaryURL.isFileURL, temporaryURL.standardizedFileURL != plan.source.url.standardizedFileURL,
              !FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw MediaError.invalid("The temporary output must be a new file, separate from the source.")
        }
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: temporaryURL) } }
        var active = plan
        var fallback = ""
        if plan.method == .copy {
            do {
                _ = try await run("ffmpeg", arguments: copyArguments(plan, output: temporaryURL), duration: plan.outputDuration, progress: progress)
                progress(0.94, "Verifying copied boundaries")
                let output = try await inspect(temporaryURL)
                let boundaries = try await verifyCopy(plan, output: output)
                try await validateOutput(plan, output: output)
                try unchanged(plan.source)
                let result = makeResult(plan, output, start: boundaries.0, end: boundaries.1,
                                        note: "Copied picture verified against decoded source frames at both ends. " + omissions(plan))
                success = true
                progress(1, "Validated")
                return result
            } catch {
                if Task.isCancelled || isCancellation(error) { throw MediaError.cancelled }
                guard plan.settings.method == .automatic else { throw error }
                try? FileManager.default.removeItem(at: temporaryURL)
                fallback = "Fast trim could not be verified; accurately re-encoded instead. "
                active = try encodedPlan(plan.source, plan.settings, reason: fallback)
                progress(0, "Fast trim verification failed; re-encoding")
            }
        }
        let lutFile = try writeLUTIfNeeded(for: active, output: temporaryURL)
        defer { if let lutFile { try? FileManager.default.removeItem(at: lutFile) } }
        _ = try await run("ffmpeg", arguments: encodeArguments(active, output: temporaryURL, lutFile: lutFile), duration: active.outputDuration, progress: progress)
        progress(0.94, "Validating encoded movie")
        let output = try await inspect(temporaryURL)
        try await validateOutput(active, output: output)
        // Accurate seek discards frames before A. Locate the first retained presentation point
        // independently, so review does not pretend arbitrary decimal A is a source frame boundary.
        let frames = try await fingerprints(active.source, from: active.settings.start, length: min(2, active.duration), origin: active.source.startTime)
        guard let first = frames.first else { throw MediaError.failed("The selected range contains no video frames.") }
        let actualStart = first.time - active.source.startTime
        let endFrames = try await fingerprints(active.source, from: max(active.settings.start, active.settings.end - 2), length: min(2, active.duration), origin: active.source.startTime)
        guard let last = endFrames.last else { throw MediaError.failed("Could not validate the selected ending frame.") }
        let actualEnd = last.time + last.duration - active.source.startTime
        try unchanged(plan.source)
        try Task.checkCancellation()
        let result = makeResult(active, output, start: actualStart, end: actualEnd,
                                note: fallback + "Encoded from the first source frame at or after A through frames before B; boundaries follow source frame timing. " + omissions(active))
        success = true
        progress(1, "Validated")
        return result
    }

    private func encodedPlan(_ source: MediaSource, _ settings: EditSettings, reason: String) throws -> ExportPlan {
        if let restriction = source.encodingRestriction {
            let oddOnly = restriction == "Encoding is not supported for odd full-frame dimensions (choose an even crop)."
            if !oddOnly || !settings.cropEnabled { throw MediaError.unavailable(restriction) }
        }
        return try ExportPlan(source: source, settings: settings, method: .encode, plannedStart: settings.start, plannedEnd: settings.end,
                          explanation: reason + " " + (source.audioCount > 1 ? "Only the first audio track is retained. " : "") +
                          (source.subtitleCount > 0 ? "Subtitles are omitted. " : "") + "Chapters and extra video tracks are omitted.")
    }

    private func copyPlan(_ source: MediaSource, _ settings: EditSettings) async throws -> ExportPlan {
        guard source.format.contains("mov"), ["h264", "hevc"].contains(source.videoCodec), abs(source.startTime) < 0.001 else {
            throw MediaError.unavailable("Fast trim currently requires an H.264/HEVC MP4 or MOV movie with a zero video start timestamp.")
        }
        let metadata = try await probe(source.url)
        let audio = (metadata["streams"] as? [[String: Any]] ?? []).filter { $0["codec_type"] as? String == "audio" }
        guard audio.allSatisfy({ ["aac", "alac", "ac3", "eac3"].contains($0["codec_name"] as? String ?? "") }) else {
            throw MediaError.unavailable("One of the audio tracks cannot be copied into the supported MP4 output.")
        }
        let beginning = try await packets(source.url, around: settings.start, duration: source.duration)
        let ending = try await packets(source.url, around: settings.end, duration: source.duration)
        let keysA = beginning.filter(\.key).map(\.pts)
        var keysB = ending.filter(\.key).map(\.pts)
        keysB.append(source.duration)
        guard let start = keysA.min(by: { abs($0 - settings.start) < abs($1 - settings.start) }),
              let cut = keysB.filter({ $0 > start }).min(by: { abs($0 - settings.end) < abs($1 - settings.end) }) else {
            throw MediaError.unavailable("No suitable keyframes were found within the bounded inspection window. Choose Accurate trim.")
        }
        // Stop at the next GOP's decode timestamp, not its presentation timestamp.
        // Otherwise reordered reference frames beyond B can leak into the output.
        let decodeCut = ending.first(where: { $0.key && abs($0.pts - cut) < 0.000001 })?.dts ?? cut
        let end = ending.filter { $0.dts < decodeCut - 0.000001 }.map { $0.pts + $0.duration }.max() ?? cut
        guard end > start else { throw MediaError.unavailable("No independently usable copy range was found.") }
        return try ExportPlan(source: source, settings: settings, method: .copy, plannedStart: max(0, start), plannedEnd: min(source.duration, end),
                          explanation: "Source quality unchanged. Planned boundaries include frame reordering; both ends are verified before saving. All audio tracks are retained. Subtitles, chapters and extra video tracks are omitted.", copyCutEnd: decodeCut)
    }

    private struct Packet { let pts: Double; let dts: Double; let duration: Double; let key: Bool }
    private func packets(_ url: URL, around time: Double, duration: Double) async throws -> [Packet] {
        let interval = decimal(max(0, time - 8)) + "%" + decimal(min(duration + 0.1, time + 8))
        let data = try await run("ffprobe", arguments: ["-v", "error", "-select_streams", "V:0", "-read_intervals", interval, "-show_packets", "-show_entries", "packet=pts_time,dts_time,duration_time,flags", "-of", "json", url.path], outputLimit: 8_000_000)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return (object["packets"] as? [[String: Any]] ?? []).compactMap { packet in
            guard let pts = number(packet["pts_time"]), let dts = number(packet["dts_time"]), let length = number(packet["duration_time"]), length > 0 else { return nil }
            return Packet(pts: pts, dts: dts, duration: length, key: (packet["flags"] as? String ?? "").contains("K"))
        }
    }

    private func encodeArguments(_ plan: ExportPlan, output: URL, lutFile: URL? = nil) -> [String] {
        // -t is an output limit, so at 0.5x two source seconds have to be allowed four output seconds.
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-ss", decimal(seek(plan.source, plan.settings.start)), "-i", plan.source.url.path,
                    "-t", decimal(plan.settings.outputDuration), "-map", "0:V:0", "-map", "0:a:0?", "-map_metadata", "-1", "-map_chapters", "-1"]
        var filters: [String] = []
        let speed = plan.settings.speed
        if abs(speed - 1) > 0.000001 { filters.append("setpts=PTS/\(decimal(speed))") }
        if let lutFile {
            filters.append("lut3d=file='\(filterEscaped(lutFile.path))':interp=trilinear")
        }
        if plan.settings.cropEnabled {
            let c = plan.settings.crop
            filters.append("crop=\(c.width):\(c.height):\(c.x):\(c.y)")
        }
        if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }
        // atempo only takes 0.5…2 per stage, so extreme speeds are reached by chaining stages.
        if abs(speed - 1) > 0.000001, plan.source.audioCount > 0 {
            args += ["-af", Self.atempoChain(for: speed).map { "atempo=" + decimal($0) }.joined(separator: ",")]
        }
        args += ["-c:v", "libx264", "-preset", "medium", "-crf", String(plan.settings.quality.crf), "-pix_fmt", "yuv420p",
                 "-fps_mode", "passthrough", "-enc_time_base", "-1", "-c:a", "aac", "-b:a", "192k", "-metadata:s:v:0", "rotate=0",
                 "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", "-f", "mp4", output.path]
        return args
    }

    /// Factors within atempo's 0.5…2 range whose product is `speed`.
    static func atempoChain(for speed: Double) -> [Double] {
        guard speed > 0, abs(speed - 1) > 0.000001 else { return [] }
        var remaining = speed
        var stages: [Double] = []
        while remaining > 2.000001 { stages.append(2); remaining /= 2 }
        while remaining < 0.499999 { stages.append(0.5); remaining /= 0.5 }
        stages.append(remaining)
        return stages
    }

    private func writeLUTIfNeeded(for plan: ExportPlan, output: URL) throws -> URL? {
        guard let lut = plan.colorLUT else { return nil }
        let url = output.deletingLastPathComponent().appendingPathComponent(".croptrimmer-color-\(UUID().uuidString).cube")
        try lut.cubeText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func filterEscaped(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: ":", with: "\\:")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private func copyArguments(_ plan: ExportPlan, output: URL) -> [String] {
        // Video decoding order can lead presentation by several frames. Separate demux inputs
        // let video stop before the next GOP without truncating the audio by that same delay.
        var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-ss", decimal(seek(plan.source, plan.plannedStart)),
                    "-t", decimal((plan.copyCutEnd ?? plan.plannedEnd) - plan.plannedStart), "-i", plan.source.url.path]
        if plan.source.audioCount > 0 {
            args += ["-ss", decimal(seek(plan.source, plan.plannedStart)), "-t", decimal(plan.duration), "-i", plan.source.url.path]
        }
        args += ["-map", "0:V:0"]
        if plan.source.audioCount > 0 { args += ["-map", "1:a"] }
        args += ["-map_chapters", "-1", "-c", "copy", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", "-f", "mp4", output.path]
        return args
    }

    /// An editor time as an input `-ss`, which FFmpeg measures from the container's start.
    private func seek(_ source: MediaSource, _ time: Double) -> Double { max(0, time + source.seekOffset) }

    private struct Fingerprint { let time: Double; let duration: Double; let hash: String }
    /// `start` counts from the first picture; `origin` is that picture's timestamp, for the absolute `-to`.
    private func fingerprints(_ source: MediaSource, from start: Double, length: Double, origin: Double = 0) async throws -> [Fingerprint] {
        let url = source.url
        let bytes = try await run("ffmpeg", arguments: ["-hide_banner", "-loglevel", "error", "-nostdin", "-copyts", "-ss", decimal(seek(source, start)), "-i", url.path,
                    "-to", decimal(origin + start + length), "-map", "0:V:0", "-an", "-fps_mode", "passthrough", "-enc_time_base", "-1", "-f", "framemd5", "pipe:1"], outputLimit: 2_000_000)
        let lines = String(decoding: bytes, as: UTF8.self).split(separator: "\n")
        var timeBase = 0.0
        var result: [Fingerprint] = []
        for line in lines {
            if line.hasPrefix("#tb 0:") { timeBase = ratio(String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)) ?? 0 }
            guard !line.hasPrefix("#") else { continue }
            let columns = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if columns.count == 6, let pts = Double(columns[2]), let duration = Double(columns[3]), timeBase > 0 {
                result.append(Fingerprint(time: pts * timeBase, duration: duration * timeBase, hash: columns[5]))
            }
        }
        return result
    }

    private func verifyCopy(_ plan: ExportPlan, output: MediaSource) async throws -> (Double, Double) {
        let firstOutput = try await fingerprints(output, from: 0, length: min(1, output.duration), origin: output.startTime)
        let lastOutput = try await fingerprints(output, from: max(0, output.duration - 1), length: min(1, output.duration), origin: output.startTime)
        let firstSource = try await fingerprints(plan.source, from: max(0, plan.plannedStart - 1), length: 3)
        let lastSource = try await fingerprints(plan.source, from: max(0, plan.plannedEnd - 2), length: 3)
        guard let first = firstOutput.first, let last = lastOutput.last else { throw MediaError.failed("The copied video has no decodable boundary frames.") }
        let aMatches = firstSource.filter { $0.hash == first.hash }
        let bMatches = lastSource.filter { $0.hash == last.hash }
        guard aMatches.count == 1, bMatches.count == 1 else {
            throw MediaError.failed("Copied boundary content could not be uniquely matched to the source.")
        }
        let a = aMatches[0].time, b = bMatches[0].time + bMatches[0].duration
        guard abs(a - plan.plannedStart) <= 0.005, abs(b - plan.plannedEnd) <= 0.005 else {
            throw MediaError.failed("The copied boundaries differ from the displayed plan. Choose Accurate trim.")
        }
        if plan.settings.method == .automatic && (abs(a - plan.settings.start) > 0.25 || abs(b - plan.settings.end) > 0.25) {
            throw MediaError.failed("The measured copy boundaries exceed the 0.25-second tolerance.")
        }
        return (a, b)
    }

    private func validateOutput(_ plan: ExportPlan, output: MediaSource) async throws {
        guard output.identity.size > 0, output.width == plan.width, output.height == plan.height,
              output.audioCount == (plan.method == .copy ? plan.source.audioCount : min(1, plan.source.audioCount)),
              output.videoCodec == (plan.method == .copy ? plan.source.videoCodec : "h264"),
              plan.method == .copy || output.rotation == 0 else {
            throw MediaError.failed("The output streams or dimensions do not match the export plan.")
        }
        // Both are measured against the output's own length. Slow motion stretches the two-frame
        // allowance by the same factor; above 1x the base allowance is kept rather than tightened,
        // which is looser than strictly necessary and never turns a good export into a failure.
        let allowance = max(0.1, plan.source.fps > 0 ? 2 / plan.source.fps : 0.1) / min(1, plan.settings.speed)
        guard abs(output.duration - plan.outputDuration) <= allowance else {
            throw MediaError.failed("The exported duration differs unexpectedly from the selected range.")
        }
        // Decode complete short outputs, and bounded beginning/end samples of longer ones.
        let starts = output.duration <= 20 ? [0.0] : [0.0, max(0, output.duration - 3)]
        for start in starts {
            _ = try await run("ffmpeg", arguments: ["-hide_banner", "-loglevel", "error", "-xerror", "-nostdin", "-ss", decimal(start), "-i", output.url.path,
                "-t", decimal(output.duration <= 20 ? output.duration : 3), "-map", "0:V:0", "-map", "0:a?", "-f", "null", "-"])
        }
    }

    private func makeResult(_ plan: ExportPlan, _ output: MediaSource, start: Double, end: Double, note: String) -> ExportResult {
        ExportResult(url: output.url, sourceURL: plan.source.url, duration: output.duration, width: output.width, height: output.height,
                     bytes: output.identity.size, method: plan.method, quality: plan.method == .encode ? plan.settings.quality : nil,
                     settings: plan.settings, actualStart: start, actualEnd: end, note: note)
    }
    private func omissions(_ plan: ExportPlan) -> String {
        (plan.method == .encode && plan.source.audioCount > 1 ? "Only the first audio track was retained. " : "") +
        (plan.source.subtitleCount > 0 ? "Subtitles were omitted. " : "") + "Chapters and extra video tracks were omitted."
    }
    private func unchanged(_ source: MediaSource) throws {
        guard try SourceIdentity(url: source.url) == source.identity else { throw MediaError.sourceChanged }
    }
    private func probe(_ url: URL) async throws -> [String: Any] {
        let data = try await run("ffprobe", arguments: ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path])
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MediaError.failed("Media inspection returned invalid data.") }
        return result
    }

    private func executable(_ name: String) throws -> URL {
        let candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/" + name),
                          Bundle.main.resourceURL?.appendingPathComponent("bin/" + name),
                          Bundle.main.resourceURL?.appendingPathComponent(name),
                          URL(fileURLWithPath: "/opt/homebrew/bin/" + name), URL(fileURLWithPath: "/usr/local/bin/" + name)].compactMap { $0 }
        guard let result = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw MediaError.unavailable("The media engine is missing. Install the packaged app containing FFmpeg and ffprobe, or install FFmpeg with Homebrew for development.")
        }
        return result
    }

    /// File-backed stdout/stderr avoid pipe deadlocks. Polling yields the actor for cancellation,
    /// bounds diagnostics, and reads FFmpeg progress without blocking the main thread.
    private func run(_ command: String, arguments: [String], duration: Double? = nil, outputLimit: Int = 16_000_000,
                     progress: @escaping @Sendable (Double, String) -> Void = { _, _ in }) async throws -> Data {
        try Task.checkCancellation()
        let token = cancellation
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CropTrimmer-process-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdout = directory.appendingPathComponent("stdout")
        let stderr = directory.appendingPathComponent("stderr")
        _ = FileManager.default.createFile(atPath: stdout.path, contents: nil)
        _ = FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let out = try FileHandle(forWritingTo: stdout), err = try FileHandle(forWritingTo: stderr)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        process.executableURL = try executable(command)
        process.arguments = arguments
        process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
        let id = UUID()
        try process.run()
        processes[id] = process
        defer { processes.removeValue(forKey: id) }
        var cancelledAt: Date?
        var exceeded = false
        while process.isRunning {
            if Task.isCancelled || token != cancellation || exceeded {
                if cancelledAt == nil { cancelledAt = Date(); process.terminate() }
                if Date().timeIntervalSince(cancelledAt!) > 1 { kill(process.processIdentifier, SIGKILL) }
            }
            let size = (try? SourceIdentity(url: stdout).size) ?? 0
            let errorSize = (try? SourceIdentity(url: stderr).size) ?? 0
            if size > outputLimit || errorSize > 2_000_000 { exceeded = true }
            // Progress lines are appended, so only the tail is read; a full re-read every poll
            // would grow quadratically over a long export.
            if let duration, duration > 0, size < outputLimit, let data = try? tail(of: stdout, size: size, bytes: 4_096) {
                let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
                if let line = lines.last(where: { $0.hasPrefix("out_time_us=") }), let micros = Double(line.dropFirst(12)) {
                    progress(min(0.92, max(0, micros / 1_000_000 / duration) * 0.92), "Processing movie")
                }
            }
            // Cancellation must still wait for child termination before removing its files.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume() }
            }
        }
        if token != cancellation || Task.isCancelled { throw MediaError.cancelled }
        // A process can exit between polls, so the limit is enforced once more on the final files.
        let finalSize = (try? SourceIdentity(url: stdout).size) ?? 0
        let finalErrorSize = (try? SourceIdentity(url: stderr).size) ?? 0
        if finalSize > outputLimit || finalErrorSize > 2_000_000 { exceeded = true }
        if exceeded { throw MediaError.failed("Media inspection exceeded its bounded output limit. Choose Accurate trim or a different source.") }
        guard process.terminationStatus == 0 else {
            let diagnostics = (try? Data(contentsOf: stderr)).map { String(decoding: $0.suffix(6_000), as: UTF8.self) } ?? ""
            throw MediaError.failed(command + " failed. " + diagnostics.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Data(contentsOf: stdout)
    }
}

private func tail(of url: URL, size: Int64, bytes: Int64) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    try handle.seek(toOffset: UInt64(max(0, size - bytes)))
    return try handle.readToEnd() ?? Data()
}
private func number(_ value: Any?) -> Double? {
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
}
private func ratio(_ text: String?) -> Double? {
    guard let text else { return nil }
    let parts = text.split(separator: "/")
    guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0, a > 0 else { return nil }
    return a / b
}
private func decimal(_ value: Double) -> String { String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value) }
private func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if case MediaError.cancelled = error { return true }
    return false
}
