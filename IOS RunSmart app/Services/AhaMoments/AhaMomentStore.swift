import Foundation
import Supabase

struct DBAhaMomentRow: Decodable, Sendable {
    let id: UUID?

    enum CodingKeys: String, CodingKey {
        case id
    }
}

struct DBAhaMomentInsert: Encodable, Sendable {
    let userId: UUID
    let momentId: String
    let context: String?
    let variant: String?
    var ctaClicked: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case momentId = "moment_id"
        case context
        case variant
        case ctaClicked = "cta_clicked"
    }
}

struct DBAhaMomentFiredAtRow: Decodable, Sendable {
    let firedAt: String?

    enum CodingKeys: String, CodingKey {
        case firedAt = "fired_at"
    }
}

struct DBAhaProfileInsightUpdate: Encodable, Sendable {
    let runnerIdentity: String
    let goalTimelineWeeks: Int
    let projectedGoalDate: String

    enum CodingKeys: String, CodingKey {
        case runnerIdentity = "runner_identity"
        case goalTimelineWeeks = "goal_timeline_weeks"
        case projectedGoalDate = "projected_goal_date"
    }
}

actor AhaMomentStore {
    static let shared = AhaMomentStore()

    private let supabase = SupabaseManager.client
    private static let profileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Clears onboarding-only moments so a deleted/re-onboarded account can see them again.
    func resetOnboardingMoments() async {
        guard let userID = supabase.auth.currentUser?.id else { return }
        do {
            try await supabase
                .from("user_aha_moments")
                .delete()
                .eq("user_id", value: userID.uuidString)
                .in("moment_id", values: ["knows_me", "future_vision"])
                .execute()
        } catch {
            print("[AhaMomentStore] resetOnboardingMoments error (ignored):", error)
        }
    }

    func hasFired(momentId: String, context: String? = nil) async -> Bool {
        guard let userID = supabase.auth.currentUser?.id else { return false }
        do {
            var query = supabase
                .from("user_aha_moments")
                .select("id")
                .eq("user_id", value: userID.uuidString)
                .eq("moment_id", value: momentId)

            if let context, !context.isEmpty {
                query = query.eq("context", value: context)
            } else {
                query = query.is("context", value: nil)
            }

            let rows: [DBAhaMomentRow] = try await query.limit(1).execute().value
            return !rows.isEmpty
        } catch {
            print("[AhaMomentStore] hasFired error:", error)
            return false
        }
    }

    func record(momentId: String, context: String? = nil, variant: String = "C", ctaClicked: Bool? = nil) async {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let insert = DBAhaMomentInsert(
            userId: userID,
            momentId: momentId,
            context: context,
            variant: variant,
            ctaClicked: ctaClicked
        )
        do {
            try await supabase
                .from("user_aha_moments")
                .insert(insert)
                .execute()
        } catch {
            // Unique violations and transient network errors should not block UX.
            print("[AhaMomentStore] record error (ignored):", error)
        }
    }

    func updateDismissed(momentId: String, context: String? = nil) async {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let payload: [String: String] = [
            "dismissed_at": ISO8601DateFormatter().string(from: Date())
        ]
        do {
            if let context, !context.isEmpty {
                try await supabase
                    .from("user_aha_moments")
                    .update(payload)
                    .eq("user_id", value: userID.uuidString)
                    .eq("moment_id", value: momentId)
                    .eq("context", value: context)
                    .execute()
            } else {
                try await supabase
                    .from("user_aha_moments")
                    .update(payload)
                    .eq("user_id", value: userID.uuidString)
                    .eq("moment_id", value: momentId)
                    .is("context", value: nil)
                    .execute()
            }
        } catch {
            print("[AhaMomentStore] updateDismissed error (ignored):", error)
        }
    }

    func persistInsightProfile(
        identity: RunnerIdentityKind,
        timeline: GoalTimelineProjection
    ) async {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let update = DBAhaProfileInsightUpdate(
            runnerIdentity: identity.rawValue,
            goalTimelineWeeks: timeline.weeks,
            projectedGoalDate: Self.profileDateFormatter.string(from: timeline.projectedDate)
        )
        do {
            try await supabase
                .from("profiles")
                .update(update)
                .eq("auth_user_id", value: userID.uuidString)
                .execute()
        } catch {
            print("[AhaMomentStore] persistInsightProfile error (ignored):", error)
        }
    }

    func latestNoticedFiredAt() async -> Date? {
        guard let userID = supabase.auth.currentUser?.id else { return nil }
        do {
            let rows: [DBAhaMomentFiredAtRow] = try await supabase
                .from("user_aha_moments")
                .select("fired_at")
                .eq("user_id", value: userID.uuidString)
                .eq("moment_id", value: "noticed")
                .order("fired_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let raw = rows.first?.firedAt else { return nil }
            return ISO8601DateFormatter().date(from: raw) ?? Self.profileDateFormatter.date(from: raw)
        } catch {
            print("[AhaMomentStore] latestNoticedFiredAt error:", error)
            return nil
        }
    }

    func isNoticedOnCooldown(minimumGapDays: Int = 3) async -> Bool {
        guard let last = await latestNoticedFiredAt() else { return false }
        let elapsed = Date().timeIntervalSince(last) / 86_400
        return elapsed < Double(minimumGapDays)
    }


    private static func likePatternPrefix(_ prefix: String) -> String {
        prefix
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }

    func hasFiredAnyContext(momentId: String, contextPrefix: String) async -> Bool {
        guard let userID = supabase.auth.currentUser?.id else { return false }
        do {
            let rows: [DBAhaMomentRow] = try await supabase
                .from("user_aha_moments")
                .select("id")
                .eq("user_id", value: userID.uuidString)
                .eq("moment_id", value: momentId)
                .like("context", pattern: Self.likePatternPrefix(contextPrefix))
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            print("[AhaMomentStore] hasFiredAnyContext error:", error)
            return false
        }
    }
}
