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
        /// C7.2: the coach opened an athlete's detail and it was marked seen. `newCount` is how many new
        /// items the marker showed (0 when nothing was new).
        case coachAthleteSeen(newCount: Int)
        /// C7.2: a linked v2 athlete saved a new goal and the goal change was queued for the coach.
        case athleteGoalChangeLogged
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
        /// C7.4: the athlete sent a flag. `hasRun` = it is about a run (false for Today's run-less entry).
        /// Never the note.
        case flagCreated(kind: RunFlagKind, hasRun: Bool)
        /// C7.4: the athlete removed an unhandled flag.
        case flagRemoved
        /// C7.4: the coach's "Mark handled" reached the server. Minutes from the flag to the resolve.
        case flagResolved(minutesOpen: Int)
        /// C7.16: a milestone tag was on Coach Today. `kind` is a `CoachMilestoneKind` raw value. Once per
        /// milestone per session, never the athlete.
        case milestoneShown(kind: String)
        /// C7.16: the coach tapped a one-tap reaction on a milestone. Never which reaction or the athlete.
        case praiseSent(kind: String)
        /// C7.7: the athlete's reply to a coach note reached the server. `target` says what kind of note
        /// it answers. Never the text.
        case coachNoteReplySent(target: FeedbackReplyTarget)
        /// C7.11: the coach removed an athlete and the server ended the link. No properties.
        case coachRemovedAthlete
        /// C7.11: the athlete left their coach (A13 or P9) and the server ended the link. No properties.
        case athleteLeftCoach
        /// C7.10: T6 or P10 shown (once per account and role).
        case pushPermissionPrompted(role: RemotePushRole)
        /// C7.10: the system prompt's answer.
        case pushPermissionResult(role: RemotePushRole, granted: Bool)
        /// C7.10: a remote push was tapped.
        case pushOpened(kind: RemotePushKind)

        var name: String {
            switch self {
            case .coachTodayViewed: "coach_today_viewed"
            case .coachTodayRowOpened: "coach_today_row_opened"
            case .coachAthleteSeen: "coach_athlete_seen"
            case .athleteGoalChangeLogged: "athlete_goal_change_logged"
            case .consentV2Shown: "consent_v2_shown"
            case .consentV2Acked: "consent_v2_acked"
            case .consentV2LeaveTapped: "consent_v2_leave_tapped"
            case .runRPESet: "run_rpe_set"
            case .runNoteSaved: "run_note_saved"
            case .runNoteHiddenToggled: "run_note_hidden_toggled"
            case .rpeBackfillDone: "rpe_backfill_done"
            case .flagCreated: "flag_created"
            case .flagRemoved: "flag_removed"
            case .flagResolved: "flag_resolved"
            case .milestoneShown: "milestone_shown"
            case .praiseSent: "praise_sent"
            case .coachNoteReplySent: "coach_note_reply_sent"
            case .coachRemovedAthlete: "coach_removed_athlete"
            case .athleteLeftCoach: "athlete_left_coach"
            case .pushPermissionPrompted: "push_permission_prompted"
            case .pushPermissionResult: "push_permission_result"
            case .pushOpened: "push_opened"
            }
        }

        var properties: [String: Value] {
            switch self {
            case .coachTodayViewed(let athleteCount, let needCount):
                ["athlete_count": .count(athleteCount), "need_count": .count(needCount)]
            case .coachTodayRowOpened(let reason):
                ["reason": .kind(reason)]
            case .coachAthleteSeen(let newCount):
                ["new_count": .count(newCount)]
            case .athleteGoalChangeLogged, .coachRemovedAthlete, .athleteLeftCoach:
                [:]
            case .consentV2Shown(let surface), .consentV2Acked(let surface), .consentV2LeaveTapped(let surface):
                ["surface": .kind(surface.rawValue)]
            case .runRPESet(let shared), .runNoteSaved(let shared):
                ["shared": .flag(shared)]
            case .runNoteHiddenToggled(let hidden):
                ["hidden": .flag(hidden)]
            case .rpeBackfillDone(let count):
                ["count": .count(count)]
            case .flagCreated(let kind, let hasRun):
                ["kind": .kind(kind.rawValue), "has_run": .flag(hasRun)]
            case .flagRemoved:
                [:]
            case .flagResolved(let minutesOpen):
                ["minutes_open": .count(minutesOpen)]
            case .milestoneShown(let kind), .praiseSent(let kind):
                ["kind": .kind(kind)]
            case .coachNoteReplySent(let target):
                ["target": .kind(target.rawValue)]
            case .pushPermissionPrompted(let role):
                ["role": .kind(role.rawValue)]
            case .pushPermissionResult(let role, let granted):
                ["role": .kind(role.rawValue), "granted": .flag(granted)]
            case .pushOpened(let kind):
                ["kind": .kind(kind.rawValue)]
            }
        }
    }

    /// Sends one event through the app's analytics path (PostHog via `Analytics.shared`).
    @MainActor
    static func track(_ event: Event, to tracker: any AnalyticsTracking = Analytics.shared) {
        tracker.track(event.name, properties: event.properties.mapValues(\.raw))
    }
}
