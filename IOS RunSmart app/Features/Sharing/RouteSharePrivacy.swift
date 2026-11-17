import Foundation
import CoreLocation

/// Pure helpers for the route map on a shared run. The run share includes the map by default, and
/// the first and last 200 m of the route are always cut so the image does not show where the
/// runner starts or finishes.
enum RouteSharePrivacy {
    /// Route length hidden at each end of a shared map.
    static let trimMeters: Double = 200
    /// A shared route must keep at least this much line after both ends are cut, otherwise it is
    /// a stub that points at the start. So a route needs `2 * trimMeters + minimumVisibleMeters`.
    static let minimumVisibleMeters: Double = 50

    static let privacyNote = "The first and last 200 m are kept private."

    /// Coach upload cutoff. The PRD says "~1 km"; this is the one constant.
    static let coachUploadMinimumRunMeters: Double = 1_000
    /// Inclusive radius drawn once per run for the coach upload privacy zone.
    static let coachUploadRadiusRange: ClosedRange<Double> = 200...300

    /// Forces a sample into the coach-upload radius so a bad source cannot hide less than 200 m.
    static func coachUploadRadius(_ sample: Double) -> Double {
        guard sample.isFinite else { return coachUploadRadiusRange.lowerBound }
        return min(max(sample, coachUploadRadiusRange.lowerBound), coachUploadRadiusRange.upperBound)
    }

    static func randomCoachUploadRadius(using generator: inout some RandomNumberGenerator) -> Double {
        Double.random(in: coachUploadRadiusRange, using: &generator)
    }

    /// Points outside a disk around the first point and a disk around the last point.
    ///
    /// Reuses the same great-circle distance as `shareableRoute` (`CLLocation.distance`) and does
    /// not reuse that function's along-path cut or its segment break. A point that passes the start
    /// or finish again is dropped wherever it sits. The input array is not mutated. Kept points stay
    /// in order with their original `startsNewSegment` flags, so a map may draw a straight line
    /// across the gap. That gap is accepted for the coach upload.
    static func pointsOutsideEndpointRadius(_ points: [RunRoutePoint], radiusMeters: Double) -> [RunRoutePoint] {
        let copy = points
        guard copy.count >= 2, radiusMeters.isFinite, radiusMeters > 0 else { return [] }
        guard CLLocationCoordinate2DIsValid(copy[0].coordinate),
              CLLocationCoordinate2DIsValid(copy[copy.count - 1].coordinate) else { return [] }
        let origin = CLLocation(latitude: copy[0].latitude, longitude: copy[0].longitude)
        let finish = CLLocation(latitude: copy[copy.count - 1].latitude, longitude: copy[copy.count - 1].longitude)
        return copy.filter { point in
            guard point.latitude.isFinite, point.longitude.isFinite else { return false }
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            return location.distance(from: origin) > radiusMeters
                && location.distance(from: finish) > radiusMeters
        }
    }

    /// Distance along the route. Never counts the jump across a segment start (a pause or resume).
    static func pathLengthMeters(_ points: [RunRoutePoint]) -> Double {
        cumulativeMeters(points).last ?? 0
    }

    /// The points that may appear on a shared map, or nil when the route is too short to show
    /// anything once both ends are cut (under 400 m of route, plus a small visible remainder).
    ///
    /// Two cuts apply. The first and last `trimMeters` of route are dropped. Then every point within
    /// `trimMeters` in a straight line of the first or the last point is dropped too, so a loop that
    /// passes the start or finish later does not show where they are. Where points were dropped in the
    /// middle, the next kept point starts a new segment, so no line is drawn across the hidden area.
    static func shareableRoute(
        _ points: [RunRoutePoint],
        trimMeters: Double = RouteSharePrivacy.trimMeters
    ) -> [RunRoutePoint]? {
        guard points.count >= 2 else { return nil }
        let cumulative = cumulativeMeters(points)
        let total = cumulative.last ?? 0
        guard total >= 2 * trimMeters + minimumVisibleMeters else { return nil }
        let origin = CLLocation(latitude: points[0].latitude, longitude: points[0].longitude)
        let finish = CLLocation(latitude: points[points.count - 1].latitude, longitude: points[points.count - 1].longitude)
        var kept: [RunRoutePoint] = []
        var droppedSinceLastKept = false
        for (index, point) in points.enumerated() {
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            let isShown = cumulative[index] >= trimMeters
                && total - cumulative[index] >= trimMeters
                && location.distance(from: origin) >= trimMeters
                && location.distance(from: finish) >= trimMeters
            guard isShown else {
                droppedSinceLastKept = true
                continue
            }
            var shown = point
            if droppedSinceLastKept, !kept.isEmpty { shown.startsNewSegment = true }
            droppedSinceLastKept = false
            kept.append(shown)
        }
        guard RoutePointSegments.split(kept).contains(where: { $0.count >= 2 }) else { return nil }
        return kept
    }

    /// Distance from the first point to each point, along the route, not counting segment jumps.
    private static func cumulativeMeters(_ points: [RunRoutePoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: points.count)
        var total = 0.0
        for index in 1..<points.count {
            if points[index].startsNewSegment != true {
                let previous = points[index - 1]
                let current = points[index]
                total += CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            }
            result[index] = total
        }
        return result
    }
}

/// Splits a route into continuous stretches. A point with `startsNewSegment` begins a new one.
enum RoutePointSegments {
    static func split(_ points: [RunRoutePoint]) -> [[RunRoutePoint]] {
        var segments: [[RunRoutePoint]] = []
        var current: [RunRoutePoint] = []
        for point in points {
            if point.startsNewSegment == true, !current.isEmpty {
                segments.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    /// Stretches long enough to draw as a line.
    static func drawableSegments(_ points: [RunRoutePoint]) -> [[RunRoutePoint]] {
        split(points).filter { $0.count >= 2 }
    }
}

extension ProgressSharePayload {
    /// The payload for a share that includes the route map. Only the privacy line changes.
    func includingRouteMap() -> ProgressSharePayload {
        var copy = self
        copy.privacyNote = RouteSharePrivacy.privacyNote
        return copy
    }
}
