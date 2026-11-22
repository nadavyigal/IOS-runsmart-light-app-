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
        /// C7.8: the v2 consent copy was shown (P8 at join, P9 on Today).
        case consentV2Shown(surface: CoachConsentSurface)
        /// C7.8: the athlete accepted the v2 copy and the server recorded it.
        case consentV2Acked(surface: CoachConsentSurface)
        /// C7.8: P9 "Leave {Coach}" opened the leave sheet.
        case consentV2LeaveTapped(surface: CoachConsentSurface)
        /// C7.3: the athlete set effort. `shared` = it was queued for the coach. Never the value.
        case runRPESet(shared: Bool)
        /// C7.3: the athlete saved a run note. Never the text.
        case runNoteSaved(shared: Bool)
        /// C7.3: "Hide note from {Coach}" was turned on or off.
        case runNoteHiddenToggled(hidden: Bool)
        /// C7.3: the one-time RPE backfill after the ack queued `count` runs (D7).
        case rpeBackfillDone(count: Int)

        var name: String {
            switch self {
            case .coachTodayViewed: "coach_today_viewed"
            case .coachTodayRowOpened: "coach_today_row_opened"
            case .consentV2Shown: "consent_v2_shown"
            case .consentV2Acked: "consent_v2_acked"
            case .consentV2LeaveTapped: "consent_v2_leave_tapped"
            case .runRPESet: "run_rpe_set"
            case .runNoteSaved: "run_note_saved"
            case .runNoteHiddenToggled: "run_note_hidden_toggled"
            case .rpeBackfillDone: "rpe_backfill_done"
            }
        }

        var properties: [String: Value] {
            switch self {
            case .coachTodayViewed(let athleteCount, let needCount):
                ["athlete_count": .count(athleteCount), "need_count": .count(needCount)]
            case .coachTodayRowOpened(let reason):
                ["reason": .kind(reason)]
            case .consentV2Shown(let surface), .consentV2Acked(let surface), .consentV2LeaveTapped(let surface):
                ["surface": .kind(surface.rawValue)]
            case .runRPESet(let shared), .runNoteSaved(let shared):
                ["shared": .flag(shared)]
            case .runNoteHiddenToggled(let hidden):
                ["hidden": .flag(hidden)]
            case .rpeBackfillDone(let count):
                ["count": .count(count)]
            }
        }
    }

    /// Sends one event through the app's analytics path (PostHog via `Analytics.shared`).
    @MainActor
    static func track(_ event: Event, to tracker: any AnalyticsTracking = Analytics.shared) {
        tracker.track(event.name, properties: event.properties.mapValues(\.raw))
    }
}
