import Foundation

enum GarminImportProcessor {
    typealias RoutePointLoader = (String) async -> [RunRoutePoint]
    typealias HiddenRunChecker = (RecordedRun) -> Bool

    static func normalizedRuns(
        from activities: [DBGarminActivity],
        isHidden: HiddenRunChecker,
        routePointLoader: @escaping RoutePointLoader
    ) async -> [RecordedRun] {
        let visibleRuns = activities
            .compactMap { $0.toRecordedRun() }
            .filter { !isHidden($0) }

        let consolidated = ActivityConsolidationService
            .consolidatedRuns(visibleRuns)
            .sorted { $0.startedAt > $1.startedAt }

        let routeLoads = await withTaskGroup(of: (String, [RunRoutePoint]).self) { group in
            for run in consolidated where run.providerActivityID != nil && run.routePoints.isEmpty {
                let activityID = run.providerActivityID!
                group.addTask {
                    (activityID, await routePointLoader(activityID))
                }
            }

            var loaded: [String: [RunRoutePoint]] = [:]
            for await (activityID, points) in group {
                loaded[activityID] = points
            }
            return loaded
        }

        return consolidated.map { run in
            var copy = run
            if let activityID = copy.providerActivityID, copy.routePoints.isEmpty {
                copy.routePoints = routeLoads[activityID] ?? []
            }
            return copy
        }
    }

    static func newestNormalizedRun(
        from activities: [DBGarminActivity],
        isHidden: HiddenRunChecker,
        routePointLoader: @escaping RoutePointLoader
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
