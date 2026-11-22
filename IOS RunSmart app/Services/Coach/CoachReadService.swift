import Foundation
import Supabase

// "Coach" in this file means a HUMAN coach (Coach Mode). It is unrelated to the
// AI coach: `coach_message`, `profiles.coaching_style`, `CoachFlowView`.
//
// Story 2.2. These calls are the only coach read of a linked athlete's plan,
// workouts, and run summaries. Week boundaries are dates the caller computes.
// There is no UI here.

enum CoachReadRPC {
    static let listAthletes = "coach_list_athletes"
    static let plan = "coach_get_athlete_plan"
    static let workouts = "coach_get_athletes_workouts"
    static let runs = "coach_get_athletes_runs"
}

nonisolated enum CoachReadDay {
    /// `yyyy-MM-dd` in `calendar`'s time zone. The server treats a run's date as
    /// the UTC date of `runs.completed_at`, and a workout's date as `scheduled_date`.
    static func iso(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

struct CoachAthleteSummary: Codable, Equatable, Sendable {
    let athleteID: UUID
    let displayName: String
    let linkedAt: Date
    let hasActivePlan: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case athleteID = "athlete_id"
        case displayName = "display_name"
        case linkedAt = "linked_at"
        case hasActivePlan = "has_active_plan"
    }

    init(athleteID: UUID, displayName: String, linkedAt: Date, hasActivePlan: Bool) {
        self.athleteID = athleteID
        self.displayName = displayName
        self.linkedAt = linkedAt
        self.hasActivePlan = hasActivePlan
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        athleteID = try container.decode(UUID.self, forKey: .athleteID)
        displayName = try container.decode(String.self, forKey: .displayName)
        linkedAt = try CoachReadTimestamp.date(from: container.decode(String.self, forKey: .linkedAt), key: .linkedAt, container: container)
        hasActivePlan = try container.decode(Bool.self, forKey: .hasActivePlan)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(athleteID, forKey: .athleteID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(CoachReadTimestamp.iso(linkedAt), forKey: .linkedAt)
        try container.encode(hasActivePlan, forKey: .hasActivePlan)
    }
}

struct CoachPlanSummary: Codable, Equatable, Sendable {
    let id: UUID
    let athleteID: UUID
    let title: String
    let startDate: String
    let endDate: String
    let targetDistance: Double?
    let targetTime: Int?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case athleteID = "athlete_id"
        case title
        case startDate = "start_date"
        case endDate = "end_date"
        case targetDistance = "target_distance"
        case targetTime = "target_time"
    }
}

struct CoachWorkoutSummary: Codable, Equatable, Sendable {
    let id: UUID
    let athleteID: UUID
    let planID: UUID
    let scheduledDate: String
    let type: String
    let plannedDistance: Double
    let plannedDurationMinutes: Int?
    let targetPace: Int?
    let completed: Bool
    let completedAt: Date?
    let actualDistanceKm: Double?
    let actualDurationMinutes: Int?
    let actualPace: Int?
    let notes: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case athleteID = "athlete_id"
        case planID = "plan_id"
        case scheduledDate = "scheduled_date"
        case type
        case plannedDistance = "planned_distance"
        case plannedDurationMinutes = "planned_duration_minutes"
        case targetPace = "target_pace"
        case completed
        case completedAt = "completed_at"
        case actualDistanceKm = "actual_distance_km"
        case actualDurationMinutes = "actual_duration_minutes"
        case actualPace = "actual_pace"
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        athleteID = try container.decode(UUID.self, forKey: .athleteID)
        planID = try container.decode(UUID.self, forKey: .planID)
        scheduledDate = try container.decode(String.self, forKey: .scheduledDate)
        type = try container.decode(String.self, forKey: .type)
        plannedDistance = try container.decode(Double.self, forKey: .plannedDistance)
        plannedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .plannedDurationMinutes)
        targetPace = try container.decodeIfPresent(Int.self, forKey: .targetPace)
        completed = try container.decode(Bool.self, forKey: .completed)
        if let raw = try container.decodeIfPresent(String.self, forKey: .completedAt) {
            completedAt = try CoachReadTimestamp.date(from: raw, key: .completedAt, container: container)
        } else {
            completedAt = nil
        }
        actualDistanceKm = try container.decodeIfPresent(Double.self, forKey: .actualDistanceKm)
        actualDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .actualDurationMinutes)
        actualPace = try container.decodeIfPresent(Int.self, forKey: .actualPace)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(athleteID, forKey: .athleteID)
        try container.encode(planID, forKey: .planID)
        try container.encode(scheduledDate, forKey: .scheduledDate)
        try container.encode(type, forKey: .type)
        try container.encode(plannedDistance, forKey: .plannedDistance)
        try container.encodeIfPresent(plannedDurationMinutes, forKey: .plannedDurationMinutes)
        try container.encodeIfPresent(targetPace, forKey: .targetPace)
        try container.encode(completed, forKey: .completed)
        try container.encodeIfPresent(completedAt.map(CoachReadTimestamp.iso), forKey: .completedAt)
        try container.encodeIfPresent(actualDistanceKm, forKey: .actualDistanceKm)
        try container.encodeIfPresent(actualDurationMinutes, forKey: .actualDurationMinutes)
        try container.encodeIfPresent(actualPace, forKey: .actualPace)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

