import Foundation
import SwiftUI

// MARK: - DBGarminActivity → RecordedRun

extension DBGarminActivity {
    var startDate: Date? {
        guard let startStr = startTime else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: startStr) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: startStr)
    }

    var distanceKmLabel: String {
        guard let m = distanceM, m > 0 else { return "—" }
        return String(format: "%.2f km", m / 1000)
    }

    var durationLabel: String {
        guard let s = durationS, s > 0 else { return "—" }
        let total = Int(s)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm", m)
    }

    var sportLabel: String {
        guard let raw = sport, !raw.isEmpty else { return "Activity" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var relativeStartLabel: String {
        guard let d = startDate else { return "—" }
        let diff = Date().timeIntervalSince(d)
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        let days = Int(diff / 86400)
        return days < 7 ? "\(days)d ago" : {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: d)
        }()
    }

    func toRecordedRun() -> RecordedRun? {
        let trimmedActivityID = activityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedActivityID.isEmpty,
              isRunningSport,
              let startStr = startTime,
              let startDate = parseISO8601(startStr),
              let durationS = durationS, durationS > 0,
              let distanceM = distanceM, distanceM > 0 else { return nil }

        let endDate = startDate.addingTimeInterval(durationS)
        let pace = durationS / (distanceM / 1000)

        return RecordedRun(
            id: HealthKitRecordedRunMapper.stableUUID(for: trimmedActivityID),
            providerActivityID: trimmedActivityID,
            source: .garmin,
            startedAt: startDate,
            endedAt: endDate,
            distanceMeters: distanceM,
            movingTimeSeconds: durationS,
            averagePaceSecondsPerKm: pace,
            averageHeartRateBPM: avgHr,
            routePoints: [],
            syncedAt: Date()
        )
    }

    private func parseISO8601(_ str: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: str) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: str)
    }

    private var isRunningSport: Bool {
        guard let sport else { return false }
        let normalized = sport.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "run" || normalized.contains("run") || normalized.contains("running")
    }
}

// MARK: - DBGarminDailyMetrics → readiness signals

struct GarminReadiness {
    let readiness: Int
    let readinessLabel: String
    let recoveryLabel: String
    let hrvLabel: String

    static func from(_ metrics: DBGarminDailyMetrics?) -> GarminReadiness {
        guard let m = metrics else {
            return GarminReadiness(readiness: 0, readinessLabel: "--", recoveryLabel: "--", hrvLabel: "--")
        }

        let bb = m.bodyBattery ?? 0
        let readiness = min(100, max(0, bb))
        let label: String
        switch bb {
        case 71...: label = "Ready to train"
        case 41...70: label = "Moderate energy"
        default: label = "Rest recommended"
        }

        let recovery: String
        if let sleepS = m.sleepDurationS, sleepS > 0 {
            let hrs = sleepS / 3600
            let mins = (sleepS % 3600) / 60
            recovery = String(format: "%dh %02dm", Int32(hrs), Int32(mins))
        } else {
            recovery = "--"
        }

        let hrv: String
        if let h = m.hrv {
            hrv = h > 50 ? "Stable" : h > 30 ? "Moderate" : "Low"
        } else {
            hrv = "--"
        }

        return GarminReadiness(readiness: readiness, readinessLabel: label, recoveryLabel: recovery, hrvLabel: hrv)
    }
}

enum GarminDistanceBucket {
    static let standardKmBuckets = [3, 5, 8, 10, 15]

    static func bucket(forKm km: Double) -> Int {
        standardKmBuckets.min(by: { abs(Double($0) - km) < abs(Double($1) - km) }) ?? Int(km.rounded())
    }

    static func representativeActivities(from activities: [DBGarminActivity]) -> [Int: DBGarminActivity] {
        var pickedByBucket: [Int: DBGarminActivity] = [:]
        for activity in activities {
            guard let meters = activity.distanceM, meters > 0 else { continue }
            let bucket = bucket(forKm: meters / 1_000)
            if pickedByBucket[bucket] == nil {
                pickedByBucket[bucket] = activity
            }
        }
        return pickedByBucket
    }
}

enum WellnessTrendMapper {
    static func series(from metrics: [DBGarminDailyMetrics], maxDays: Int = 7) -> WellnessTrendSeries {
        guard !metrics.isEmpty else { return .empty }
        let points = metrics
            .sorted(by: { $0.date < $1.date })
            .suffix(maxDays)
            .compactMap(point(from:))
        guard !points.isEmpty else { return .empty }

        let hrvValues = points.compactMap(\.hrvMilliseconds)
        let readinessValues = points.compactMap(readinessValue(from:))
        let latest = points.last
        let latestHRV = latest?.hrvMilliseconds
        let latestReadiness = latest.flatMap(readinessValue(from:))

        return WellnessTrendSeries(
            days: points,
            hrvBars: bars(from: hrvValues),
            readinessBars: bars(from: readinessValues.map(Double.init)),
            hrvTrendSummary: summary(for: hrvValues, metricName: "HRV"),
            readinessTrendSummary: summary(for: readinessValues.map(Double.init), metricName: "Readiness"),
            latestHRVDisplay: latestHRV.map { String(format: "%.0f ms", $0) } ?? "--",
            latestReadinessDisplay: latestReadiness.map { "\($0)" } ?? "--"
        )
    }

    static func readinessValue(from point: DailyWellnessPoint) -> Int? {
        if let trainingReadiness = point.trainingReadiness {
            return min(100, max(0, trainingReadiness))
        }
        if let bodyBattery = point.bodyBattery {
            return min(100, max(0, bodyBattery))
        }
        return nil
    }

    private static func point(from metrics: DBGarminDailyMetrics) -> DailyWellnessPoint? {
        guard let date = parseDate(metrics.date) else { return nil }
        return DailyWellnessPoint(
            date: date,
            hrvMilliseconds: metrics.hrv,
            trainingReadiness: metrics.trainingReadiness,
            bodyBattery: metrics.bodyBattery
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func bars(from values: [Double]) -> [CGFloat] {
        guard let maxValue = values.max(), maxValue > 0 else { return [] }
        return values.map { max(0.08, CGFloat($0 / maxValue)) }
    }

    private static func summary(for values: [Double], metricName: String) -> String {
        guard values.count >= 3 else { return "Building \(metricName.lowercased()) trend" }
        guard let first = values.first, let last = values.last else { return "Building \(metricName.lowercased()) trend" }
        let delta = last - first
        if abs(delta) < max(2.0, first * 0.03) {
            return "\(metricName) is stable over 7 days"
        }
        return delta > 0
            ? "\(metricName) is trending up"
            : "\(metricName) is trending down"
    }
}
