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
        return match(run: run, preparedRoutes: prepare(savedRoutes), benchmarkRouteIDs: benchmarkRouteIDs)
    }

    /// A saved route with its coverage geometry built once, so a re-match pass over many runs
    /// does not rebuild it for every run.
    nonisolated struct PreparedRoute {
        let route: SavedRoute
        fileprivate let trace: PreparedTrace
    }

    nonisolated static func prepare(_ savedRoutes: [SavedRoute]) -> [PreparedRoute] {
        savedRoutes
            .filter { $0.points.count >= minimumRoutePoints && $0.distanceMeters > 0 }
            .map { PreparedRoute(route: $0, trace: PreparedTrace($0.points)) }
    }

    nonisolated static func match(
        run: RecordedRun,
        preparedRoutes: [PreparedRoute],
        benchmarkRouteIDs: Set<UUID> = []
    ) -> RouteMatchResult? {
        guard run.routePoints.count >= minimumRoutePoints, !preparedRoutes.isEmpty else { return nil }

        // The run's geometry is built at most once, and only if some route needs coverage.
        var runTrace: PreparedTrace?
        var candidates: [Candidate] = []
        for prepared in preparedRoutes {
            candidates.append(candidate(for: prepared, run: run, runTrace: &runTrace))
        }
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
        var runOnRoute: Double
        var isReversed: Bool
        var score: Double
        var confidence: RouteMatchConfidence
    }

    nonisolated private static func candidate(for prepared: PreparedRoute, run: RecordedRun, runTrace: inout PreparedTrace?) -> Candidate {
        let route = prepared.route
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
        // It is measured both ways: on an out-and-back route one pass covers both legs, so the
        // run must also stay on the route (a return by another street fails that check).
        // Skipped when no confidence level could use it: endpoints apart, or distance beyond
        // the widest limit (route variant). The second pass only matters for a match or variant.
        let distanceRatio = distanceDeltaMeters / max(route.distanceMeters, 1)
        let coverageCanMatter = startDeltaMeters <= 300 && endDeltaMeters <= 300 && distanceRatio <= maxVariantDistanceRatio
        var routeCoverage = 0.0
        var runOnRoute = 0.0
        if coverageCanMatter {
            let trace = runTrace ?? PreparedTrace(run.routePoints)
            runTrace = trace
            routeCoverage = coverage(of: prepared.trace, by: trace)
            if routeCoverage >= 0.85 || shapeSimilarity >= 0.74 {
                runOnRoute = coverage(of: trace, by: prepared.trace)
            }
        }
        let endpointScore = max(0, 1 - ((startDeltaMeters + endDeltaMeters) / 600))
        let distanceScore = max(0, 1 - (distanceDeltaMeters / max(route.distanceMeters * 0.25, 1)))
        let score = (max(shapeSimilarity, routeCoverage) * 0.50) + (endpointScore * 0.30) + (distanceScore * 0.20)
        let confidence = confidence(
            distanceRatio: distanceRatio,
            startDeltaMeters: startDeltaMeters,
            endDeltaMeters: endDeltaMeters,
            shapeSimilarity: shapeSimilarity,
            routeCoverage: routeCoverage,
            runOnRoute: runOnRoute
        )

        return Candidate(
            route: route,
            distanceDeltaMeters: distanceDeltaMeters,
            startDeltaMeters: startDeltaMeters,
            endDeltaMeters: endDeltaMeters,
            shapeSimilarity: shapeSimilarity,
            routeCoverage: routeCoverage,
            runOnRoute: runOnRoute,
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
        routeCoverage: Double,
        runOnRoute: Double
    ) -> RouteMatchConfidence {
        let sameStartAndFinish = startDeltaMeters <= 120 && endDeltaMeters <= 120

        // The 8% distance limit for a full match is unchanged. Coverage lets a run with a short
        // detour still pass the shape check, which compares points by index and drifts after one.
        // A full match also needs most of the run on the route, so its time can set the route PB.
        if sameStartAndFinish,
           distanceRatio <= 0.08,
           runOnRoute >= 0.80,
           shapeSimilarity >= 0.74 || routeCoverage >= 0.90 {
            return .matched
        }

        // A variant may leave the route for its extra distance, but not for most of the run.
        if sameStartAndFinish,
           distanceRatio <= maxVariantDistanceRatio,
           routeCoverage >= 0.85,
           runOnRoute >= 0.70 {
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

    /// Share of `target`'s length that `other` passes within `coverageToleranceMeters` of.
    /// Both are resampled by distance, so dense GPS stretches do not dominate.
    nonisolated private static func coverage(of target: PreparedTrace, by other: PreparedTrace) -> Double {
        guard !target.samples.isEmpty, !other.samples.isEmpty else { return 0 }
        // Each trace has its own flat frame around its first point; move target points into
        // other's frame. The two origins are within a few hundred meters, so the frames agree.
        let shift = projected(
            latitude: other.originLatitude,
            longitude: other.originLongitude,
            originLatitude: target.originLatitude,
            originLongitude: target.originLongitude
        )
        let tolerance = coverageToleranceMeters
        var covered = 0
        for point in target.samples {
            let x = point.x - shift.x
            let y = point.y - shift.y
            guard x >= other.minX - tolerance, x <= other.maxX + tolerance,
                  y >= other.minY - tolerance, y <= other.maxY + tolerance else { continue }
            if other.hasPoint(withinToleranceOfX: x, y: y) { covered += 1 }
        }
        return Double(covered) / Double(target.samples.count)
    }

    fileprivate struct PlanePoint {
        var x: Double
        var y: Double
        /// True for the first point after a pause or recovered-run resume. The runner may have
        /// moved while recording was off, so nothing is measured or sampled across this point.
        var startsNewSegment = false
    }

    /// A trace resampled by distance in a flat frame around its first point, with a grid for
    /// nearby-point lookups. Built once per route per pass and once per run.
    fileprivate struct PreparedTrace {
        let originLatitude: Double
        let originLongitude: Double
        let samples: [PlanePoint]
        let minX: Double
        let maxX: Double
        let minY: Double
        let maxY: Double
        /// Cells twice the tolerance wide: a circle of that tolerance touches at most 2 x 2 cells.
        private let cells: [Int64: [PlanePoint]]
        private let cellSize: Double

        nonisolated init(_ points: [RunRoutePoint]) {
            originLatitude = points.first?.latitude ?? 0
            originLongitude = points.first?.longitude ?? 0
            let flat = points.map { point -> PlanePoint in
                var flat = RouteMatchingService.projected(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    originLatitude: points.first?.latitude ?? 0,
                    originLongitude: points.first?.longitude ?? 0
                )
                flat.startsNewSegment = point.startsNewSegment == true
                return flat
            }
            samples = RouteMatchingService.resampled(flat)
            minX = samples.map(\.x).min() ?? 0
            maxX = samples.map(\.x).max() ?? 0
            minY = samples.map(\.y).min() ?? 0
            maxY = samples.map(\.y).max() ?? 0
            cellSize = RouteMatchingService.coverageToleranceMeters * 2
            var grid: [Int64: [PlanePoint]] = [:]
            for sample in samples {
                let key = Self.key(Int((sample.x / cellSize).rounded(.down)), Int((sample.y / cellSize).rounded(.down)))
                grid[key, default: []].append(sample)
            }
            cells = grid
        }

        nonisolated func hasPoint(withinToleranceOfX x: Double, y: Double) -> Bool {
            let tolerance = RouteMatchingService.coverageToleranceMeters
            let limit = tolerance * tolerance
            let scaledX = x / cellSize
            let scaledY = y / cellSize
            let cellX = Int(scaledX.rounded(.down))
            let cellY = Int(scaledY.rounded(.down))
            let neighborX = scaledX - Double(cellX) < 0.5 ? cellX - 1 : cellX + 1
            let neighborY = scaledY - Double(cellY) < 0.5 ? cellY - 1 : cellY + 1
            for gridX in [cellX, neighborX] {
                for gridY in [cellY, neighborY] {
                    for other in cells[Self.key(gridX, gridY)] ?? [] {
                        let dx = other.x - x
                        let dy = other.y - y
                        if dx * dx + dy * dy <= limit { return true }
                    }
                }
            }
            return false
        }

        nonisolated private static func key(_ x: Int, _ y: Int) -> Int64 {
            (Int64(x) << 32) | Int64(UInt32(truncatingIfNeeded: y))
        }
    }

    /// Local flat projection in meters around the origin; accurate to well under a meter over a run.
    nonisolated fileprivate static func projected(
        latitude: Double,
        longitude: Double,
        originLatitude: Double,
        originLongitude: Double
    ) -> PlanePoint {
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(originLatitude * .pi / 180)
        return PlanePoint(
            x: (longitude - originLongitude) * metersPerDegreeLongitude,
            y: (latitude - originLatitude) * metersPerDegreeLatitude
        )
    }

    /// Evenly spaced points along the line, at most about `maxCount` of them. A segment start
    /// is a break: the gap before it adds no length and gets no samples, and the new stretch
    /// begins with a sample at its first point, so length and coverage come from real
    /// recording only.
    nonisolated fileprivate static func resampled(_ points: [PlanePoint], maxCount: Int = 200) -> [PlanePoint] {
        guard points.count > 1, let first = points.first, let last = points.last else { return points }
        var length = 0.0
        for (a, b) in zip(points, points.dropFirst()) where !b.startsNewSegment {
            length += hypot(b.x - a.x, b.y - a.y)
        }
        guard length > 0 else { return [first] }

        let spacing = max(10, length / Double(maxCount - 1))
        var result = [first]
        var travelled = 0.0
        var nextSampleAt = spacing
        for (a, b) in zip(points, points.dropFirst()) {
            if b.startsNewSegment {
                result.append(PlanePoint(x: b.x, y: b.y))
                nextSampleAt = travelled + spacing
                continue
            }
            let segment = hypot(b.x - a.x, b.y - a.y)
            guard segment > 0 else { continue }
            while nextSampleAt <= travelled + segment {
                let t = (nextSampleAt - travelled) / segment
                result.append(PlanePoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                nextSampleAt += spacing
            }
            travelled += segment
        }
        result.append(PlanePoint(x: last.x, y: last.y))
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
