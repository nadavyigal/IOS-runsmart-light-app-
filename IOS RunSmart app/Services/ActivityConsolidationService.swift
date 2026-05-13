import Foundation

struct ActivityConsolidationGroup: Hashable {
    var id: String
    var canonicalRun: RecordedRun
    var runs: [RecordedRun]
}

enum ActivityConsolidationService {
    static func consolidatedRuns(_ runs: [RecordedRun], calendar: Calendar = .current) -> [RecordedRun] {
        groups(for: runs, calendar: calendar).map(\.canonicalRun)
    }

    static func userVisibleRecentRuns(
        _ runs: [RecordedRun],
        now: Date = Date(),
        lookbackDays: Int = 14,
        calendar: Calendar = .current
    ) -> [RecordedRun] {
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? now.addingTimeInterval(TimeInterval(-lookbackDays * 86_400))
        let futureTolerance = now.addingTimeInterval(6 * 3_600)

        return consolidatedRuns(runs, calendar: calendar)
            .filter { run in
                run.startedAt >= start &&
                run.startedAt <= futureTolerance &&
                isUserVisibleRun(run)
            }
    }

    static func canonicalRun(for target: RecordedRun, in runs: [RecordedRun], calendar: Calendar = .current) -> RecordedRun {
        let allRuns = runs.contains(where: { isSameStoredRun($0, target) }) ? runs : runs + [target]
        return groups(for: allRuns, calendar: calendar)
            .first { group in group.runs.contains(where: { isSameStoredRun($0, target) || matches($0, target, calendar: calendar) }) }?
            .canonicalRun ?? assignConsolidatedID(to: target, groupID: stableGroupID(for: [target], calendar: calendar))
    }

    static func groups(for runs: [RecordedRun], calendar: Calendar = .current) -> [ActivityConsolidationGroup] {
        var groups: [[RecordedRun]] = []

        for run in uniqueStoredRuns(runs).sorted(by: { $0.startedAt < $1.startedAt }) {
            if let index = groups.firstIndex(where: { group in
                group.contains(where: { matches($0, run, calendar: calendar) })
            }) {
                groups[index].append(run)
            } else {
                groups.append([run])
            }
        }

        return groups.map { runs in
            let groupID = stableGroupID(for: runs, calendar: calendar)
            let canonical = mergedCanonicalRun(from: runs, groupID: groupID)
            return ActivityConsolidationGroup(id: groupID, canonicalRun: canonical, runs: runs)
        }
        .sorted { $0.canonicalRun.startedAt > $1.canonicalRun.startedAt }
    }

    static func matches(_ lhs: RecordedRun, _ rhs: RecordedRun, calendar: Calendar = .current) -> Bool {
        guard !isSameStoredRun(lhs, rhs) else { return true }
        guard lhs.distanceMeters > 0 || rhs.distanceMeters > 0 else { return false }

        let startDelta = abs(lhs.startedAt.timeIntervalSince(rhs.startedAt))
        let overlap = min(lhs.endedAt, rhs.endedAt).timeIntervalSince(max(lhs.startedAt, rhs.startedAt))
        let distanceTolerance = max(250.0, min(lhs.distanceMeters, rhs.distanceMeters) * 0.08)
        let durationTolerance = max(180.0, min(lhs.movingTimeSeconds, rhs.movingTimeSeconds) * 0.10)
        let distanceDelta = abs(lhs.distanceMeters - rhs.distanceMeters)
        let durationDelta = abs(lhs.movingTimeSeconds - rhs.movingTimeSeconds)
        let sameLocalDay = calendar.isDate(lhs.startedAt, inSameDayAs: rhs.startedAt)

        return sameLocalDay &&
            startDelta <= 10 * 60 &&
            overlap >= -120 &&
            distanceDelta <= distanceTolerance &&
            durationDelta <= durationTolerance
    }

    static func isUserVisibleRun(_ run: RecordedRun) -> Bool {
        guard run.distanceMeters >= 1_000 else { return false }
        guard run.movingTimeSeconds >= 8 * 60 else { return false }

        let pace = run.averagePaceSecondsPerKm > 0
            ? run.averagePaceSecondsPerKm
            : run.movingTimeSeconds / max(run.distanceMeters / 1_000, 0.1)
        return pace >= 150 && pace <= 1_200
    }

