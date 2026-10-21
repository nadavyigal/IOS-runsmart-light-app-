import Foundation

/// Re-scores stored runs against the current saved routes.
///
/// A run's route match used to be computed once, when the run was processed, against the
/// routes that existed at that moment. A run therefore never counted toward a route saved
/// or benchmarked after it, including the route saved from that same run.
enum RouteRematchService {
    /// Upper bound on runs re-scored in one pass, newest first.
    nonisolated static let maxRunsPerPass = 300

    /// New match results keyed by run id, only for runs whose stored result should change.
    nonisolated static func updatedMatches(
        runs: [RecordedRun],
        savedRoutes: [SavedRoute],
        benchmarkRouteIDs: Set<UUID> = [],
        limit: Int = maxRunsPerPass
    ) -> [UUID: RouteMatchResult] {
        let savedRouteIDs = Set(savedRoutes.map(\.id))
        let candidates = runs
            .filter { $0.routePoints.count >= RouteMatchingService.minimumRoutePoints }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(max(0, limit))

        let preparedRoutes = RouteMatchingService.prepare(savedRoutes)
        var updates: [UUID: RouteMatchResult] = [:]
        for run in candidates {
            guard let candidate = RouteMatchingService.match(
                run: run,
                preparedRoutes: preparedRoutes,
                benchmarkRouteIDs: benchmarkRouteIDs
            ) else { continue }
            let preferred = preferredResult(
                existing: run.routeMatchResult,
                candidate: candidate,
                savedRouteIDs: savedRouteIDs,
                benchmarkRouteIDs: benchmarkRouteIDs
            )
            if preferred != run.routeMatchResult {
                updates[run.id] = preferred
            }
        }
        return updates
    }

    /// Keeps a result that counts toward a route unless its route is gone or the new result
    /// ranks at least as high: a benchmark route first, then full match over route variant.
    nonisolated static func preferredResult(
        existing: RouteMatchResult?,
        candidate: RouteMatchResult,
        savedRouteIDs: Set<UUID>,
        benchmarkRouteIDs: Set<UUID> = []
    ) -> RouteMatchResult {
        guard let existing,
              existing.confidence.countsTowardRoute,
              let existingRouteID = existing.routeID,
              savedRouteIDs.contains(existingRouteID) else {
            return candidate
        }
        return rank(candidate, benchmarkRouteIDs) >= rank(existing, benchmarkRouteIDs) ? candidate : existing
    }

    nonisolated private static func rank(_ result: RouteMatchResult, _ benchmarkRouteIDs: Set<UUID>) -> (Int, Int) {
        let onBenchmark = result.confidence.countsTowardRoute && result.routeID.map(benchmarkRouteIDs.contains) == true
        return (onBenchmark ? 1 : 0, result.confidence.rank)
    }
}
