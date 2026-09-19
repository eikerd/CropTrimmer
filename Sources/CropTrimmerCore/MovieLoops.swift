import Foundation

/// A queue entry with its own temporal, crop, and encoding settings.
public struct MovieLoop: Identifiable, Equatable, Sendable {
    public let id: UUID
    public fileprivate(set) var settings: EditSettings
    public var start: Double { settings.start }
    public var end: Double { settings.end }
    public var duration: Double { end - start }

    fileprivate init(start: Double, end: Double, settings: EditSettings) {
        id = UUID(); self.settings = settings
        self.settings.start = start; self.settings.end = end
    }
    fileprivate mutating func setRange(start: Double, end: Double) {
        settings.start = start; settings.end = end
    }
}

/// Owns up to three independent ranges and keeps every range inside the source.
public struct MovieLoops: Equatable, Sendable {
    public static let maximumCount = 3
    public private(set) var ranges: [MovieLoop] = []
    public private(set) var selectedID: UUID?
    public let sourceDuration: Double
    public var selected: MovieLoop? { ranges.first { $0.id == selectedID } }

    public init(sourceDuration: Double = 0, defaultLength: Double = 5, settings: EditSettings = EditSettings()) {
        self.sourceDuration = sourceDuration.isFinite && sourceDuration > 0 ? sourceDuration : 0
        if self.sourceDuration > 0 {
            let first = MovieLoop(start: 0, end: Self.length(defaultLength, within: self.sourceDuration), settings: settings)
            ranges = [first]; selectedID = first.id
        }
    }

    @discardableResult public mutating func select(_ id: UUID) -> Bool {
        guard ranges.contains(where: { $0.id == id }) else { return false }
        selectedID = id
        return true
    }

    /// A new loop starts at the selected loop's out point (B), so pressing + repeatedly chains loops
    /// end to end. Whatever remains after B — a full length or a fraction of a second — is the new
    /// loop's range, running to the end of the movie when less than a full length is left. Only when
    /// the selected loop already ends at the movie's end (nothing beyond float dust remains) does it
    /// fall back to an unused spot; overlap is allowed and remains editable.
    @discardableResult public mutating func add(length requestedLength: Double) -> Bool {
        guard ranges.count < Self.maximumCount, sourceDuration > 0 else { return false }
        let length = Self.length(requestedLength, within: sourceDuration)
        if let out = selected?.end, sourceDuration - out > 0.001 {
            let loop = MovieLoop(start: out, end: min(out + length, sourceDuration), settings: selected?.settings ?? EditSettings())
            ranges.append(loop); selectedID = loop.id
            return true
        }
        let latestStart = sourceDuration - length
        var start = min(selected?.end ?? 0, latestStart)
        if ranges.contains(where: { abs($0.start - start) < 0.001 && abs($0.duration - length) < 0.001 }), latestStart > 0 {
            let points = ([0, latestStart] + ranges.map(\.start).filter { $0 <= latestStart }).sorted()
            let gaps = zip(points, points.dropFirst()).map { ($0, $1) }
            if let widest = gaps.max(by: { $0.1 - $0.0 < $1.1 - $1.0 }) {
                start = (widest.0 + widest.1) / 2
            }
        }
        let loop = MovieLoop(start: start, end: start + length, settings: selected?.settings ?? EditSettings())
        ranges.append(loop); selectedID = loop.id
        return true
    }

    /// Removes any loop but the last one. Removing the selected loop selects its neighbour;
    /// removing another loop leaves the selection alone.
    @discardableResult public mutating func remove(_ id: UUID) -> Bool {
        guard ranges.count > 1, let index = ranges.firstIndex(where: { $0.id == id }) else { return false }
        ranges.remove(at: index)
        if selectedID == id { selectedID = ranges[min(index, ranges.count - 1)].id }
        return true
    }

    @discardableResult public mutating func removeSelected() -> Bool {
        guard let selectedID else { return false }
        return remove(selectedID)
    }

    @discardableResult public mutating func updateSelected(start: Double, end: Double) -> Bool {
        guard start.isFinite, end.isFinite, start >= 0, end > start, end <= sourceDuration,
              let index = ranges.firstIndex(where: { $0.id == selectedID }) else { return false }
        ranges[index].setRange(start: start, end: end)
        return true
    }

    @discardableResult public mutating func updateSelected(settings: EditSettings) -> Bool {
        guard updateSelected(start: settings.start, end: settings.end),
              let index = ranges.firstIndex(where: { $0.id == selectedID }) else { return false }
        ranges[index].settings = settings
        return true
    }

    @discardableResult public mutating func update(id: UUID, settings: EditSettings) -> Bool {
        guard settings.start.isFinite, settings.end.isFinite, settings.start >= 0,
              settings.end > settings.start, settings.end <= sourceDuration,
              let index = ranges.firstIndex(where: { $0.id == id }) else { return false }
        ranges[index].settings = settings
        return true
    }

    /// The shortest a loop gets when it is pushed against the end of the movie.
    public static let minimumLength = 0.1

    /// The drag's original range is used on every update, preventing cumulative drift. A loop pushed
    /// past the end of the movie keeps its start and runs to the end, shortening instead of stopping;
    /// dragging it back restores the original length.
    @discardableResult public mutating func move(_ id: UUID, originalStart: Double, originalEnd: Double, by delta: Double) -> Bool {
        guard originalStart.isFinite, originalEnd.isFinite, delta.isFinite,
              originalStart >= 0, originalEnd > originalStart, originalEnd <= sourceDuration,
              let index = ranges.firstIndex(where: { $0.id == id }) else { return false }
        let duration = originalEnd - originalStart
        let latestStart = max(0, sourceDuration - min(duration, Self.minimumLength))
        let start = min(max(0, originalStart + delta), latestStart)
        ranges[index].setRange(start: start, end: min(start + duration, sourceDuration))
        selectedID = id
        return true
    }

    @discardableResult public mutating func resizeSelected(to requestedLength: Double) -> Bool {
        guard let current = selected else { return false }
        let length = Self.length(requestedLength, within: sourceDuration)
        let start = min(current.start, sourceDuration - length)
        return updateSelected(start: start, end: start + length)
    }

    private static func length(_ requested: Double, within source: Double) -> Double {
        min(source, requested.isFinite && requested > 0 ? requested : 5)
    }
}
