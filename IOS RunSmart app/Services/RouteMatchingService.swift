import CoreLocation
import Foundation

enum RouteMatchingService {
    nonisolated static let minimumRoutePoints = 6
    /// A route point counts as covered when the run passed within this distance of it.
    nonisolated static let coverageToleranceMeters = 35.0
    /// Longest or shortest a route variant may be, relative to the route.
    nonisolated static let maxVariantDistanceRatio = 0.25

    /// Picks the route the run counts toward. A route the run counts toward beats one it only
    /// resembles, a benchmark route beats a plain saved route, and a full match beats a variant.
    nonisolated static func match(
        run: RecordedRun,
        savedRoutes: [SavedRoute],
        benchmarkRouteIDs: Set<UUID> = []
    ) -> RouteMatchResult? {
        guard run.routePoints.count >= minimumRoutePoints else { return nil }
        let routes = savedRoutes.filter { $0.points.count >= minimumRoutePoints && $0.distanceMeters > 0 }
        guard !routes.isEmpty else { return nil }

        let candidates = routes.map { candidate(for: $0, run: run) }
        guard let best = candidates.max(by: { preference($0, benchmarkRouteIDs) < preference($1, benchmarkRouteIDs) }) else {
            return nil
        }

        return RouteMatchResult(
            routeID: best.confidence.countsTowardRoute ? best.route.id : nil,
            candidateRouteID: best.route.id,
            confidence: best.confidence,
            distanceDeltaMeters: best.distanceDeltaMeters,
            startDeltaMeters: best.startDeltaMeters,
            endDeltaMeters: best.endDeltaMeters,
            shapeSimilarity: best.shapeSimilarity,
            isReversed: best.isReversed,
            routeCoverage: best.routeCoverage
        )
    }

    nonisolated private static func preference(_ candidate: Candidate, _ benchmarkRouteIDs: Set<UUID>) -> (Int, Int, Int, Double) {
        let counts = candidate.confidence.countsTowardRoute
        return (
            counts ? 1 : 0,
            counts && benchmarkRouteIDs.contains(candidate.route.id) ? 1 : 0,
            candidate.confidence.rank,
            candidate.score
        )
    }

    /// The stored result for the run a route was saved from: the route is that run's
    /// own trace, so it matches with zero deltas instead of being re-scored.
    nonisolated static func exactMatch(routeID: UUID) -> RouteMatchResult {
        RouteMatchResult(
            routeID: routeID,
            candidateRouteID: routeID,
            confidence: .matched,
            distanceDeltaMeters: 0,
            startDeltaMeters: 0,
            endDeltaMeters: 0,
            shapeSimilarity: 1,
            isReversed: false,
            routeCoverage: 1
        )
    }

    nonisolated private struct Candidate {
        var route: SavedRoute
        var distanceDeltaMeters: Double
        var startDeltaMeters: Double
        var endDeltaMeters: Double
        var shapeSimilarity: Double
        var routeCoverage: Double
        var isReversed: Bool
        var score: Double
        var confidence: RouteMatchConfidence
    }

    nonisolated private static func candidate(for route: SavedRoute, run: RecordedRun) -> Candidate {
        let forwardStart = distance(from: run.routePoints.first, to: route.points.first)
        let forwardEnd = distance(from: run.routePoints.last, to: route.points.last)
        let reverseStart = distance(from: run.routePoints.first, to: route.points.last)
        let reverseEnd = distance(from: run.routePoints.last, to: route.points.first)
        let isReversed = (reverseStart + reverseEnd) < (forwardStart + forwardEnd)
        let routePoints = isReversed ? Array(route.points.reversed()) : route.points
        let shapeSimilarity = shapeSimilarity(
            runPoints: Array(run.routePoints),
            routePoints: routePoints
        )
        let distanceDeltaMeters = abs(run.distanceMeters - route.distanceMeters)
        let startDeltaMeters = isReversed ? reverseStart : forwardStart
        let endDeltaMeters = isReversed ? reverseEnd : forwardEnd
        // Coverage is direction-free; only worth the cost when the run starts and ends nearby.
        let routeCoverage = startDeltaMeters <= 300 && endDeltaMeters <= 300
            ? coverage(of: route.points, by: run.routePoints)
            : 0
        let endpointScore = max(0, 1 - ((startDeltaMeters + endDeltaMeters) / 600))
        let distanceScore = max(0, 1 - (distanceDeltaMeters / max(route.distanceMeters * 0.25, 1)))
        let score = (max(shapeSimilarity, routeCoverage) * 0.50) + (endpointScore * 0.30) + (distanceScore * 0.20)
        let confidence = confidence(
            distanceRatio: distanceDeltaMeters / max(route.distanceMeters, 1),
            startDeltaMeters: startDeltaMeters,
            endDeltaMeters: endDeltaMeters,
            shapeSimilarity: shapeSimilarity,
            routeCoverage: routeCoverage
        )

        return Candidate(
            route: route,
            distanceDeltaMeters: distanceDeltaMeters,
            startDeltaMeters: startDeltaMeters,
            endDeltaMeters: endDeltaMeters,
            shapeSimilarity: shapeSimilarity,
            routeCoverage: routeCoverage,
            isReversed: isReversed,
            score: score,
            confidence: confidence
        )
    }

