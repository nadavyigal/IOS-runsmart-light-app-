import Foundation
import CoreLocation
#if canImport(HealthKit)
import HealthKit
#endif

/// Everything RunSmart writes to Apple Health for one recorded run, as plain values.
/// HealthKit cannot write in unit tests, so the decisions (which pauses, which distance
/// samples, whether there is energy or a route) are made here and tested; the service
/// only turns this plan into HealthKit objects.
struct HealthKitWorkoutPlan {
    enum PauseEventKind: Equatable {
        case pause
        case resume
    }

    struct PauseEvent: Equatable {
        var kind: PauseEventKind
        var date: Date
    }

    /// Distance covered while moving, over one stretch between pauses.
    struct DistanceSample: Equatable {
        var start: Date
        var end: Date
        var meters: Double
    }

    struct EnergySample: Equatable {
        var start: Date
        var end: Date
        var kilocalories: Double
    }

    static let runIDMetadataKey = "RunSmartRunID"
    static let sourceMetadataKey = "RunSmartSource"
    static let energyEstimateMetadataKey = "RunSmartEnergyIsEstimate"

    var runID: UUID
    var start: Date
    var end: Date
    var pauseEvents: [PauseEvent]
    var distanceSamples: [DistanceSample]
    /// Nil unless RunSmart has an estimate. Never invented.
    var energy: EnergySample?
    /// Continuous stretches of the route, each with at least two points. Empty when the
    /// route as a whole has fewer than two usable points.
    var routeSegments: [[RunRoutePoint]]

    static func make(for run: RecordedRun) -> HealthKitWorkoutPlan {
        let start = run.startedAt
        let end = max(run.endedAt, run.startedAt)
        let pauses = normalizedPauses(run.pauseIntervals ?? [], start: start, end: end)
        let active = activeIntervals(excluding: pauses, start: start, end: end)
        let segments = routeSegments(from: run.routePoints, start: start, end: end)

        var energy: EnergySample?
        if let kilocalories = run.estimatedActiveKilocalories, kilocalories.isFinite, kilocalories > 0, end > start {
            energy = EnergySample(start: start, end: end, kilocalories: kilocalories)
        }

        return HealthKitWorkoutPlan(
            runID: run.id,
            start: start,
            end: end,
            pauseEvents: pauseEvents(for: pauses, workoutEnd: end),
            distanceSamples: distanceSamples(
                totalMeters: run.distanceMeters,
                active: active,
                routePoints: run.routePoints
            ),
            energy: energy,
            routeSegments: segments
        )
    }

    // MARK: Pauses

