import AVFoundation

/// AVAssetTrack.timeRange can include an empty leading edit. Use the first real
/// video segment so the editor's zero is a picture, not the beginning of that gap.
public enum NativeTimeline {
    public static func videoOrigin(in asset: AVAsset) async throws -> Double {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw MediaError.unavailable("The native viewer found no video track.") }
        let segments = try await track.load(.segments)
        let origins = segments.filter { !$0.isEmpty }.map { $0.timeMapping.target.start.seconds }.filter(\.isFinite)
        if let start = origins.min() { return start }
        let range = try await track.load(.timeRange)
        guard range.start.seconds.isFinite else { throw MediaError.unavailable("The native viewer cannot map this movie's timeline.") }
        return range.start.seconds
    }
}
