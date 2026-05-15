import Foundation

enum GarminImportProcessor {
    typealias RoutePointLoader = (String) async -> [RunRoutePoint]
    typealias HiddenRunChecker = (RecordedRun) -> Bool

    static func normalizedRuns(
        from activities: [DBGarminActivity],
        isHidden: HiddenRunChecker,
        routePointLoader: RoutePointLoader
    ) async -> [RecordedRun] {
        let visibleRuns = activities
            .compactMap { $0.toRecordedRun() }
            .filter { !isHidden($0) }

        let consolidated = ActivityConsolidationService
            .consolidatedRuns(visibleRuns)
            .sorted { $0.startedAt > $1.startedAt }

        var normalized: [RecordedRun] = []
        for var run in consolidated {
            if let activityID = run.providerActivityID, run.routePoints.isEmpty {
                run.routePoints = await routePointLoader(activityID)
            }
            normalized.append(run)
        }
        return normalized
    }

    static func newestNormalizedRun(
        from activities: [DBGarminActivity],
        isHidden: HiddenRunChecker,
        routePointLoader: RoutePointLoader
    ) async -> RecordedRun? {
        await normalizedRuns(
            from: activities,
            isHidden: isHidden,
            routePointLoader: routePointLoader
        ).first
    }

    static func normalizedActivities(
        from activities: [DBGarminActivity],
        isHidden: HiddenRunChecker
    ) -> [DBGarminActivity] {
        let visibleRuns = activities
            .compactMap { $0.toRecordedRun() }
            .filter { !isHidden($0) }
        let visibleProviderIDs = Set(
            ActivityConsolidationService
                .consolidatedRuns(visibleRuns)
                .compactMap(\.providerActivityID)
        )
        var seen = Set<String>()
        return activities
            .filter { activity in
                guard visibleProviderIDs.contains(activity.activityId), !seen.contains(activity.activityId) else { return false }
                seen.insert(activity.activityId)
                return true
            }
            .sorted { lhs, rhs in
                (lhs.startDate ?? .distantPast) > (rhs.startDate ?? .distantPast)
            }
    }
}
