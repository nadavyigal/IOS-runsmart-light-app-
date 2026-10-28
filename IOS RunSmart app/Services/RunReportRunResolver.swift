import Foundation

/// Identity lookup shared by saved report entry points.
enum RunReportRunResolver {
    static func resolve(runID: String, runs: [RecordedRun]) -> RecordedRun? {
        guard !runID.isEmpty else { return nil }
        for group in ActivityConsolidationService.groups(for: runs) {
            if group.id == runID || matches(runID, run: group.canonicalRun) ||
                group.runs.contains(where: { matches(runID, run: $0) }) {
                return group.canonicalRun
            }
        }
        // Consolidation can omit an old fragment. An explicit identity still belongs to
        // that recorded activity; never substitute a different run by date or distance.
        return runs.first { matches(runID, run: $0) }
    }

    /// Consolidation can add GPS to a richer provider copy after stored runs were
    /// matched. Refresh that final geometry before the report chooses its route action.
    static func resolve(runID: String, runs: [RecordedRun], savedRoutes: [SavedRoute],
                        benchmarkRouteIDs: Set<UUID>) -> RecordedRun? {
        guard var run = resolve(runID: runID, runs: runs) else { return nil }
        run.routeMatchResult = RouteMatchingService.match(
            run: run, savedRoutes: savedRoutes, benchmarkRouteIDs: benchmarkRouteIDs
        )
        return run
    }

    private static func matches(_ runID: String, run: RecordedRun) -> Bool {
        run.consolidatedActivityID == runID || run.providerActivityID == runID ||
            UUID(uuidString: runID) == run.id ||
            (UUID(uuidString: runID) != nil && run.providerActivityID.flatMap(UUID.init(uuidString:)) == UUID(uuidString: runID))
    }
}