    private static func uniqueStoredRuns(_ runs: [RecordedRun]) -> [RecordedRun] {
        var bestByKey: [String: RecordedRun] = [:]
        for run in runs {
            let key = storedRunKey(run)
            if let current = bestByKey[key] {
                bestByKey[key] = richnessScore(run) > richnessScore(current) ? run : current
            } else {
                bestByKey[key] = run
            }
        }
        return Array(bestByKey.values)
    }

    private static func mergedCanonicalRun(from runs: [RecordedRun], groupID: String) -> RecordedRun {
        var canonical = runs.max { richnessScore($0) < richnessScore($1) } ?? runs[0]
        canonical.consolidatedActivityID = groupID

        if canonical.routePoints.isEmpty,
           let routeRun = runs.max(by: { $0.routePoints.count < $1.routePoints.count }),
           !routeRun.routePoints.isEmpty {
            canonical.routePoints = routeRun.routePoints
        }

        if canonical.averageHeartRateBPM == nil,
           let heartRate = runs.compactMap(\.averageHeartRateBPM).first {
            canonical.averageHeartRateBPM = heartRate
        }

        if canonical.distanceMeters <= 0,
           let distance = runs.map(\.distanceMeters).max(), distance > 0 {
            canonical.distanceMeters = distance
        }

        if canonical.movingTimeSeconds <= 0,
           let movingTime = runs.map(\.movingTimeSeconds).max(), movingTime > 0 {
            canonical.movingTimeSeconds = movingTime
        }

        if canonical.averagePaceSecondsPerKm <= 0,
           canonical.distanceMeters > 0,
           canonical.movingTimeSeconds > 0 {
            canonical.averagePaceSecondsPerKm = canonical.movingTimeSeconds / (canonical.distanceMeters / 1_000)
        }

        return canonical
    }

    private static func assignConsolidatedID(to run: RecordedRun, groupID: String) -> RecordedRun {
        var copy = run
        copy.consolidatedActivityID = groupID
        return copy
    }

    private static func richnessScore(_ run: RecordedRun) -> Double {
        var score = 0.0
        if !run.routePoints.isEmpty { score += 5 }
        if run.averageHeartRateBPM != nil { score += 3 }
        if run.providerActivityID?.isEmpty == false { score += 2 }
        if run.distanceMeters > 0 { score += 1 }
        if run.movingTimeSeconds > 0 { score += 1 }
        if run.syncedAt != nil { score += 0.5 }

        switch run.source {
        case .garmin: score += 0.3
        case .healthKit: score += 0.2
        case .runSmart: score += 0.1
        }
        return score
    }

    private static func isSameStoredRun(_ lhs: RecordedRun, _ rhs: RecordedRun) -> Bool {
        if lhs.id == rhs.id { return true }
        guard let lhsProviderID = lhs.providerActivityID,
              let rhsProviderID = rhs.providerActivityID else { return false }
        return lhs.source == rhs.source && lhsProviderID == rhsProviderID
    }

    private static func storedRunKey(_ run: RecordedRun) -> String {
        if let providerID = run.providerActivityID, !providerID.isEmpty {
            return "\(run.source.rawValue)|\(providerID)"
        }
        return "\(run.source.rawValue)|\(run.id.uuidString)"
    }

    private static func stableGroupID(for runs: [RecordedRun], calendar: Calendar) -> String {
        let representative = runs.min(by: { $0.startedAt < $1.startedAt }) ?? runs[0]
        let roundedStart = roundedDate(representative.startedAt, toNearestSeconds: 5 * 60)
        let distanceBucket = Int((representative.distanceMeters / 250).rounded())
        return "activity-\(dateKey(roundedStart, calendar: calendar))-\(distanceBucket)"
    }

    private static func roundedDate(_ date: Date, toNearestSeconds seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / seconds).rounded() * seconds)
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}
