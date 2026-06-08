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
    private let notificationPreferenceKey = "runsmart.notifications.enabled"
    private let planAdjustmentConfirmationsKey = "runsmart.notifications.planAdjustmentConfirmations"
    private var appleDisplayNameSeed: String?
    private var appleEmailSeed: String?

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
                    age: p.age,
                    averageWeeklyDistanceKm: p.averageWeeklyDistanceKm,
                    trainingDataSource: p.trainingDataSource.flatMap(TrainingDataSource.init(rawValue:)),
                    trainingDataUpdatedAt: p.trainingDataUpdatedAt.flatMap(Self.parseProfileDate),
                    weeklyRunDays: p.daysPerWeek,
                    preferredDays: p.preferredTimes,
                    units: "Metric",
                    coachingTone: p.coachingStyle ?? "Motivating",
                    notificationsEnabled: UserDefaults.standard.object(forKey: notificationPreferenceKey) as? Bool ?? false,
                    planAdjustmentConfirmationsEnabled: UserDefaults.standard.object(forKey: planAdjustmentConfirmationsKey) as? Bool ?? true
                )
            } else {
                profile = nil
                hasCompletedOnboarding = false
                displayName = appleDisplayNameSeed ?? ""
                onboardingProfile.displayName = appleDisplayNameSeed ?? ""
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
        var completedOnboarding = onboarding
        if completedOnboarding.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completedOnboarding.displayName = appleDisplayNameSeed ?? "RunSmart Runner"
        }
        onboardingProfile = completedOnboarding
        UserDefaults.standard.set(onboarding.notificationsEnabled, forKey: notificationPreferenceKey)
        UserDefaults.standard.set(onboarding.planAdjustmentConfirmationsEnabled, forKey: planAdjustmentConfirmationsKey)
        // email comes from the Apple JWT the auth server decoded — always present after sign-in
        let email = supabase.auth.currentUser?.email ?? appleEmailSeed ?? ""
        let insert = DBProfileInsert(
            authUserId: userID.uuidString,
            email: email,
            name: completedOnboarding.displayName,
            goal: completedOnboarding.supabaseGoal,
            experience: completedOnboarding.supabaseExperience,
            age: completedOnboarding.age,
            averageWeeklyDistanceKm: completedOnboarding.averageWeeklyDistanceKm,
            trainingDataSource: completedOnboarding.trainingDataSource?.rawValue,
            trainingDataUpdatedAt: completedOnboarding.trainingDataUpdatedAt.map(Self.profileDateFormatter.string(from:)),
            preferredTimes: completedOnboarding.preferredDays,
            daysPerWeek: completedOnboarding.weeklyRunDays,
            coachingStyle: completedOnboarding.supabaseCoachingStyle,
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
                displayName = p.name ?? completedOnboarding.displayName
            }
        } catch {
            print("[SupabaseSession] completeOnboarding rich upsert error:", error)
            do {
                let rows: [DBProfile] = try await supabase
                    .from("profiles")
                    .upsert(DBProfileInsertLegacy(
                        authUserId: userID.uuidString,
                        email: email,
                        name: completedOnboarding.displayName,
                        goal: completedOnboarding.supabaseGoal,
                        experience: completedOnboarding.supabaseExperience,
                        preferredTimes: completedOnboarding.preferredDays,
                        daysPerWeek: completedOnboarding.weeklyRunDays,
                        coachingStyle: completedOnboarding.supabaseCoachingStyle,
                        onboardingComplete: true
                    ), onConflict: "auth_user_id")
                    .select()
                    .execute()
                    .value
                if let p = rows.first {
                    profile = p
                    hasCompletedOnboarding = true
                    displayName = p.name ?? completedOnboarding.displayName
                    lastAuthError = nil
                }
            } catch {
                lastAuthError = "Could not save onboarding. Check the profiles auth_user_id unique constraint and RLS policies."
                print("[SupabaseSession] completeOnboarding legacy upsert error:", error)
            }
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    func rememberAppleProfile(displayName: String?, email: String?) {
        appleDisplayNameSeed = Self.trimmedNonEmpty(displayName)
        appleEmailSeed = Self.trimmedNonEmpty(email)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        onboardingProfile.notificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: notificationPreferenceKey)
        objectWillChange.send()
        if !enabled {
            PushService.shared.cancelAllRunSmartReminders()
        }
    }

    func setPlanAdjustmentConfirmationsEnabled(_ enabled: Bool) {
        onboardingProfile.planAdjustmentConfirmationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: planAdjustmentConfirmationsKey)
        objectWillChange.send()
        if !enabled {
            PushService.shared.cancelPlanAdjustmentConfirmation()
        }
    }

    private func clearSessionState() {
        isAuthenticated = false
        hasCompletedOnboarding = false
        profile = nil
        displayName = ""
        onboardingProfile = .empty
        appleDisplayNameSeed = nil
        appleEmailSeed = nil
        lastAuthError = nil
    }

    private static let profileDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseProfileDate(_ value: String) -> Date? {
        if let date = profileDateFormatter.date(from: value) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
