import Foundation
import Supabase

// C7.2 "New since last visit" (v1.3 C7.2, UX spec A.3 and A.4). "Coach" means a HUMAN coach (Coach Mode).
//
// Server: 20261121130000_coach_last_seen_and_events.sql (M3). Seen state lives on the server, so a second
// coach phone clears the marker after a refresh. Both writes go through a small outbox so an offline open or
// goal save is sent on the next foreground (v1.3 §1.1 offline AC).

enum CoachSeenRPC {
    static let rosterSummary = "coach_roster_summary"
    static let markSeen = "coach_mark_athlete_seen"
    static let logGoalChange = "athlete_log_goal_change"
}

/// The `coach_athlete_events` kinds the coach can see as new. `left` and `removed` are never counted.
enum CoachAthleteEventKind: String, Codable, Equatable, Sendable {
    case goalChange = "goal_change"
    case athleteSkip = "athlete_skip"
    case athleteMove = "athlete_move"
}

/// What is new for one athlete since the coach last opened them. One row of `coach_roster_summary`.
nonisolated struct CoachAthleteNews: Equatable, Sendable {
    var seenAt: Date?
    var newRuns: Int
    var newFlags: Int
    var newReplies: Int
    var newEvents: Int
    var latestEventKind: CoachAthleteEventKind?
    var oldestNewAt: Date?

    init(
        seenAt: Date? = nil, newRuns: Int = 0, newFlags: Int = 0, newReplies: Int = 0, newEvents: Int = 0,
        latestEventKind: CoachAthleteEventKind? = nil, oldestNewAt: Date? = nil
    ) {
        self.seenAt = seenAt
        self.newRuns = newRuns
        self.newFlags = newFlags
        self.newReplies = newReplies
        self.newEvents = newEvents
        self.latestEventKind = latestEventKind
        self.oldestNewAt = oldestNewAt
    }

    /// The "{n} new" number.
    var total: Int { max(newRuns, 0) + max(newFlags, 0) + max(newReplies, 0) + max(newEvents, 0) }

    /// The same athlete after the coach opened them on this phone: nothing is new.
    func seen(at date: Date) -> CoachAthleteNews { CoachAthleteNews(seenAt: date) }
}

nonisolated protocol CoachSeenRepository: Sendable {
    /// `coach_roster_summary()`: athlete id to news, for the caller's active v2 athletes.
    func rosterNews() async throws -> [UUID: CoachAthleteNews]
    /// `coach_mark_athlete_seen(p_athlete, p_seen_at)`. Idempotent; the server keeps the latest time.
    func markSeen(athleteID: UUID, seenAt: Date) async throws
    /// `athlete_log_goal_change(p_client_id)`. False means no active link; nothing was written.
    func logGoalChange(clientID: UUID) async throws -> Bool
}

nonisolated struct SupabaseCoachSeenRepository: CoachSeenRepository {
    private struct SummaryRow: Decodable {
        let athleteID: UUID
        let seenAt: String?
        let newRuns: Int
        let newFlags: Int
        let newReplies: Int
        let newEvents: Int
        let latestEventKind: String?
        let oldestNewAt: String?

        enum CodingKeys: String, CodingKey {
            case athleteID = "athlete_id"
            case seenAt = "seen_at"
            case newRuns = "new_runs"
            case newFlags = "new_flags"
            case newReplies = "new_replies"
            case newEvents = "new_events"
            case latestEventKind = "latest_event_kind"
            case oldestNewAt = "oldest_new_at"
        }
    }

    private struct SeenParams: Encodable {
        let p_athlete: UUID
        let p_seen_at: String
    }

    private struct GoalParams: Encodable {
        let p_client_id: UUID
    }

    func rosterNews() async throws -> [UUID: CoachAthleteNews] {
        let rows: [SummaryRow] = try await SupabaseManager.client
            .rpc(CoachSeenRPC.rosterSummary)
            .execute()
            .value
        return Dictionary(rows.map { row in
            (row.athleteID, CoachAthleteNews(
                seenAt: row.seenAt.flatMap(CoachSeenTimestamp.parse), newRuns: row.newRuns, newFlags: row.newFlags,
                newReplies: row.newReplies, newEvents: row.newEvents,
                latestEventKind: row.latestEventKind.flatMap(CoachAthleteEventKind.init(rawValue:)),
                oldestNewAt: row.oldestNewAt.flatMap(CoachSeenTimestamp.parse)
            ))
        }, uniquingKeysWith: { first, _ in first })
    }

    func markSeen(athleteID: UUID, seenAt: Date) async throws {
        try await SupabaseManager.client
            .rpc(CoachSeenRPC.markSeen, params: SeenParams(p_athlete: athleteID, p_seen_at: CoachSeenTimestamp.iso(seenAt)))
            .execute()
    }

    func logGoalChange(clientID: UUID) async throws -> Bool {
        try await SupabaseManager.client
            .rpc(CoachSeenRPC.logGoalChange, params: GoalParams(p_client_id: clientID))
            .execute()
            .value
    }
}

