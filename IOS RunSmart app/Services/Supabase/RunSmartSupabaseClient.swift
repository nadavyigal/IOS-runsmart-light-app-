import Foundation
import Supabase

// MARK: - Client singleton

enum SupabaseManager {
    static let client: SupabaseClient = {
        let auth = SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
        return SupabaseClient(
            supabaseURL: URL(string: "https://dxqglotcyirxzyqaxqln.supabase.co")!,
            supabaseKey: "sb_publishable_PpDpqkqVaKFnOyoLR7mdyA_UNTeeoqN",
            options: SupabaseClientOptions(auth: auth)
        )
    }()
}

// MARK: - Database row types

struct DBProfile: Sendable {
    let id: String           // supports legacy bigint and web UUID profile IDs
    let authUserId: UUID?
    let email: String
    let name: String?
    let goal: String         // nullable in DB; defaults to ""
    let experience: String   // nullable in DB; defaults to ""
    let preferredTimes: [String]
    let coachingStyle: String?
    let daysPerWeek: Int     // nullable in DB; defaults to 0
    let onboardingComplete: Bool
}

extension DBProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case email
        case name
        case goal
        case experience
        case preferredTimes = "preferred_times"
        case coachingStyle = "coaching_style"
        case daysPerWeek = "days_per_week"
        case onboardingComplete = "onboarding_complete"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            id = uuid.uuidString
        } else if let string = try? c.decode(String.self, forKey: .id) {
            id = string
        } else if let int = try? c.decode(Int.self, forKey: .id) {
            id = "\(int)"
        } else {
            id = ""
        }
        authUserId = try? c.decodeIfPresent(UUID.self, forKey: .authUserId)
        email = (try? c.decode(String.self, forKey: .email)) ?? ""
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        goal = (try? c.decode(String.self, forKey: .goal)) ?? ""
        experience = (try? c.decode(String.self, forKey: .experience)) ?? ""
        preferredTimes = (try? c.decode([String].self, forKey: .preferredTimes)) ?? []
        coachingStyle = try? c.decodeIfPresent(String.self, forKey: .coachingStyle)
        daysPerWeek = (try? c.decode(Int.self, forKey: .daysPerWeek)) ?? 0
        onboardingComplete = (try? c.decode(Bool.self, forKey: .onboardingComplete)) ?? false
    }
}

struct DBProfileInsert: Encodable, Sendable {
    let authUserId: String   // UUID string — matches auth_user_id uuid column
    let email: String        // NOT NULL in DB
    let name: String
    let goal: String
    let experience: String
    let preferredTimes: [String]
    let daysPerWeek: Int
    let coachingStyle: String
    let onboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case authUserId = "auth_user_id"
        case email
        case name
        case goal
        case experience
        case preferredTimes = "preferred_times"
        case daysPerWeek = "days_per_week"
        case coachingStyle = "coaching_style"
        case onboardingComplete = "onboarding_complete"
    }
}

enum DBProfileReference: Codable, Hashable, Sendable {
    case numeric(Int)
    case uuid(UUID)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let int = try? c.decode(Int.self) {
            self = .numeric(int)
        } else if let uuid = try? c.decode(UUID.self) {
            self = .uuid(uuid)
        } else if let string = try? c.decode(String.self), let uuid = UUID(uuidString: string) {
            self = .uuid(uuid)
        } else if let string = try? c.decode(String.self), let int = Int(string) {
            self = .numeric(int)
        } else if let string = try? c.decode(String.self) {
            self = .string(string)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .numeric(let value):
            try c.encode(value)
        case .uuid(let value):
            try c.encode(value.uuidString)
        case .string(let value):
            try c.encode(value)
        }
    }

    var debugValue: String {
        switch self {
        case .numeric(let value): "\(value)"
        case .uuid(let value): value.uuidString
        case .string(let value): value
        }
    }
}

struct DBPlan: Codable, Sendable {
    let id: UUID
    let profileId: DBProfileReference
    let title: String
    let description: String?
    let startDate: String
    let endDate: String
    let totalWeeks: Int
    let isActive: Bool
    let planType: String

