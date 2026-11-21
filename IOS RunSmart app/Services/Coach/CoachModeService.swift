import Foundation

nonisolated enum RunSmartFeatures {
    /// Coach Mode is on in every Release build (TestFlight and the App Store).
    /// Debug builds turn it on with the `-enable-coach-mode` launch argument.
    /// Only accounts with a `coach_profiles` row get the Coach tab; athletes see "Join a coach".
    static let coachModeEnabled: Bool = {
#if DEBUG
        coachModeEnabled(processArguments: ProcessInfo.processInfo.arguments, isDebugBuild: true)
#else
        coachModeEnabled(processArguments: ProcessInfo.processInfo.arguments, isDebugBuild: false)
#endif
    }()

    static func coachModeEnabled(processArguments: [String], isDebugBuild: Bool) -> Bool {
        if isDebugBuild { return processArguments.contains("-enable-coach-mode") }
        return true
    }

    // MARK: Coach Experience v2 gate (C7.0, decision N1 = B)

    /// Debug builds turn v2 on with this launch argument.
    static let coachV2LaunchArgument = "-enable-coach-v2"

    /// Which build this is, as the server stores it in `client_capabilities.channel`.
    static let coachV2Channel: CoachV2Channel = {
#if DEBUG
        coachV2Channel(isDebugBuild: true, receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
#else
        coachV2Channel(isDebugBuild: false, receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent)
#endif
    }()

    /// TestFlight installs carry a "sandboxReceipt" (the signal `Analytics.resolveInternalTesterSignals`
    /// uses); App Store installs carry "receipt".
    static func coachV2Channel(isDebugBuild: Bool, receiptName: String?) -> CoachV2Channel {
        if isDebugBuild { return .debug }
        return receiptName == "sandboxReceipt" ? .testflight : .appStore
    }

    /// The build half of the gate: Debug with `-enable-coach-v2`, or any TestFlight build.
    static func coachV2BuildFlag(channel: CoachV2Channel, processArguments: [String]) -> Bool {
        switch channel {
        case .debug: processArguments.contains(coachV2LaunchArgument)
        case .testflight: true
        case .appStore: false
        }
    }

    /// v2 is on when the server kill switch (`runtime_flags.coach_v2`) is on AND either the build
    /// flag is on, or this is an App Store build and `coach_v2_pilot_access()` said yes.
    /// A Debug build without the argument stays off even with pilot access.
    static func coachV2Enabled(
        channel: CoachV2Channel,
        processArguments: [String],
        pilotAccess: Bool,
        v2FlagOn: Bool
    ) -> Bool {
        guard v2FlagOn else { return false }
        return coachV2WouldBeEnabled(channel: channel, processArguments: processArguments, pilotAccess: pilotAccess)
    }

    /// The same rule without the kill switch. True with the switch off means "paused", not "off".
    static func coachV2WouldBeEnabled(channel: CoachV2Channel, processArguments: [String], pilotAccess: Bool) -> Bool {
        if coachV2BuildFlag(channel: channel, processArguments: processArguments) { return true }
        return channel == .appStore && pilotAccess
    }

    /// Live answer from the 15-minute flag cache. Off until the flags were read once,
    /// so a fresh install offline, or a server without the v2 migration, stays on 1.2.6 behavior.
    static var coachV2Enabled: Bool {
        let snapshot = CoachV2FlagCache.standard.load()
        return coachV2Enabled(
            channel: coachV2Channel,
            processArguments: ProcessInfo.processInfo.arguments,
            pilotAccess: snapshot?.pilotAccess ?? false,
            v2FlagOn: snapshot?.v2FlagOn ?? false
        )
    }

    /// Invite URLs are reserved for Story 1.4 and must never enter authentication handling.
    static func isCoachInviteURL(_ url: URL) -> Bool {
        url.host?.caseInsensitiveCompare("join") == .orderedSame
            || url.pathComponents.dropFirst().first?.caseInsensitiveCompare("join") == .orderedSame
    }
}
import Combine
import Supabase



// "Coach" in this file means a HUMAN coach (Coach Mode). It is unrelated to the AI
// coach: `coach_message`, `profiles.coaching_style`, `CoachFlowView`.

/// Reads the coach role and invite code from Supabase.
nonisolated protocol CoachModeRepository: Sendable {
    /// True when the signed-in user has a `coach_profiles` row (RLS limits reads to their own row).
    func hasCoachProfile(userID: UUID) async throws -> Bool
    /// The coach's single active invite code. Created on first call; raises for non-coaches.
    func myInviteCode() async throws -> String
}

nonisolated struct SupabaseCoachModeRepository: CoachModeRepository {
    private struct CoachProfileRow: Decodable {
        let userId: UUID

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
        }
    }

    func hasCoachProfile(userID: UUID) async throws -> Bool {
        let rows: [CoachProfileRow] = try await SupabaseManager.client
            .from("coach_profiles")
            .select("user_id")
            .eq("user_id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    func myInviteCode() async throws -> String {
        try await SupabaseManager.client
            .rpc("get_or_create_my_invite")
            .execute()
            .value
    }
}

/// Decides whether the Coach tab exists. Non-coaches, guests and signed-out users never get it.
@MainActor
final class CoachModeStore: ObservableObject {
    @Published private(set) var isCoach = false

    private let repository: any CoachModeRepository
    private var currentUserID: UUID?

    init(repository: any CoachModeRepository = SupabaseCoachModeRepository()) {
        self.repository = repository
    }

    /// Pass the signed-in user's id, or nil when signed out / guest.
    /// A failed check keeps the last answer for the same user (a coach on a flaky
    /// connection keeps the tab) and never grants the tab to anyone else.
    func refresh(userID: UUID?) async {
        if userID != currentUserID {
            currentUserID = userID
            isCoach = false
        }
        guard let userID else { return }

        do {
            let hasProfile = try await repository.hasCoachProfile(userID: userID)
            // The account may have changed while the request was in flight.
            guard currentUserID == userID else { return }
            isCoach = hasProfile
        } catch {
            if !(error is CancellationError) {
                print("[CoachModeStore] coach role check failed:", error)
            }
        }
    }
}

/// What the coach shares: the code, a link, and the share-sheet text.
struct CoachInvite: Equatable {
    /// Uppercased, trimmed. Codes are case-insensitive, so the canonical form is upper case.
    let code: String

    init(code: String) {
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// `{INVITE_BASE_URL}/join/{CODE}`
    func link(baseURL: URL = ExternalURLs.inviteBase) -> URL {
        baseURL.appendingPathComponent("join").appendingPathComponent(code)
    }

    func shareMessage(baseURL: URL = ExternalURLs.inviteBase) -> String {
        "Join my group in RunSmart: \(link(baseURL: baseURL).absoluteString)  Code: \(code)"
    }
}

@MainActor
final class CoachInviteViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(CoachInvite)
        case failed
    }

    @Published private(set) var state: State = .loading

    private let repository: any CoachModeRepository

    init(repository: any CoachModeRepository = SupabaseCoachModeRepository()) {
        self.repository = repository
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(CoachInvite(code: try await repository.myInviteCode()))
        } catch {
            if error is CancellationError { return }
            print("[CoachInviteViewModel] invite load failed:", error)
            state = .failed
        }
    }
}
