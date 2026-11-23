import Foundation
import Supabase
@preconcurrency import UserNotifications

// Coach Experience v2, story C7.14: notification settings, coach (T5) and athlete (G13).
// "Coach" means a HUMAN coach (Coach Mode), not the AI coach.
//
// Server side: M2a, supabase/migrations/20261122100000_push_tokens_and_prefs.sql (C7.10).
//   my_notification_prefs(p_time_zone)   the first read creates the own row with the D6 defaults
//   update_notification_prefs(...)       a null argument keeps the stored value
// There is no client insert or update policy: every write goes through those functions.
//
// Everything the screens need from the outside sits behind two protocols
// (`NotificationPrefsStore`, `NotificationPermissionFlow`) so tests and fixtures never
// touch the server or the system prompt.

// MARK: Kinds

/// One toggle. Raw values are the analytics `kind` (v1.3 section 3.8: enums, never text).
nonisolated enum NotificationPrefKind: String, CaseIterable, Sendable {
    case coachRunFinished = "coach_run_finished"
    case coachEveningSummary = "coach_evening_summary"
    case coachPainFlag = "coach_pain_flag"
    case athleteCoachNote = "athlete_coach_note"
    case athletePlanUpdates = "athlete_plan_updates"
    case athleteBroadcasts = "athlete_broadcasts"
}

/// Which screen: the coach's T5, or the athlete's My coach › Notifications.
nonisolated enum NotificationSettingsAudience: Equatable, Sendable {
    case coach
    case athlete(coachName: String)

    /// The toggles that audience sees, in screen order.
    var kinds: [NotificationPrefKind] {
        switch self {
        case .coach: [.coachRunFinished, .coachPainFlag, .coachEveningSummary]
        case .athlete: [.athleteCoachNote, .athletePlanUpdates, .athleteBroadcasts]
        }
    }
}

// MARK: Quiet hours time

/// A time of day without a date: what `time` columns hold. Compared and sent as minutes.
nonisolated struct QuietTime: Equatable, Hashable, Sendable {
    let minutes: Int

    init(hour: Int, minute: Int) {
        minutes = ((hour * 60 + minute) % 1440 + 1440) % 1440
    }

    /// Reads Postgres `time` text: "21:30:00", "21:30" or "21:30:00.5".
    init?(postgres text: String) {
        let parts = text.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }

    /// The `time` text sent to Postgres.
    var postgresText: String { String(format: "%02d:%02d:00", hour, minute) }

    /// The 24-hour label the copy shows ("21:30").
    var label: String { String(format: "%02d:%02d", hour, minute) }

    /// The D6 defaults (v1.3 section 3).
    static let defaultStart = QuietTime(hour: 21, minute: 30)
    static let defaultEnd = QuietTime(hour: 7, minute: 0)
}

// MARK: Row and patch

/// One `notification_prefs` row, as `my_notification_prefs` and `update_notification_prefs` return it.
nonisolated struct NotificationPrefs: Codable, Equatable, Sendable {
    var coachRunFinished: Bool
    var coachEveningSummary: Bool
    var coachPainFlag: Bool
    var athleteCoachNote: Bool
    var athletePlanUpdates: Bool
    var athleteBroadcasts: Bool
    var quietStart: QuietTime
    var quietEnd: QuietTime
    var timeZone: String

    enum CodingKeys: String, CodingKey {
        case coachRunFinished = "coach_run_finished"
        case coachEveningSummary = "coach_evening_summary"
        case coachPainFlag = "coach_pain_flag"
        case athleteCoachNote = "athlete_coach_note"
        case athletePlanUpdates = "athlete_plan_updates"
        case athleteBroadcasts = "athlete_broadcasts"
        case quietStart = "quiet_start"
        case quietEnd = "quiet_end"
        case timeZone = "time_zone"
    }

    init(
        coachRunFinished: Bool = true, coachEveningSummary: Bool = true, coachPainFlag: Bool = true,
        athleteCoachNote: Bool = true, athletePlanUpdates: Bool = true, athleteBroadcasts: Bool = true,
        quietStart: QuietTime = .defaultStart, quietEnd: QuietTime = .defaultEnd, timeZone: String = "UTC"
    ) {
        self.coachRunFinished = coachRunFinished
        self.coachEveningSummary = coachEveningSummary
        self.coachPainFlag = coachPainFlag
        self.athleteCoachNote = athleteCoachNote
        self.athletePlanUpdates = athletePlanUpdates
        self.athleteBroadcasts = athleteBroadcasts
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.timeZone = timeZone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coachRunFinished = try container.decode(Bool.self, forKey: .coachRunFinished)
        coachEveningSummary = try container.decode(Bool.self, forKey: .coachEveningSummary)
        coachPainFlag = try container.decode(Bool.self, forKey: .coachPainFlag)
        athleteCoachNote = try container.decode(Bool.self, forKey: .athleteCoachNote)
        athletePlanUpdates = try container.decode(Bool.self, forKey: .athletePlanUpdates)
        athleteBroadcasts = try container.decode(Bool.self, forKey: .athleteBroadcasts)
        timeZone = try container.decode(String.self, forKey: .timeZone)
        let start = try container.decode(String.self, forKey: .quietStart)
        let end = try container.decode(String.self, forKey: .quietEnd)
        guard let parsedStart = QuietTime(postgres: start), let parsedEnd = QuietTime(postgres: end) else {
            throw DecodingError.dataCorruptedError(
                forKey: .quietStart, in: container, debugDescription: "Unreadable quiet hours time")
        }
        quietStart = parsedStart
        quietEnd = parsedEnd
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coachRunFinished, forKey: .coachRunFinished)
        try container.encode(coachEveningSummary, forKey: .coachEveningSummary)
        try container.encode(coachPainFlag, forKey: .coachPainFlag)
        try container.encode(athleteCoachNote, forKey: .athleteCoachNote)
        try container.encode(athletePlanUpdates, forKey: .athletePlanUpdates)
        try container.encode(athleteBroadcasts, forKey: .athleteBroadcasts)
        try container.encode(quietStart.postgresText, forKey: .quietStart)
        try container.encode(quietEnd.postgresText, forKey: .quietEnd)
        try container.encode(timeZone, forKey: .timeZone)
    }

    func isOn(_ kind: NotificationPrefKind) -> Bool {
        switch kind {
        case .coachRunFinished: coachRunFinished
        case .coachEveningSummary: coachEveningSummary
        case .coachPainFlag: coachPainFlag
        case .athleteCoachNote: athleteCoachNote
        case .athletePlanUpdates: athletePlanUpdates
        case .athleteBroadcasts: athleteBroadcasts
        }
    }
}