nonisolated enum CoachSeenTimestamp {
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func parse(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        // PostgREST can send "2026-11-22 10:00:00.123+00".
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss.SSSSSSXXX", "yyyy-MM-dd HH:mm:ss.SSSXXX", "yyyy-MM-dd HH:mm:ssXXX",
                       "yyyy-MM-dd HH:mm:ss.SSSSSSX", "yyyy-MM-dd HH:mm:ssX"] {
            fallback.dateFormat = format
            if let date = fallback.date(from: raw) { return date }
        }
        return nil
    }
}

// MARK: Outbox

/// One queued v2 write. `id` is made on the phone and sent as the client id, so two flushes store one row.
nonisolated struct CoachV2OutboxItem: Codable, Equatable, Sendable, Identifiable {
    enum Action: Codable, Equatable, Sendable {
        case markSeen(athleteID: UUID, seenAt: Date)
        case goalChange
    }

    let id: UUID
    let userID: UUID
    let action: Action
    let createdAt: Date
}

/// How a failed send is handled.
nonisolated enum CoachV2OutboxOutcome: Equatable {
    /// Sent, or the server will never take it (`link_inactive`, a bad request): remove it.
    case done
    /// Offline, `v2_unavailable` (kill switch) or the server lacks the migration: keep it and stop this flush.
    case retryLater

    static func classify(_ error: Error) -> CoachV2OutboxOutcome {
        if let postgrest = error as? PostgrestError {
            if postgrest.message == "link_inactive" { return .done }
            if postgrest.message == "v2_unavailable" { return .retryLater }
            // Bad input never succeeds on retry.
            if let code = postgrest.code, ["22023", "22P02"].contains(code) { return .done }
        }
        return .retryLater
    }
}

/// Persists queued v2 writes per device in UserDefaults and sends them in order. Items for another account
/// are kept for that account. Items older than `maxAge`, and anything past `maxItems`, are dropped so a pair
/// that never becomes v2 cannot grow the queue forever.
@MainActor
final class CoachV2Outbox {
    static let shared = CoachV2Outbox()
    static let maxAge: TimeInterval = 14 * 24 * 3600
    static let maxItems = 100

    private let defaults: UserDefaults
    private let key: String
    private let repository: any CoachSeenRepository
    private let tracker: any AnalyticsTracking
    private let now: () -> Date
    private var flushing = false

    init(
        defaults: UserDefaults = .standard,
        key: String = "runsmart.coachV2.outbox",
        repository: any CoachSeenRepository = SupabaseCoachSeenRepository(),
        tracker: (any AnalyticsTracking)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.repository = repository
        self.tracker = tracker ?? Analytics.shared
        self.now = now
    }

    /// C7.2 AC3: a goal save succeeded on a v2 client. Queued, so an offline save is told to the coach later.
    func logGoalChange(userID: UUID) async {
        enqueue(.goalChange, userID: userID)
        await flush(userID: userID)
    }

    nonisolated deinit {}

    var items: [CoachV2OutboxItem] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CoachV2OutboxItem].self, from: data) else { return [] }
        return decoded
    }

    private func save(_ items: [CoachV2OutboxItem]) {
        if items.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }

    /// Adds an item. A newer seen for the same athlete replaces the older one (the server keeps the latest).
    func enqueue(_ action: CoachV2OutboxItem.Action, userID: UUID) {
        var list = items
        if case .markSeen(let athleteID, _) = action {
            list.removeAll { item in
                guard item.userID == userID, case .markSeen(let queued, _) = item.action else { return false }
                return queued == athleteID
            }
        }
        list.append(CoachV2OutboxItem(id: UUID(), userID: userID, action: action, createdAt: now()))
        save(Array(list.suffix(Self.maxItems)))
    }

    /// Sends this account's items in order. Stops at the first one that must wait.
    func flush(userID: UUID) async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        let cutoff = now().addingTimeInterval(-Self.maxAge)
        save(items.filter { $0.createdAt >= cutoff })

        for item in items where item.userID == userID {
            let outcome: CoachV2OutboxOutcome
            do {
                switch item.action {
                case .markSeen(let athleteID, let seenAt):
                    try await repository.markSeen(athleteID: athleteID, seenAt: seenAt)
                case .goalChange:
                    // False means no active link: nothing to tell a coach, and no event (C7.2 AC4).
                    if try await repository.logGoalChange(clientID: item.id) {
                        CoachV2Analytics.track(.athleteGoalChangeLogged, to: tracker)
                    }
                }
                outcome = .done
            } catch {
                if error is CancellationError { return }
                outcome = CoachV2OutboxOutcome.classify(error)
            }
            guard outcome == .done else { return }
            save(items.filter { $0.id != item.id })
        }
    }
}