    enum CodingKeys: String, CodingKey {
        case id
        case profileId = "profile_id"
        case title
        case description
        case startDate = "start_date"
        case endDate = "end_date"
        case totalWeeks = "total_weeks"
        case isActive = "is_active"
        case planType = "plan_type"
    }
}

struct DBWorkout: Codable, Sendable {
    let id: UUID
    let planId: UUID
    let week: Int
    let day: String
    let type: String
    let distance: Double
    let duration: Int?
    let pace: Int?
    let completed: Bool
    let scheduledDate: String
    let notes: String?
    let workoutStructure: String?
    let intensity: String?
    let trainingPhase: String?

    enum CodingKeys: String, CodingKey {
        case id
        case planId = "plan_id"
        case week
        case day
        case type
        case distance
        case duration
        case pace
        case completed
        case scheduledDate = "scheduled_date"
        case notes
        case workoutStructure = "workout_structure"
        case intensity
        case trainingPhase = "training_phase"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        planId = try c.decode(UUID.self, forKey: .planId)
        week = (try? c.decode(Int.self, forKey: .week)) ?? 0
        day = (try? c.decode(String.self, forKey: .day)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? "easy"
        distance = (try? c.decode(Double.self, forKey: .distance)) ?? 0
        duration = try? c.decodeIfPresent(Int.self, forKey: .duration)
        pace = try? c.decodeIfPresent(Int.self, forKey: .pace)
        completed = (try? c.decode(Bool.self, forKey: .completed)) ?? false
        scheduledDate = (try? c.decode(String.self, forKey: .scheduledDate)) ?? ""
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        workoutStructure = try? c.decodeIfPresent(String.self, forKey: .workoutStructure)
        intensity = try? c.decodeIfPresent(String.self, forKey: .intensity)
        trainingPhase = try? c.decodeIfPresent(String.self, forKey: .trainingPhase)
    }
}

struct DBConversation: Codable, Sendable {
    let id: UUID
    let profileId: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case profileId = "profile_id"
    }
}

struct DBMessage: Codable, Sendable {
    let id: UUID
    let conversationId: UUID
    let role: String
    let content: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role
        case content
        case createdAt = "created_at"
    }
}

struct DBUserStreak: Codable, Sendable {
    let authUserId: UUID?
    let currentStreak: Int
    let bestStreak: Int
    let lastActiveDay: String?

    enum CodingKeys: String, CodingKey {
        case authUserId = "auth_user_id"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case lastActiveDay = "last_active_day"
    }
}

struct DBGarminDailyMetrics: Codable, Sendable {
    let id: Int
    let authUserId: UUID?
    let date: String
    let steps: Int?
    let sleepScore: Double?
    let sleepDurationS: Int?
    let hrv: Double?
    let bodyBattery: Int?
    let bodyBatteryBalance: Double?
    let stress: Double?
    let trainingReadiness: Int?
    let restingHR: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case date
        case steps
        case sleepScore = "sleep_score"
        case sleepDurationS = "sleep_duration_s"
        case hrv
        case bodyBattery = "body_battery"
        case bodyBatteryBalance = "body_battery_balance"
        case stress
        case trainingReadiness = "training_readiness"
        case restingHR = "resting_hr"
    }
}

struct DBGarminConnection: Codable, Sendable {
    let id: Int
    let authUserId: UUID?
    let status: String?
    let lastSyncAt: String?
    let lastSuccessfulSyncAt: String?
    let connectedAt: String?
    let scopes: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case status
        case lastSyncAt = "last_sync_at"
        case lastSuccessfulSyncAt = "last_successful_sync_at"
        case connectedAt = "connected_at"
        case scopes
    }
}

