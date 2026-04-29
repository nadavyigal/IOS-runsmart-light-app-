import Foundation
import Combine
import Supabase
import AuthenticationServices
import CryptoKit

// MARK: - Session

@MainActor
final class SupabaseSession: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var profile: DBProfile?
    @Published var displayName: String = ""
    @Published var isLoading = true
    @Published var lastAuthError: String?

    let supabase = SupabaseManager.client

    private(set) var onboardingProfile: OnboardingProfile = .empty

    init() {
        Task { await initialize() }
    }

    var currentUserID: UUID? { supabase.auth.currentUser?.id }
    var currentEmail: String? { supabase.auth.currentUser?.email }
    var currentMemberSince: Date? { supabase.auth.currentUser?.createdAt }

    // plans/conversations use auth.uid() as profile_id (uuid), not profiles.id (bigint)
    var profileID: UUID? { currentUserID }

    func initialize() async {
        // Resolve the initial session before entering the infinite auth-change stream
        if let session = try? await supabase.auth.session, !session.isExpired {
            isAuthenticated = true
            await loadProfile(userID: session.user.id)
        }
        isLoading = false  // spinner off before stream — defer never fires on an infinite loop

        for await (event, session) in supabase.auth.authStateChanges {
            switch event {
            case .signedIn:
                if let s = session, !s.isExpired {
                    await MainActor.run {
                        isAuthenticated = true
                        lastAuthError = nil
                    }
                    await loadProfile(userID: s.user.id)
                } else {
                    clearSessionState()
                }
            case .signedOut:
                clearSessionState()
            default:
                break
            }
        }
    }

    func loadProfile(userID: UUID) async {
        do {
            let rows: [DBProfile] = try await supabase
                .from("profiles")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            print("[SupabaseSession] loadProfile got \(rows.count) row(s) for uid=\(userID)")
            if let p = rows.first {
                profile = p
                hasCompletedOnboarding = p.onboardingComplete
                displayName = p.name ?? ""
                lastAuthError = nil
                onboardingProfile = OnboardingProfile(
                    displayName: p.name ?? "",
                    goal: p.goal.isEmpty ? "" : p.goal,
                    experience: p.experience.isEmpty ? "" : p.experience,
                    weeklyRunDays: p.daysPerWeek,
                    preferredDays: p.preferredTimes,
                    units: "Metric",
                    coachingTone: p.coachingStyle ?? "Motivating",
                    notificationsEnabled: false
                )
            } else {
                profile = nil
                hasCompletedOnboarding = false
                displayName = ""
                lastAuthError = nil
            }
        } catch {
            let message = "Could not load your RunSmart profile. Check Supabase profiles RLS and auth_user_id linkage."
            lastAuthError = message
            print("[SupabaseSession] loadProfile error:", error)
        }
    }

    func completeOnboarding(_ onboarding: OnboardingProfile) async {
        guard let userID = currentUserID else {
            print("[SupabaseSession] completeOnboarding: no currentUserID")
            return
        }
        onboardingProfile = onboarding
        // email comes from the Apple JWT the auth server decoded — always present after sign-in
        let email = supabase.auth.currentUser?.email ?? ""
        let insert = DBProfileInsert(
            authUserId: userID.uuidString,
            email: email,
            name: onboarding.displayName,
            goal: onboarding.supabaseGoal,
            experience: onboarding.supabaseExperience,
            preferredTimes: onboarding.preferredDays,
            daysPerWeek: onboarding.weeklyRunDays,
            coachingStyle: onboarding.supabaseCoachingStyle,
            onboardingComplete: true
        )
        print("[SupabaseSession] completeOnboarding upsert uid=\(userID) email=\(email)")
        do {
            let rows: [DBProfile] = try await supabase
                .from("profiles")
                .upsert(insert, onConflict: "auth_user_id")
                .select()
                .execute()
                .value
            print("[SupabaseSession] completeOnboarding upserted \(rows.count) row(s)")
            if let p = rows.first {
                profile = p
                hasCompletedOnboarding = true
                displayName = p.name ?? onboarding.displayName
            }
        } catch {
            lastAuthError = "Could not save onboarding. Check the profiles auth_user_id unique constraint and RLS policies."
            print("[SupabaseSession] completeOnboarding error:", error)
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    private func clearSessionState() {
        isAuthenticated = false
        hasCompletedOnboarding = false
        profile = nil
        displayName = ""
        lastAuthError = nil
    }
}
