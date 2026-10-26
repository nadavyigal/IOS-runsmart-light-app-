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

    private static func matches(_ runID: String, run: RecordedRun) -> Bool {
        run.consolidatedActivityID == runID || run.providerActivityID == runID ||
            UUID(uuidString: runID) == run.id ||
            (UUID(uuidString: runID) != nil && run.providerActivityID.flatMap(UUID.init(uuidString:)) == UUID(uuidString: runID))
    }
}
