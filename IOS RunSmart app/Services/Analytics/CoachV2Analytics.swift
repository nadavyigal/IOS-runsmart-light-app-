import Foundation

/// Typed analytics for Coach Experience v2 (refined plan S3, v1.3 §3.8).
///
/// C7.0 ships this with no events. Each later story adds its own cases from v1.3 §3.8
/// in the PR that fires them, so events are reviewed with the code that sends them.
///
/// Property rules (v1.3 §3.8): only internal uuids, enums, counts and durations.
/// Never names, note, flag or reply text, or RPE values tied to a person. Use
/// `CoachV2Analytics.Value` so a free-text property cannot compile.
nonisolated enum CoachV2Analytics {
    /// The only property values an event may carry.
    enum Value: Equatable, Sendable {
        case id(UUID)
        case count(Int)
        case seconds(Int)
        case flag(Bool)
        /// A fixed enum case from code, never user text.
        case kind(String)

        var raw: Any {
            switch self {
            case .id(let id): id.uuidString.lowercased()
            case .count(let value): value
            case .seconds(let value): value
            case .flag(let value): value
            case .kind(let value): value
            }
        }
    }

    /// One case per event. Each story adds its own (v1.3 section 3.8).
    enum Event: Sendable, Equatable {
        /// C7.1: Coach Today first has data on screen. Counts only.
        case coachTodayViewed(athleteCount: Int, needCount: Int)
        /// C7.1: a Today row was opened. `reason` is a `CoachTodayReason` raw value, or "none".
        case coachTodayRowOpened(reason: String)

        var name: String {
            switch self {
            case .coachTodayViewed: "coach_today_viewed"
            case .coachTodayRowOpened: "coach_today_row_opened"
            }
        }

        var properties: [String: Value] {
            switch self {
            case .coachTodayViewed(let athleteCount, let needCount):
                ["athlete_count": .count(athleteCount), "need_count": .count(needCount)]
            case .coachTodayRowOpened(let reason):
                ["reason": .kind(reason)]
            }
        }
    }

    /// Sends one event through the app's analytics path (PostHog via `Analytics.shared`).
    @MainActor
    static func track(_ event: Event, to tracker: any AnalyticsTracking = Analytics.shared) {
        tracker.track(event.name, properties: event.properties.mapValues(\.raw))
    }
}
