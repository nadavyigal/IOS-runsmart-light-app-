import Foundation

enum BenchmarkRouteAnalyticsService {
    static func comparison(
        for run: RecordedRun,
        runs: [RecordedRun],
        savedRoutes: [SavedRoute],
        benchmarkRoutes: [BenchmarkRoute],
        calendar: Calendar = .current
    ) -> BenchmarkRouteComparison? {
        guard let match = run.routeMatchResult,
              match.confidence.countsTowardRoute,
              let routeID = match.routeID,
              let route = savedRoutes.first(where: { $0.id == routeID }),
              benchmarkRoutes.contains(where: { $0.savedRouteID == routeID }) else {
            return nil
        }

        let performances = matchedRuns(for: routeID, in: [run] + runs)
            .uniqueByRunID()
            .uniqueActivities(preserving: run)
            .map { performance(from: $0) }
            .sorted { $0.startedAt < $1.startedAt }
        // Route PB is a time, so it only comes from full-route runs. A route with only
        // variants so far falls back to the best pace.
        let fullRoute = performances.filter { !$0.isRouteVariant }
        guard let current = performances.first(where: { $0.runID == run.id }),
              let best = fullRoute.min(by: { $0.durationSeconds < $1.durationSeconds })
                ?? performances.min(by: { $0.paceSecondsPerKm < $1.paceSecondsPerKm }),
              let allTimeAverage = average(routeID: routeID, performances: performances) else {
            return nil
        }

        let priorRuns = performances.filter { $0.startedAt < current.startedAt && $0.runID != current.runID }
        let previous = priorRuns.last
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: current.startedAt)) ?? calendar.startOfDay(for: current.startedAt)
        let monthlyRuns = performances.filter { calendar.isDate($0.startedAt, equalTo: current.startedAt, toGranularity: .month) }
        guard let monthlyAverage = monthlyAverage(
            routeID: routeID,
            monthStart: monthStart,
            performances: monthlyRuns
        ) else {
            return nil
        }

        return BenchmarkRouteComparison(
            routeID: routeID,
            routeName: route.name,
            matchConfidence: match.confidence,
            currentPerformance: current,
            previousPerformance: previous,
            personalBest: best,
            allTimeAverage: allTimeAverage,
            monthlyAverage: monthlyAverage,
            recentTrend: trend(current: current, previousRuns: priorRuns),
            routeDistanceMeters: route.distanceMeters
        )
    }

    private static func matchedRuns(for routeID: UUID, in runs: [RecordedRun]) -> [RecordedRun] {
        runs.filter { run in
            guard let match = run.routeMatchResult else { return false }
            return match.routeID == routeID && match.confidence.countsTowardRoute
        }
    }

    private static func performance(from run: RecordedRun) -> BenchmarkRunPerformance {
        BenchmarkRunPerformance(
            runID: run.id,
            source: run.source,
            startedAt: run.startedAt,
            durationSeconds: run.movingTimeSeconds,
            paceSecondsPerKm: run.averagePaceSecondsPerKm,
            averageHeartRateBPM: run.averageHeartRateBPM,
            distanceMeters: run.distanceMeters,
            matchConfidence: run.routeMatchResult?.confidence
        )
    }

    private static func average(routeID: UUID, performances: [BenchmarkRunPerformance]) -> BenchmarkPerformanceAverage? {
        guard !performances.isEmpty else { return nil }
        let runCount = performances.count
        let duration = performances.reduce(0) { $0 + $1.durationSeconds } / Double(runCount)
        let pace = performances.reduce(0) { $0 + $1.paceSecondsPerKm } / Double(runCount)
        let bestPace = performances.map(\.paceSecondsPerKm).min() ?? pace
        let heartRates: [Int] = performances.compactMap(\.averageHeartRateBPM)
        let heartRateSum: Int = heartRates.reduce(0, +)
        let averageHeartRate: Int? = heartRates.isEmpty ? nil : Int((Double(heartRateSum) / Double(heartRates.count)).rounded())
        return BenchmarkPerformanceAverage(
            routeID: routeID,
            runCount: runCount,
            averageDurationSeconds: duration,
            averagePaceSecondsPerKm: pace,
            bestPaceSecondsPerKm: bestPace,
            averageHeartRateBPM: averageHeartRate
        )
    }

    private static func monthlyAverage(
        routeID: UUID,
        monthStart: Date,
        performances: [BenchmarkRunPerformance]
    ) -> MonthlyBenchmarkAverage? {
        guard let average = average(routeID: routeID, performances: performances) else { return nil }
        return MonthlyBenchmarkAverage(
            routeID: routeID,
            monthStart: monthStart,
            runCount: average.runCount,
            averageDurationSeconds: average.averageDurationSeconds,
            averagePaceSecondsPerKm: average.averagePaceSecondsPerKm,
            bestPaceSecondsPerKm: average.bestPaceSecondsPerKm,
            averageHeartRateBPM: average.averageHeartRateBPM,
            hasEnoughData: average.runCount >= 2
        )
    }

    private static func trend(current: BenchmarkRunPerformance, previousRuns: [BenchmarkRunPerformance]) -> BenchmarkRouteTrend {
        let recent = Array(previousRuns.suffix(3))
        guard recent.count >= 2 else { return .notEnoughData }
        let recentAveragePace = recent.reduce(0) { $0 + $1.paceSecondsPerKm } / Double(recent.count)
        guard recentAveragePace > 0 else { return .notEnoughData }
        let delta = (current.paceSecondsPerKm - recentAveragePace) / recentAveragePace
        if delta <= -0.02 { return .improving }
        if delta >= 0.02 { return .slowing }
        return .steady
    }
}

private extension Array where Element == RecordedRun {
    /// Native and imported copies of the same workout have different UUIDs. Use the same
    /// activity grouping as run history so one physical run contributes one performance.
    /// Keep the explicitly supplied current copy: its refreshed match and identity are what
    /// the open report is comparing, even when a provider copy has richer health metrics.
    func uniqueActivities(preserving current: RecordedRun) -> [RecordedRun] {
        let groups = ActivityConsolidationService.groups(for: self)
        let currentGroupIndex = groups.firstIndex { group in group.runs.contains { $0.id == current.id } }
            ?? groups.firstIndex { group in group.runs.contains { ActivityConsolidationService.matches($0, current) } }
        var result = groups.enumerated().map { index, group in
            index == currentGroupIndex ? current : group.canonicalRun
        }
        // Consolidation can omit a likely Garmin fragment, but an explicitly opened report
        // must still be able to compare its own recorded activity.
        if !result.contains(where: { $0.id == current.id }) {
            result.append(current)
        }
        return result
    }

    func uniqueByRunID() -> [RecordedRun] {
        var seen = Set<UUID>()
        return filter { run in
            guard !seen.contains(run.id) else { return false }
            seen.insert(run.id)
            return true
        }
    }
}
