import Foundation
import Supabase

// MARK: - View model for a challenge with enrollment state

struct ChallengeItem: Identifiable {
    let id: UUID
    let slug: String
    let title: String
    let description: String
    let durationDays: Int
    var isEnrolled: Bool
    var startedAt: Date?
}

// MARK: - Repository

final class ChallengeRepository {
    private let supabase = SupabaseManager.client

    func availableChallenges(authUserID: UUID) async -> [ChallengeItem] {
        do {
            async let challengesTask: [DBChallenge] = supabase
                .from("challenges")
                .select()
                .execute()
                .value

            async let enrollmentsTask: [DBChallengeEnrollment] = supabase
                .from("challenge_enrollments")
                .select("challenge_id, auth_user_id, started_at")
                .eq("auth_user_id", value: authUserID.uuidString)
                .execute()
                .value

            let (challenges, enrollments) = try await (challengesTask, enrollmentsTask)

            let enrolledIDs = Set(enrollments.map { $0.challengeId })

            return challenges.map { c in
                let enrollment = enrollments.first { $0.challengeId == c.id }
                let startDate: Date? = enrollment?.startedAt.flatMap {
                    ISO8601DateFormatter.shortDate.date(from: $0)
                }
                return ChallengeItem(
                    id: c.id,
                    slug: c.slug,
                    title: c.title,
                    description: c.description ?? "",
                    durationDays: c.durationDays,
                    isEnrolled: enrolledIDs.contains(c.id),
                    startedAt: startDate
                )
            }
        } catch {
            if !(error is CancellationError) {
                print("[ChallengeRepo] availableChallenges error:", error)
            }
            return []
        }
    }

    func activeChallenge(authUserID: UUID) async -> ChallengeSummary {
        guard let challenge = await availableChallenges(authUserID: authUserID)
            .first(where: \.isEnrolled) else {
            return .loading
        }

        let elapsedDays: Int
        if let startedAt = challenge.startedAt {
            let days = Calendar.current.dateComponents([.day], from: startedAt, to: Date()).day ?? 0
            elapsedDays = max(1, days + 1)
        } else {
            elapsedDays = 1
        }
        let boundedDay = min(challenge.durationDays, elapsedDays)

        return ChallengeSummary(
            id: challenge.id.uuidString,
            title: challenge.title,
            detail: challenge.description.isEmpty ? "\(challenge.durationDays)-day challenge" : challenge.description,
            progress: min(1, Double(boundedDay) / Double(max(1, challenge.durationDays))),
            dayLabel: "Day \(boundedDay)/\(challenge.durationDays)",
            isActive: true
        )
    }

    func enroll(challengeID: UUID, authUserID: UUID) async throws {
        let userID = userIdInt64(from: authUserID)
        let today = ISO8601DateFormatter.shortDate.string(from: Date())

        struct EnrollInsert: Encodable {
            let user_id: Int64
            let auth_user_id: String
            let challenge_id: String
            let started_at: String
            let updated_at: String
            let progress: EnrollProgress
        }
        struct EnrollProgress: Encodable {
            let completedDays: [String]
            let completionSource: [String: String]
        }

        let insert = EnrollInsert(
            user_id: userID,
            auth_user_id: authUserID.uuidString,
            challenge_id: challengeID.uuidString,
            started_at: today,
            updated_at: Date().ISO8601Format(),
            progress: EnrollProgress(completedDays: [], completionSource: [:])
        )

        try await supabase
            .from("challenge_enrollments")
            .upsert(insert, onConflict: "user_id,challenge_id")
            .execute()
    }
}