    nonisolated private static func confidence(
        distanceRatio: Double,
        startDeltaMeters: Double,
        endDeltaMeters: Double,
        shapeSimilarity: Double,
        routeCoverage: Double
    ) -> RouteMatchConfidence {
        let sameStartAndFinish = startDeltaMeters <= 120 && endDeltaMeters <= 120

        // The 8% distance limit for a full match is unchanged. Coverage lets a run with a short
        // detour still pass the shape check, which compares points by index and drifts after one.
        if sameStartAndFinish,
           distanceRatio <= 0.08,
           shapeSimilarity >= 0.74 || routeCoverage >= 0.90 {
            return .matched
        }

        if sameStartAndFinish,
           distanceRatio <= maxVariantDistanceRatio,
           routeCoverage >= 0.85 {
            return .routeVariant
        }

        if distanceRatio <= 0.18,
           startDeltaMeters <= 300,
           endDeltaMeters <= 300,
           shapeSimilarity >= 0.52 || routeCoverage >= 0.60 {
            return .possibleMatch
        }

        return .noMatch
    }

    /// Share of the route's length that `trace` passes within `coverageToleranceMeters` of.
    /// Both lines are resampled by distance so dense GPS stretches do not dominate.
    nonisolated private static func coverage(of route: [RunRoutePoint], by trace: [RunRoutePoint]) -> Double {
        guard let origin = route.first else { return 0 }
        let routeSamples = resampled(projected(route, origin: origin))
        let traceSamples = resampled(projected(trace, origin: origin))
        guard !routeSamples.isEmpty, !traceSamples.isEmpty else { return 0 }

        let tolerance = coverageToleranceMeters * coverageToleranceMeters
        let covered = routeSamples.filter { point in
            traceSamples.contains { other in
                let dx = other.x - point.x
                let dy = other.y - point.y
                return dx * dx + dy * dy <= tolerance
            }
        }
        return Double(covered.count) / Double(routeSamples.count)
    }

    nonisolated private struct PlanePoint {
        var x: Double
        var y: Double
    }

    /// Local flat projection in meters around `origin`; accurate to well under a meter over a run.
    nonisolated private static func projected(_ points: [RunRoutePoint], origin: RunRoutePoint) -> [PlanePoint] {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(origin.latitude * .pi / 180)
        return points.map { point in
            PlanePoint(
                x: (point.longitude - origin.longitude) * metersPerDegreeLongitude,
                y: (point.latitude - origin.latitude) * metersPerDegreeLatitude
            )
        }
    }

    /// Evenly spaced points along the line, at most about `maxCount` of them.
    nonisolated private static func resampled(_ points: [PlanePoint], maxCount: Int = 200) -> [PlanePoint] {
        guard points.count > 1, let first = points.first, let last = points.last else { return points }
        var length = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            length += hypot(b.x - a.x, b.y - a.y)
        }
        guard length > 0 else { return [first] }

        let spacing = max(10, length / Double(maxCount - 1))
        var result = [first]
        var travelled = 0.0
        var nextSampleAt = spacing
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = hypot(b.x - a.x, b.y - a.y)
            guard segment > 0 else { continue }
            while nextSampleAt <= travelled + segment {
                let t = (nextSampleAt - travelled) / segment
                result.append(PlanePoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                nextSampleAt += spacing
            }
            travelled += segment
        }
        result.append(last)
        return result
    }

    nonisolated private static func shapeSimilarity(runPoints: [RunRoutePoint], routePoints: [RunRoutePoint]) -> Double {
        let runSample = sample(runPoints, count: 20)
        let routeSample = sample(routePoints, count: 20)
        guard runSample.count == routeSample.count, !runSample.isEmpty else { return 0 }

        let distances = zip(runSample, routeSample).map { distance(from: $0.0, to: $0.1) }
        let averageDistance = distances.reduce(0, +) / Double(distances.count)
        return max(0, min(1, 1 - (averageDistance / 220)))
    }

    nonisolated private static func sample(_ points: [RunRoutePoint], count: Int) -> [RunRoutePoint] {
        guard points.count > count, count > 1 else { return points }
        let lastIndex = points.count - 1
        let step = Double(lastIndex) / Double(count - 1)
        return (0..<count).map { index in
            points[index == count - 1 ? lastIndex : Int((Double(index) * step).rounded())]
        }
    }

    nonisolated private static func distance(from lhs: RunRoutePoint?, to rhs: RunRoutePoint?) -> Double {
        guard let lhs, let rhs else { return .greatestFiniteMagnitude }
        return CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}