    /// Clamped to the workout, sorted, and merged so no two overlap. Empty and reversed
    /// intervals are dropped.
    static func normalizedPauses(_ intervals: [RunPauseInterval], start: Date, end: Date) -> [DateInterval] {
        let clamped: [DateInterval] = intervals.compactMap { interval in
            let from = max(interval.start, start)
            let to = min(interval.end, end)
            guard to > from else { return nil }
            return DateInterval(start: from, end: to)
        }.sorted { $0.start < $1.start }

        var merged: [DateInterval] = []
        for pause in clamped {
            if let last = merged.last, pause.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, pause.end))
            } else {
                merged.append(pause)
            }
        }
        return merged
    }

    /// A pause event at each pause start and a resume at its end. A pause still open when the
    /// run ended (it reaches the workout end) gets no resume: the run finished while paused.
    static func pauseEvents(for pauses: [DateInterval], workoutEnd: Date) -> [PauseEvent] {
        pauses.flatMap { pause -> [PauseEvent] in
            var events = [PauseEvent(kind: .pause, date: pause.start)]
            if pause.end < workoutEnd {
                events.append(PauseEvent(kind: .resume, date: pause.end))
            }
            return events
        }
    }

    /// The stretches of the workout that are not paused, in order.
    static func activeIntervals(excluding pauses: [DateInterval], start: Date, end: Date) -> [DateInterval] {
        guard end > start else { return [] }
        var result: [DateInterval] = []
        var cursor = start
        for pause in pauses {
            if pause.start > cursor {
                result.append(DateInterval(start: cursor, end: pause.start))
            }
            cursor = max(cursor, pause.end)
        }
        if end > cursor {
            result.append(DateInterval(start: cursor, end: end))
        }
        return result
    }

    // MARK: Distance

    /// One sample per active stretch, so nothing is counted during a pause. The meters follow
    /// the route legs inside each stretch, scaled so the samples add up to the run distance
    /// exactly. Without a route they follow the length of each stretch in time.
    static func distanceSamples(
        totalMeters: Double,
        active: [DateInterval],
        routePoints: [RunRoutePoint]
    ) -> [DistanceSample] {
        guard totalMeters.isFinite, totalMeters > 0, !active.isEmpty else { return [] }

        var weights = [Double](repeating: 0, count: active.count)
        var previous: RunRoutePoint?
        for point in routePoints where isUsable(point) {
            defer { previous = point }
            guard let from = previous, point.startsNewSegment != true else { continue }
            let leg = CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            guard leg.isFinite, leg > 0 else { continue }
            let midpoint = from.timestamp.addingTimeInterval(point.timestamp.timeIntervalSince(from.timestamp) / 2)
            weights[nearestIndex(of: midpoint, in: active)] += leg
        }

        if weights.reduce(0, +) <= 0 {
            weights = active.map(\.duration)
        }
        let weightSum = weights.reduce(0, +)
        guard weightSum > 0 else { return [] }

        var samples: [DistanceSample] = []
        for (index, interval) in active.enumerated() where weights[index] > 0 && interval.duration > 0 {
            samples.append(DistanceSample(
                start: interval.start,
                end: interval.end,
                meters: totalMeters * weights[index] / weightSum
            ))
        }
        // Float rounding: the last sample takes the remainder so the sum is the run distance.
        if let last = samples.indices.last {
            let others = samples.dropLast().reduce(0) { $0 + $1.meters }
            samples[last].meters = max(0, totalMeters - others)
        }
        return samples
    }

    private static func nearestIndex(of date: Date, in intervals: [DateInterval]) -> Int {
        var best = 0
        var bestGap = TimeInterval.greatestFiniteMagnitude
        for (index, interval) in intervals.enumerated() {
            let gap: TimeInterval
            if date < interval.start {
                gap = interval.start.timeIntervalSince(date)
            } else if date > interval.end {
                gap = date.timeIntervalSince(interval.end)
            } else {
                return index
            }
            if gap < bestGap {
                bestGap = gap
                best = index
            }
        }
        return best
    }

    // MARK: Route

    static func isUsable(_ point: RunRoutePoint) -> Bool {
        point.latitude.isFinite && point.longitude.isFinite
            && abs(point.latitude) <= 90 && abs(point.longitude) <= 180
            && point.horizontalAccuracy >= 0
    }

    /// Splits at every segment start, including boundaries on rejected fixes. Export timestamps
    /// are clamped to the workout: an otherwise fresh initial GPS fix can predate recording.
    /// Duplicate and reversed timestamps are dropped without sorting the traveled route.
    static func routeSegments(from points: [RunRoutePoint], start: Date? = nil, end: Date? = nil) -> [[RunRoutePoint]] {
        if let start, let end, end <= start { return [] }
        var segments: [[RunRoutePoint]] = []
        var current: [RunRoutePoint] = []
        var previousTimestamp: Date?
        var pendingSegmentStart = false
        for original in points {
            pendingSegmentStart = pendingSegmentStart || original.startsNewSegment == true
            guard isUsable(original), original.timestamp.timeIntervalSinceReferenceDate.isFinite else { continue }
            var point = original
            if let start { point.timestamp = max(point.timestamp, start) }
            if let end { point.timestamp = min(point.timestamp, end) }
            if let previousTimestamp, point.timestamp <= previousTimestamp { continue }
            if pendingSegmentStart {
                if !current.isEmpty {
                    segments.append(current)
                    current = []
                }
                point.startsNewSegment = true
            }
            current.append(point)
            previousTimestamp = point.timestamp
            pendingSegmentStart = false
        }
        if !current.isEmpty { segments.append(current) }
        return segments.filter { $0.count >= 2 }
    }

    static func location(for point: RunRoutePoint) -> CLLocation {
        CLLocation(
            coordinate: point.coordinate,
            altitude: point.altitude ?? 0,
            horizontalAccuracy: point.horizontalAccuracy,
            // Altitude comes from GPS without a recorded accuracy; mark it unknown when absent.
            verticalAccuracy: point.altitude == nil ? -1 : 10,
            timestamp: point.timestamp
        )
    }

    // MARK: Import

    /// True when a Health workout was written by RunSmart for a run that is still stored on this
    /// device. A workout whose run is gone (for example after a reinstall) is not skipped.
    static func isStoredLocally(metadata: [String: Any]?, localRunIDs: Set<UUID>) -> Bool {
        guard let value = metadata?[runIDMetadataKey] as? String, let id = UUID(uuidString: value) else { return false }
        return localRunIDs.contains(id)
    }

    // MARK: Metadata

    #if canImport(HealthKit)
    /// Kept on every workout so imports can recognise RunSmart's own runs.
    static func metadata(for run: RecordedRun) -> [String: Any] {
        [
            sourceMetadataKey: run.source.rawValue,
            runIDMetadataKey: run.id.uuidString,
            HKMetadataKeyIndoorWorkout: false
        ]
    }
    #endif
}
