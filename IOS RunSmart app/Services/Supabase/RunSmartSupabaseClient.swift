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
    let id: Int              // bigint auto-increment in DB
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
        id = try c.decode(Int.self, forKey: .id)
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

struct DBPlan: Codable, Sendable {
    let id: UUID
    let profileId: UUID
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
    let sleepScore: Int?
    let sleepDurationS: Int?
    let hrv: Double?
    let bodyBattery: Int?
    let bodyBatteryBalance: Double?

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
    }
}

struct DBGarminConnection: Codable, Sendable {
    let id: Int
    let authUserId: UUID?
    let status: String?
    let lastSyncAt: String?
    let connectedAt: String?
    let scopes: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case status
        case lastSyncAt = "last_sync_at"
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
