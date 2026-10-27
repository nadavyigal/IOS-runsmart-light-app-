import Foundation
import CoreGraphics
import CoreLocation

enum RunShareAssetFormat: String, CaseIterable, Identifiable {
    case story = "Story"
    case feed = "Feed"
    case video = "Video"

    var id: String { rawValue }
    var pixelSize: CGSize { CGSize(width: 1080, height: self == .feed ? 1350 : 1920) }
    var detail: String { self == .feed ? "1080 × 1350" : self == .video ? "10 sec · 1080 × 1920" : "1080 × 1920" }
}

/// An immutable rendering boundary. No raw/untrimmed route or demo data reaches a renderer.
struct RunShareSnapshot {
    let title: String
    let dateLabel: String
    let distanceLabel: String
    let distanceUnit: String
    let durationLabel: String
    let paceLabel: String
    let sourceLabel: String
    let insight: String
    let privacyNote: String
    let distanceMeters: Double
    let movingTimeSeconds: Double
    let routePoints: [RunRoutePoint]

    static let appStoreCallToAction = "Get RunSmart on the App Store"

    static func make(
        run: RecordedRun,
        includeMap: Bool,
        insight: String = "",
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> RunShareSnapshot {
        let distance = run.distanceMeters.isFinite && run.distanceMeters > 0 ? run.distanceMeters : 0
        let time = run.movingTimeSeconds.isFinite && run.movingTimeSeconds > 0 && run.movingTimeSeconds < Double(Int.max / 2)
            ? run.movingTimeSeconds : 0
        let route = includeMap ? (RouteSharePrivacy.shareableRoute(validRoutePoints(run.routePoints)) ?? []) : []
        let date = DateFormatter()
        date.locale = locale
        date.calendar = calendar
        date.timeZone = calendar.timeZone
        date.dateStyle = .medium
        date.timeStyle = .none
        let pace = distance > 0 && time > 0 ? time / (distance / 1000) : 0
        return RunShareSnapshot(
            title: RunTitle.displayTitle(for: run, calendar: calendar),
            dateLabel: date.string(from: run.startedAt),
            distanceLabel: distance > 0 ? String(format: "%.1f", locale: locale, distance / 1000) : "--",
            distanceUnit: "km",
            durationLabel: time > 0 ? duration(time) : "--",
            paceLabel: pace.isFinite && pace > 0 && pace < Double(Int.max / 2) ? "\(paceDuration(pace)) /km" : "--",
            sourceLabel: RunSmartAttribution.sourceLabel(for: run),
            insight: String(insight.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150)),
            privacyNote: route.isEmpty ? "No location data is included." : RouteSharePrivacy.privacyNote,
            distanceMeters: distance,
            movingTimeSeconds: time,
            routePoints: route
        )
    }

    var shareCaption: String {
        ["RunSmart · \(title)", "\(distanceLabel) \(distanceUnit) · \(durationLabel) · \(paceLabel)", privacyNote]
            .joined(separator: "\n")
    }

    /// A rejected fix creates a gap; filtering it must not connect the neighboring stretches.
    private static func validRoutePoints(_ points: [RunRoutePoint]) -> [RunRoutePoint] {
        var result: [RunRoutePoint] = []
        var hasGap = false
        for point in points {
            guard point.latitude.isFinite, point.longitude.isFinite,
                  CLLocationCoordinate2DIsValid(point.coordinate),
                  point.horizontalAccuracy.isFinite, point.horizontalAccuracy >= 0,
                  point.timestamp.timeIntervalSince1970.isFinite else {
                hasGap = true
                continue
            }
            var copy = point
            if hasGap { copy.startsNewSegment = true }
            result.append(copy)
            hasGap = false
        }
        return result
    }

    private static func duration(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        if whole >= 3600 { return "\(whole / 3600):\(String(format: "%02d:%02d", (whole % 3600) / 60, whole % 60))" }
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }

    private static func paceDuration(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }
}

/// Includes actual insight content and run data, not just switches. A ready export cannot
/// be reused after a report refresh or a map opt-out while a new task is being scheduled.
struct RunShareRenderKey: Hashable {
    let format: RunShareAssetFormat
    let run: RecordedRun?
    let includeMap: Bool
    let insight: String?

    func hash(into hasher: inout Hasher) {
        // Equality still compares the full run. Stable coarse hashing avoids rehashing an entire
        // GPS array on each progress update; hash collisions never make unequal keys equal.
        hasher.combine(format)
        hasher.combine(run?.id)
        hasher.combine(includeMap)
        hasher.combine(insight)
    }
}

struct RunSharePreparedAsset {
    let key: RunShareRenderKey
    let snapshot: RunShareSnapshot
    let fileURL: URL

    func url(matching current: RunShareRenderKey) -> URL? {
        key == current ? fileURL : nil
    }

    func activityItem(matching current: RunShareRenderKey) -> RunShareActivityItem? {
        guard key == current else { return nil }
        return RunShareActivityItem(fileURL: fileURL, caption: snapshot.shareCaption)
    }
}
