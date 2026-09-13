import SwiftUI
import AVKit
import CropTrimmerCore

struct ReviewView: View {
    @ObservedObject var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var originalImage: NSImage?
    @State private var resultImage: NSImage?
    @State private var previewError: String?
    @State private var originalDetails = ""
    @State private var resultPlayer: AVPlayer?
    private var selected: ExportResult? { model.results.first { $0.id == selectedID } ?? model.results.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Exports").font(.title2); Spacer(); Button("Done") { resultPlayer?.pause(); dismiss() }.keyboardShortcut(.defaultAction) }
            if let result = selected {
                HStack(alignment: .top, spacing: 12) {
                    comparison("Original", image: originalImage)
                    if let player = resultPlayer {
                        VStack(alignment: .leading) { Text("Exported · \(result.width) × \(result.height)").font(.headline); PlayerSurface(player: player).frame(height: 230).background(.black) }
                    } else { comparison("Exported · \(result.width) × \(result.height)", image: resultImage) }
                }
                if !originalDetails.isEmpty { Text("Original: " + originalDetails).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                if let previewError { Text(previewError).font(.caption).foregroundStyle(.orange) }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.url.lastPathComponent).font(.headline).textSelection(.enabled)
                        Text("\(timeLabel(result.duration)) · \(result.width) × \(result.height) · \(byteLabel(result.bytes))").monospacedDigit()
                        Text(result.method == .copy ? "Fast trim · source quality unchanged" : "Re-encoded · \(result.quality?.rawValue ?? "Balanced")")
                        Text("Requested: \(timeLabel(result.settings.start)) – \(timeLabel(result.settings.end))").monospacedDigit()
                        Text(String(format: "Actual boundary shifts: %+.3f s / %+.3f s", result.actualStart - result.settings.start, result.actualEnd - result.settings.end)).monospacedDigit()
                        if !result.note.isEmpty { Text(result.note).foregroundStyle(.secondary) }
                    }.font(.caption)
                    Spacer()
                    VStack {
                        Button("Play result") { resultPlayer?.pause(); let player = AVPlayer(url: result.url); resultPlayer = player; player.play() }
                        if let resultPlayer { Button("Pause result") { resultPlayer.pause() } }
                        Button("Reveal in Finder") { model.reveal(result.url) }
                    }
                }
            }
            Divider()
            List(model.results.reversed()) { result in
                Button { resultPlayer?.pause(); resultPlayer = nil; selectedID = result.id } label: {
                    HStack {
                        Image(systemName: result.settings.cropEnabled ? "crop" : "scissors")
                        VStack(alignment: .leading, spacing: 3) { Text(result.url.lastPathComponent).lineLimit(1); Text("\(timeLabel(result.duration)) · \(result.width) × \(result.height) · \(result.quality?.rawValue ?? "Source quality")").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(byteLabel(result.bytes)).monospacedDigit()
                        if result.id == selected?.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }.contentShape(Rectangle()).padding(.vertical, 3)
                }.buttonStyle(.plain)
            }.listStyle(.inset).frame(minHeight: 90, maxHeight: 160)
        }.padding(20).frame(width: 780).preferredColorScheme(.dark)
            .task(id: selected?.id) { await loadPreviews() }
            .onDisappear { resultPlayer?.pause() }
    }

    private func comparison(_ title: String, image: NSImage?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            ZStack {
                Color.black
                if let image { Image(nsImage: image).resizable().scaledToFit() }
                else { Image(systemName: "film").foregroundStyle(.secondary) }
            }.frame(height: 230)
        }.frame(maxWidth: .infinity)
    }

    @MainActor private func loadPreviews() async {
        guard let result = selected else { return }
        originalImage = nil; resultImage = nil; previewError = nil; originalDetails = ""
        let resultTime = min(result.duration / 2, max(0, result.duration - 0.01))
        do {
            async let original = frame(url: result.sourceURL, time: result.actualStart + resultTime)
            async let exported = frame(url: result.url, time: resultTime)
            let (sourceImage, outputImage) = try await (original, exported)
            guard !Task.isCancelled, selected?.id == result.id else { return }
            originalImage = sourceImage; resultImage = outputImage
            let asset = AVURLAsset(url: result.sourceURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let upright = size.applying(transform)
                let attributes = try FileManager.default.attributesOfItem(atPath: result.sourceURL.path)
                let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard !Task.isCancelled, selected?.id == result.id else { return }
                originalDetails = "\(timeLabel(duration.seconds)) · \(Int(abs(upright.width))) × \(Int(abs(upright.height))) · \(byteLabel(bytes))"
            }
        } catch {
            guard !Task.isCancelled else { return }
            previewError = "A comparison frame could not be loaded. Use Play result or Reveal in Finder to inspect the saved movie."
        }
    }

    private func frame(url: URL, time: Double) async throws -> NSImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 600)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let origin = try await NativeTimeline.videoOrigin(in: generator.asset)
        let result = try await generator.image(at: CMTime(seconds: origin + time, preferredTimescale: 60000))
        return NSImage(cgImage: result.image, size: .zero)
    }
}
