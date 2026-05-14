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
              match.confidence == .matched,
              let routeID = match.routeID,
              let route = savedRoutes.first(where: { $0.id == routeID }),
              benchmarkRoutes.contains(where: { $0.savedRouteID == routeID }) else {
            return nil
        }

        let performances = matchedRuns(for: routeID, in: runs + [run])
            .uniqueByRunID()
            .map(performance)
            .sorted { $0.startedAt < $1.startedAt }
        guard let current = performances.first(where: { $0.runID == run.id }),
              let best = performances.min(by: { $0.durationSeconds < $1.durationSeconds }),
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
            recentTrend: trend(current: current, previousRuns: priorRuns)
        )
    }

    private static func matchedRuns(for routeID: UUID, in runs: [RecordedRun]) -> [RecordedRun] {
        runs.filter { run in
            guard let match = run.routeMatchResult else { return false }
            return match.routeID == routeID && match.confidence == .matched
        }
    }

    private static func performance(from run: RecordedRun) -> BenchmarkRunPerformance {
        BenchmarkRunPerformance(
            runID: run.id,
            source: run.source,
            startedAt: run.startedAt,
            durationSeconds: run.movingTimeSeconds,
            paceSecondsPerKm: run.averagePaceSecondsPerKm,
            averageHeartRateBPM: run.averageHeartRateBPM
        )
    }

    private static func average(routeID: UUID, performances: [BenchmarkRunPerformance]) -> BenchmarkPerformanceAverage? {
        guard !performances.isEmpty else { return nil }
        let runCount = performances.count
        let duration = performances.reduce(0) { $0 + $1.durationSeconds } / Double(runCount)
        let pace = performances.reduce(0) { $0 + $1.paceSecondsPerKm } / Double(runCount)
        let bestPace = performances.map(\.paceSecondsPerKm).min() ?? pace
        let heartRates = performances.compactMap(\.averageHeartRateBPM)
        let averageHeartRate = heartRates.isEmpty ? nil : Int((Double(heartRates.reduce(0, +)) / Double(heartRates.count)).rounded())
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
    func uniqueByRunID() -> [RecordedRun] {
        var seen = Set<UUID>()
        return filter { run in
            guard !seen.contains(run.id) else { return false }
            seen.insert(run.id)
            return true
        }
    }
}