struct DBGarminActivity: Codable, Hashable, Sendable {
    let id: Int
    let authUserId: UUID?
    let activityId: String
    let startTime: String?
    let sport: String?
    let durationS: Double?
    let distanceM: Double?
    let avgHr: Int?
    let avgPaceSPerKm: Double?
    let elevationGainM: Double?
    let calories: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case activityId = "activity_id"
        case startTime = "start_time"
        case sport
        case durationS = "duration_s"
        case distanceM = "distance_m"
        case avgHr = "avg_hr"
        case avgPaceSPerKm = "avg_pace_s_per_km"
        case elevationGainM = "elevation_gain_m"
        case calories
    }
}

struct DBAIInsight: Codable, Sendable {
    let id: UUID?
    let authUserId: UUID?
    let activityId: String?
    let type: String?
    let content: String?
    let summary: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case activityId = "activity_id"
        case type
        case content
        case summary
        case createdAt = "created_at"
    }
}

struct DBChallenge: Codable, Sendable {
    let id: UUID
    let slug: String
    let title: String
    let description: String?
    let durationDays: Int

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description
        case durationDays = "duration_days"
    }
}

struct DBChallengeEnrollment: Codable, Sendable {
    let challengeId: UUID
    let authUserId: UUID?
    let startedAt: String?
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case authUserId = "auth_user_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

// MARK: - Enum mappers

extension OnboardingProfile {
    var supabaseGoal: String {
        let lower = goal.lowercased()
        if lower.contains("habit") || lower.contains("consistency") { return "habit" }
        if lower.contains("speed") || lower.contains("5k") || lower.contains("interval") { return "speed" }
        return "distance"
    }

    var supabaseExperience: String {
        let lower = experience.lowercased()
        if lower.contains("beginner") || lower.contains("base") || lower.contains("new") { return "beginner" }
        if lower.contains("advanced") || lower.contains("competitive") { return "advanced" }
        return "intermediate"
    }

    var supabaseCoachingStyle: String {
        switch coachingTone.lowercased() {
        case let s where s.contains("motivat") || s.contains("encourag"): return "encouraging"
        case let s where s.contains("techni") || s.contains("analytic"): return "analytical"
        case let s where s.contains("strict") || s.contains("challeng"): return "challenging"
        default: return "supportive"
        }
    }
}

extension TrainingGoalRequest {
    var supabaseGoal: String {
        let lower = goal.lowercased()
        if lower.contains("habit") || lower.contains("consistency") || lower.contains("just") { return "habit" }
        if lower.contains("speed") || lower.contains("5k") || lower.contains("pr") { return "speed" }
        return "distance"
    }

    var supabaseExperience: String {
        let lower = experience.lowercased()
        if lower.contains("beginner") || lower.contains("base") || lower.contains("new") { return "beginner" }
        if lower.contains("advanced") || lower.contains("competitive") { return "advanced" }
        return "intermediate"
    }

    var supabaseCoachingStyle: String {
        switch coachingTone.lowercased() {
        case let s where s.contains("motivat") || s.contains("encourag"): return "encouraging"
        case let s where s.contains("techni") || s.contains("analytic"): return "analytical"
        case let s where s.contains("strict") || s.contains("challeng"): return "challenging"
        default: return "supportive"
        }
    }
}

extension WorkoutKind {
    var supabaseType: String {
        switch self {
        case .easy: return "easy"
        case .intervals: return "intervals"
        case .tempo: return "tempo"
        case .hills: return "hill"
        case .strength: return "rest"
        case .recovery: return "recovery"
        case .long: return "long"
        case .race: return "time-trial"
        case .parkrun: return "easy"
        }
    }
}

// MARK: - Helpers

func userIdInt64(from uuid: UUID) -> Int64 {
    let (a, b, c, d, e, f, g, h, _, _, _, _, _, _, _, _) = uuid.uuid
    var val = Int64(a) << 56
    val |= Int64(b) << 48
    val |= Int64(c) << 40
    val |= Int64(d) << 32
    val |= Int64(e) << 24
    val |= Int64(f) << 16
    val |= Int64(g) << 8
    val |= Int64(h)
    return val < 0 ? -val : val
}
