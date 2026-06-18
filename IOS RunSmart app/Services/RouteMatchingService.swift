import CoreLocation
import Foundation

enum RouteMatchingService {
    static let minimumRoutePoints = 6

    static func match(run: RecordedRun, savedRoutes: [SavedRoute]) -> RouteMatchResult? {
        guard run.routePoints.count >= minimumRoutePoints else { return nil }
        let routes = savedRoutes.filter { $0.points.count >= minimumRoutePoints && $0.distanceMeters > 0 }
        guard !routes.isEmpty else { return nil }

        let candidates = routes.map { candidate(for: $0, run: run) }
        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }

        let confidence = confidence(for: best, routeDistanceMeters: max(best.route.distanceMeters, 1))
        let attachedRouteID = confidence == .matched ? best.route.id : nil
        return RouteMatchResult(
            routeID: attachedRouteID,
            candidateRouteID: best.route.id,
            confidence: confidence,
            distanceDeltaMeters: best.distanceDeltaMeters,
            startDeltaMeters: best.startDeltaMeters,
            endDeltaMeters: best.endDeltaMeters,
            shapeSimilarity: best.shapeSimilarity,
            isReversed: best.isReversed
        )
    }

    private struct Candidate {
        var route: SavedRoute
        var distanceDeltaMeters: Double
        var startDeltaMeters: Double
        var endDeltaMeters: Double
        var shapeSimilarity: Double
        var isReversed: Bool
        var score: Double
    }

    private static func candidate(for route: SavedRoute, run: RecordedRun) -> Candidate {
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
        let endpointScore = max(0, 1 - ((isReversed ? reverseStart + reverseEnd : forwardStart + forwardEnd) / 600))
        let distanceScore = max(0, 1 - (distanceDeltaMeters / max(route.distanceMeters * 0.25, 1)))
        let score = (shapeSimilarity * 0.50) + (endpointScore * 0.30) + (distanceScore * 0.20)

        return Candidate(
            route: route,
            distanceDeltaMeters: distanceDeltaMeters,
            startDeltaMeters: isReversed ? reverseStart : forwardStart,
            endDeltaMeters: isReversed ? reverseEnd : forwardEnd,
            shapeSimilarity: shapeSimilarity,
            isReversed: isReversed,
            score: score
        )
    }

    private static func confidence(for candidate: Candidate, routeDistanceMeters: Double) -> RouteMatchConfidence {
        let distanceRatio = candidate.distanceDeltaMeters / routeDistanceMeters
        if distanceRatio <= 0.08,
           candidate.startDeltaMeters <= 120,
           candidate.endDeltaMeters <= 120,
           candidate.shapeSimilarity >= 0.74 {
            return .matched
        }

        if distanceRatio <= 0.18,
           candidate.startDeltaMeters <= 300,
           candidate.endDeltaMeters <= 300,
           candidate.shapeSimilarity >= 0.52 {
            return .possibleMatch
        }

        return .noMatch
    }

    private static func shapeSimilarity(runPoints: [RunRoutePoint], routePoints: [RunRoutePoint]) -> Double {
        let runSample = sample(runPoints, count: 20)
        let routeSample = sample(routePoints, count: 20)
        guard runSample.count == routeSample.count, !runSample.isEmpty else { return 0 }

        let distances = zip(runSample, routeSample).map { distance(from: $0.0, to: $0.1) }
        let averageDistance = distances.reduce(0, +) / Double(distances.count)
        return max(0, min(1, 1 - (averageDistance / 220)))
    }

    private static func sample(_ points: [RunRoutePoint], count: Int) -> [RunRoutePoint] {
        guard points.count > count, count > 1 else { return points }
        let lastIndex = points.count - 1
        let step = Double(lastIndex) / Double(count - 1)
        return (0..<count).map { index in
            points[index == count - 1 ? lastIndex : Int((Double(index) * step).rounded())]
        }
    }

    private static func distance(from lhs: RunRoutePoint?, to rhs: RunRoutePoint?) -> Double {
        guard let lhs, let rhs else { return .greatestFiniteMagnitude }
        return CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}
