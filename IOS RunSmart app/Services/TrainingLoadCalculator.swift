import Foundation

enum TrainingLoadStatus: String, Hashable {
    case insufficientData
    case detraining
    case optimal
    case elevated
    case highRisk
}

struct TrainingLoadMetrics: Hashable {
    /// Summed session load over the last 7 days.
    let acuteLoad: Double
    /// Average weekly load over the last 28 days.
    let chronicLoad: Double
    /// Acute:chronic workload ratio; nil when chronic is zero or data is insufficient.
    let acwr: Double?
    let status: TrainingLoadStatus
}

/// Session-RPE training load (Foster et al.): load = minutes x RPE.
/// Pure and deterministic; all callers inject now/calendar (house style,
/// see TrainingMetrics / FlexWeekPresentation).
enum TrainingLoadCalculator {

    static func sessionLoad(for run: RecordedRun) -> Double {
        (run.movingTimeSeconds / 60.0) * Double(effortRPE(for: run))
    }

    static func snapshot(
        runs: [RecordedRun],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrainingLoadMetrics {
        let windowStart = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let acuteStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let recent = runs.filter { $0.startedAt >= windowStart && $0.startedAt <= now }

        guard recent.count >= 4 else {
            return TrainingLoadMetrics(acuteLoad: 0, chronicLoad: 0, acwr: nil, status: .insufficientData)
        }

        let acute = recent.filter { $0.startedAt >= acuteStart }.map(sessionLoad(for:)).reduce(0, +)
        let chronic = recent.map(sessionLoad(for:)).reduce(0, +) / 4.0

        guard chronic > 0 else {
            return TrainingLoadMetrics(acuteLoad: acute, chronicLoad: 0, acwr: nil, status: .insufficientData)
        }

        let acwr = acute / chronic
        return TrainingLoadMetrics(acuteLoad: acute, chronicLoad: chronic, acwr: acwr, status: status(for: acwr))
    }

    private static func status(for acwr: Double) -> TrainingLoadStatus {
        switch acwr {
        case ..<0.8: return .detraining
        case ..<1.3: return .optimal
        case ..<1.5: return .elevated
        default: return .highRisk
        }
    }

    /// Effort on the 1-10 session-RPE scale: prefer the runner's own RPE,
    /// fall back to an average-HR band, then to moderate (5).
    private static func effortRPE(for run: RecordedRun) -> Int {
        if let rpe = run.rpe, (1...10).contains(rpe) { return rpe }
        if let hr = run.averageHeartRateBPM {
            switch hr {
            case ..<120: return 3
            case ..<140: return 5
            case ..<160: return 7
            default: return 9
            }
        }
        return 5
    }
}
