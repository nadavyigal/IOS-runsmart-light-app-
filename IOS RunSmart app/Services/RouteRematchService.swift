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
        limit: Int = maxRunsPerPass
    ) -> [UUID: RouteMatchResult] {
        let savedRouteIDs = Set(savedRoutes.map(\.id))
        let candidates = runs
            .filter { $0.routePoints.count >= RouteMatchingService.minimumRoutePoints }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(max(0, limit))

        var updates: [UUID: RouteMatchResult] = [:]
        for run in candidates {
            guard let candidate = RouteMatchingService.match(run: run, savedRoutes: savedRoutes) else { continue }
            let preferred = preferredResult(
                existing: run.routeMatchResult,
                candidate: candidate,
                savedRouteIDs: savedRouteIDs
            )
            if preferred != run.routeMatchResult {
                updates[run.id] = preferred
            }
        }
        return updates
    }

    /// Keeps an existing `.matched` result unless its route is gone or the new result is
    /// also `.matched` (the new one is then the best-scoring route, so it is no downgrade).
    nonisolated static func preferredResult(
        existing: RouteMatchResult?,
        candidate: RouteMatchResult,
        savedRouteIDs: Set<UUID>
    ) -> RouteMatchResult {
        guard let existing,
              existing.confidence == .matched,
              let existingRouteID = existing.routeID,
              savedRouteIDs.contains(existingRouteID) else {
            return candidate
        }
        return candidate.confidence == .matched ? candidate : existing
    }
}
