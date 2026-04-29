import Foundation

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
        guard let startStr = startTime,
              let startDate = parseISO8601(startStr),
              let durationS = durationS, durationS > 0 else { return nil }

        let distanceM = distanceM ?? 0
        let endDate = startDate.addingTimeInterval(durationS)
        let pace = distanceM > 0 ? durationS / (distanceM / 1000) : 0

        return RecordedRun(
            id: UUID(),
            providerActivityID: activityId,
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