struct CoachRunSummary: Codable, Equatable, Sendable {
    let id: Int
    let athleteID: UUID
    let workoutID: UUID?
    let completedAt: Date
    let type: String?
    let distanceKm: Double
    let durationSeconds: Int
    let pace: Double?
    let averageHeartRate: Int?
    let source: String?
    /// C7.3: shared effort 1 to 10. Nil when not shared (no ack, not v2, kill switch, or
    /// a server without M1a).
    let rpe: Int?
    /// C7.3: a note the coach may read with `CoachRunNotesFetcher`. False when hidden.
    let hasNote: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case athleteID = "athlete_id"
        case workoutID = "workout_id"
        case completedAt = "completed_at"
        case type
        case distanceKm = "distance_km"
        case durationSeconds = "duration_seconds"
        case pace
        case averageHeartRate = "average_heart_rate"
        case source
        case rpe
        case hasNote = "has_note"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        athleteID = try container.decode(UUID.self, forKey: .athleteID)
        workoutID = try container.decodeIfPresent(UUID.self, forKey: .workoutID)
        completedAt = try CoachReadTimestamp.date(from: container.decode(String.self, forKey: .completedAt), key: .completedAt, container: container)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        pace = try container.decodeIfPresent(Double.self, forKey: .pace)
        averageHeartRate = try container.decodeIfPresent(Int.self, forKey: .averageHeartRate)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        rpe = try container.decodeIfPresent(Int.self, forKey: .rpe)
        hasNote = try container.decodeIfPresent(Bool.self, forKey: .hasNote) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(athleteID, forKey: .athleteID)
        try container.encodeIfPresent(workoutID, forKey: .workoutID)
        try container.encode(CoachReadTimestamp.iso(completedAt), forKey: .completedAt)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encode(distanceKm, forKey: .distanceKm)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(pace, forKey: .pace)
        try container.encodeIfPresent(averageHeartRate, forKey: .averageHeartRate)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(rpe, forKey: .rpe)
        try container.encode(hasNote, forKey: .hasNote)
    }
}

struct CoachWorkoutQuery: Encodable, Equatable {
    var from: String
    var to: String
    var athleteIDs: [UUID]?

    enum CodingKeys: String, CodingKey {
        case from = "p_from"
        case to = "p_to"
        case athleteIDs = "p_athlete_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encodeIfPresent(athleteIDs, forKey: .athleteIDs)
    }
}

nonisolated struct CoachRunQuery: Encodable, Equatable, Sendable {
    var from: String
    var to: String
    var athleteIDs: [UUID]?

    var latestThrough: Date? = nil

    enum CodingKeys: String, CodingKey {
        case from = "p_from"
        case to = "p_to"
        case athleteIDs = "p_athlete_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encodeIfPresent(athleteIDs, forKey: .athleteIDs)
    }
}

struct CoachPlanParams: Encodable, Equatable {
    var athleteID: UUID

    enum CodingKeys: String, CodingKey {
        case athleteID = "p_athlete"
    }
}

nonisolated protocol CoachReadServing: Sendable {
    func listAthletes() async throws -> [CoachAthleteSummary]
    func plan(for athleteID: UUID) async throws -> [CoachPlanSummary]
    func workouts(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachWorkoutSummary]
    func runs(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachRunSummary]
    func latestRun(for athleteID: UUID, through: Date) async throws -> CoachRunSummary?
}

nonisolated protocol CoachReadFetching: Sendable {
    func listAthletes() async throws -> [CoachAthleteSummary]
    func plans(for athleteID: UUID) async throws -> [CoachPlanSummary]
    func workouts(_ query: CoachWorkoutQuery) async throws -> [CoachWorkoutSummary]
    func runs(_ query: CoachRunQuery) async throws -> [CoachRunSummary]
}