/// The arguments of `update_notification_prefs`. A nil field is left out of the request, so the
/// server keeps the stored value.
nonisolated struct NotificationPrefsPatch: Encodable, Equatable, Sendable {
    var coachRunFinished: Bool?
    var coachEveningSummary: Bool?
    var coachPainFlag: Bool?
    var athleteCoachNote: Bool?
    var athletePlanUpdates: Bool?
    var athleteBroadcasts: Bool?
    var quietStart: String?
    var quietEnd: String?

    enum CodingKeys: String, CodingKey {
        case coachRunFinished = "p_coach_run_finished"
        case coachEveningSummary = "p_coach_evening_summary"
        case coachPainFlag = "p_coach_pain_flag"
        case athleteCoachNote = "p_athlete_coach_note"
        case athletePlanUpdates = "p_athlete_plan_updates"
        case athleteBroadcasts = "p_athlete_broadcasts"
        case quietStart = "p_quiet_start"
        case quietEnd = "p_quiet_end"
    }

    static func toggle(_ kind: NotificationPrefKind, _ enabled: Bool) -> NotificationPrefsPatch {
        var patch = NotificationPrefsPatch()
        switch kind {
        case .coachRunFinished: patch.coachRunFinished = enabled
        case .coachEveningSummary: patch.coachEveningSummary = enabled
        case .coachPainFlag: patch.coachPainFlag = enabled
        case .athleteCoachNote: patch.athleteCoachNote = enabled
        case .athletePlanUpdates: patch.athletePlanUpdates = enabled
        case .athleteBroadcasts: patch.athleteBroadcasts = enabled
        }
        return patch
    }

    static func quietHours(start: QuietTime, end: QuietTime) -> NotificationPrefsPatch {
        var patch = NotificationPrefsPatch()
        patch.quietStart = start.postgresText
        patch.quietEnd = end.postgresText
        return patch
    }
}

// MARK: Store

nonisolated protocol NotificationPrefsStore: Sendable {
    /// `my_notification_prefs(p_time_zone)`: the first read creates the row with the D6 defaults.
    func load(timeZone: String) async throws -> NotificationPrefs
    /// `update_notification_prefs(...)`: returns the stored row.
    func update(_ patch: NotificationPrefsPatch) async throws -> NotificationPrefs
}

enum NotificationPrefsRPC {
    static let read = "my_notification_prefs"
    static let update = "update_notification_prefs"
}

nonisolated struct SupabaseNotificationPrefsStore: NotificationPrefsStore {
    private struct ReadParams: Encodable {
        let timeZone: String
        enum CodingKeys: String, CodingKey { case timeZone = "p_time_zone" }
    }

    func load(timeZone: String) async throws -> NotificationPrefs {
        try await SupabaseManager.client
            .rpc(NotificationPrefsRPC.read, params: ReadParams(timeZone: timeZone))
            .execute()
            .value
    }

    func update(_ patch: NotificationPrefsPatch) async throws -> NotificationPrefs {
        try await SupabaseManager.client
            .rpc(NotificationPrefsRPC.update, params: patch)
            .execute()
            .value
    }
}

// MARK: Permission

/// What the system says about notifications for this app. Reading it never prompts.
nonisolated enum NotificationPermissionStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case granted

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .granted
        @unknown default: self = .denied
        }
    }
}

/// The permission side of the settings screens.
///
/// `turnOn` must run the in-app pre-permission flow (T6 for the coach, P10 for the athlete,
/// C7.10), never the raw system prompt, and it never prompts again after a denial.
nonisolated protocol NotificationPermissionFlow: Sendable {
    func status() async -> NotificationPermissionStatus
    func turnOn(for audience: NotificationSettingsAudience) async -> NotificationPermissionStatus
}

/// Reads the system status. `turnOn` waits for C7.10's T6/P10 flow (`RemotePushRegistrar`): until
/// that lands it changes nothing and shows no prompt. The catch-up after C7.10 merges replaces this
/// type's `turnOn` with a call into that flow; the screens and the model stay as they are.
nonisolated struct SystemNotificationPermissionFlow: NotificationPermissionFlow {
    func status() async -> NotificationPermissionStatus {
        NotificationPermissionStatus(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    func turnOn(for audience: NotificationSettingsAudience) async -> NotificationPermissionStatus {
        await status()
    }
}