struct CoachReadService: CoachReadServing {
    private let client: any CoachReadFetching

    init(client: any CoachReadFetching = SupabaseCoachReadClient()) {
        self.client = client
    }

    func listAthletes() async throws -> [CoachAthleteSummary] {
        try await client.listAthletes()
    }

    func plan(for athleteID: UUID) async throws -> [CoachPlanSummary] {
        try await client.plans(for: athleteID)
    }

    func workouts(from: Date, to: Date, athleteIDs: [UUID]? = nil, calendar: Calendar) async throws -> [CoachWorkoutSummary] {
        try await client.workouts(CoachWorkoutQuery(
            from: CoachReadDay.iso(from, calendar: calendar),
            to: CoachReadDay.iso(to, calendar: calendar),
            athleteIDs: athleteIDs
        ))
    }

    func runs(from: Date, to: Date, athleteIDs: [UUID]? = nil, calendar: Calendar) async throws -> [CoachRunSummary] {
        try await client.runs(CoachRunQuery(
            from: CoachReadDay.iso(from, calendar: calendar),
            to: CoachReadDay.iso(to, calendar: calendar),
            athleteIDs: athleteIDs
        ))
    }

    func latestRun(for athleteID: UUID, through: Date) async throws -> CoachRunSummary? {
        let day = CoachReadDay.iso(through, calendar: .coachRunUTC)
        return try await client.runs(CoachRunQuery(
            from: "1900-01-01", to: day, athleteIDs: [athleteID], latestThrough: through
        )).first
    }
}

struct SupabaseCoachReadClient: CoachReadFetching {
    func listAthletes() async throws -> [CoachAthleteSummary] {
        try await SupabaseManager.client
            .rpc(CoachReadRPC.listAthletes)
            .execute()
            .value
    }

    func plans(for athleteID: UUID) async throws -> [CoachPlanSummary] {
        try await SupabaseManager.client
            .rpc(CoachReadRPC.plan, params: CoachPlanParams(athleteID: athleteID))
            .execute()
            .value
    }

    func workouts(_ query: CoachWorkoutQuery) async throws -> [CoachWorkoutSummary] {
        try await SupabaseManager.client
            .rpc(CoachReadRPC.workouts, params: query)
            .execute()
            .value
    }

    func runs(_ query: CoachRunQuery) async throws -> [CoachRunSummary] {
        let request = try await SupabaseManager.client.rpc(CoachReadRPC.runs, params: query)
        if let through = query.latestThrough {
            return try await request.lte("completed_at", value: CoachReadTimestamp.iso(through))
                .order("completed_at", ascending: false)
                .order("id", ascending: false).limit(1).execute().value
        }
        return try await request.execute().value
    }
}

/// In-memory stand-in for tests and later screens. It does not talk to Supabase.
struct MockCoachReadService: CoachReadServing {
    var athletes: [CoachAthleteSummary] = []
    var plans: [UUID: [CoachPlanSummary]] = [:]
    var workoutResults: [CoachWorkoutSummary] = []
    var runResults: [CoachRunSummary] = []

    func latestRun(for athleteID: UUID, through: Date) async throws -> CoachRunSummary? {
        runResults.filter { $0.athleteID == athleteID && $0.completedAt <= through }
            .max { $0.completedAt < $1.completedAt }
    }

    func listAthletes() async throws -> [CoachAthleteSummary] { athletes }

    func plan(for athleteID: UUID) async throws -> [CoachPlanSummary] {
        plans[athleteID] ?? []
    }

    func workouts(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachWorkoutSummary] {
        _ = (from, to, athleteIDs, calendar)
        return workoutResults
    }

    func runs(from: Date, to: Date, athleteIDs: [UUID]?, calendar: Calendar) async throws -> [CoachRunSummary] {
        _ = (from, to, athleteIDs, calendar)
        return runResults
    }
}

private nonisolated enum CoachReadTimestamp {
    static func date<K: CodingKey>(from raw: String, key: K, container: KeyedDecodingContainer<K>) throws -> Date {
        if let date = parsed(raw) { return date }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: raw)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func parsed(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ssXXX", "yyyy-MM-dd HH:mm:ssXX", "yyyy-MM-dd HH:mm:ssX"] {
            fallback.dateFormat = format
            if let date = fallback.date(from: raw) { return date }
        }
        return nil
    }
}


extension Calendar {
    nonisolated static var coachRunUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
