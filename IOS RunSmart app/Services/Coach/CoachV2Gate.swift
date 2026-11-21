import Combine
import Foundation
import Supabase

// Coach Experience v2 gate (story C7.0, with the C7.12 kill switch and the N1 = B
// pilot allowlist). "Coach" means a HUMAN coach (Coach Mode), not the AI coach.
//
// Server side: supabase/migrations/20261121100000_coach_v2_gate.sql.
// The server is the real gate: every later v2 RPC checks link_is_v2. This file only
// decides what the app shows, and tells the server which clients are v2-capable.

/// The build that sent a capability report. Raw values match `client_capabilities.channel`.
nonisolated enum CoachV2Channel: String, Codable, Sendable {
    case debug
    case testflight
    case appStore = "app_store"
}

/// What the coach screens render.
nonisolated enum CoachV2State: Equatable, Sendable {
    /// 1.2.6 behavior. No v2 string, sheet, prompt or RPC.
    case off
    /// This client would have v2, but the server kill switch is on. 1.2.6 behavior plus one line.
    case paused
    case on
}

enum CoachV2RPC {
    static let runtimeFlags = "get_runtime_flags"
    static let pilotAccess = "coach_v2_pilot_access"
    static let reportCapabilities = "report_client_capabilities"
    static let rosterStatus = "coach_v2_roster_status"
}

// MARK: Flag cache

/// The last flags this device read for one user. Kept in UserDefaults so a relaunch
/// renders the same state before the network answers.
nonisolated struct CoachV2FlagSnapshot: Codable, Equatable, Sendable {
    var userID: UUID
    var v2FlagOn: Bool
    var pilotAccess: Bool
    var fetchedAt: Date
}

nonisolated struct CoachV2FlagCache: @unchecked Sendable {
    /// v1.3 §3.7: the client reads the flags on launch and foreground, at most every 15 minutes.
    static let maxAge: TimeInterval = 15 * 60
    static let standard = CoachV2FlagCache(defaults: .standard)

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "coachV2.flagSnapshot.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> CoachV2FlagSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CoachV2FlagSnapshot.self, from: data)
    }

    func save(_ snapshot: CoachV2FlagSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    static func isFresh(_ snapshot: CoachV2FlagSnapshot, for userID: UUID, now: Date) -> Bool {
        snapshot.userID == userID
            && now.timeIntervalSince(snapshot.fetchedAt) < maxAge
            && now >= snapshot.fetchedAt
    }
}

// MARK: Repository

nonisolated struct CoachV2CapabilityReport: Encodable, Equatable, Sendable {
    let coachV2: Bool
    let version: String?
    let build: Int?
    let channel: CoachV2Channel
    var platform = "ios"

    enum CodingKeys: String, CodingKey {
        case coachV2 = "p_coach_v2"
        case version = "p_version"
        case build = "p_build"
        case channel = "p_channel"
        case platform = "p_platform"
    }
}

nonisolated protocol CoachV2GateRepository: Sendable {
    /// `get_runtime_flags()`: only the allow-listed keys come back.
    func runtimeFlags() async throws -> [String: Bool]
    /// `coach_v2_pilot_access()`: the caller is a listed coach, or linked to one.
    func pilotAccess() async throws -> Bool
    func reportCapabilities(_ report: CoachV2CapabilityReport) async throws
    /// `coach_v2_roster_status()`: athlete id to athlete_is_v2, for the caller's active athletes.
    func rosterStatus() async throws -> [UUID: Bool]
}

nonisolated struct SupabaseCoachV2GateRepository: CoachV2GateRepository {
    private struct FlagRow: Decodable {
        let key: String
        let enabled: Bool
    }

    private struct RosterRow: Decodable {
        let athleteID: UUID
        let athleteIsV2: Bool

        enum CodingKeys: String, CodingKey {
            case athleteID = "athlete_id"
            case athleteIsV2 = "athlete_is_v2"
        }
    }

    func runtimeFlags() async throws -> [String: Bool] {
        let rows: [FlagRow] = try await SupabaseManager.client
            .rpc(CoachV2RPC.runtimeFlags)
            .execute()
            .value
        return Dictionary(rows.map { ($0.key, $0.enabled) }, uniquingKeysWith: { first, _ in first })
    }

    func pilotAccess() async throws -> Bool {
        try await SupabaseManager.client
            .rpc(CoachV2RPC.pilotAccess)
            .execute()
            .value
    }

    func reportCapabilities(_ report: CoachV2CapabilityReport) async throws {
        try await SupabaseManager.client
            .rpc(CoachV2RPC.reportCapabilities, params: report)
            .execute()
    }

    func rosterStatus() async throws -> [UUID: Bool] {
        let rows: [RosterRow] = try await SupabaseManager.client
            .rpc(CoachV2RPC.rosterStatus)
            .execute()
            .value
        return Dictionary(rows.map { ($0.athleteID, $0.athleteIsV2) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: Store

/// Owns `coachV2Enabled` for the signed-in user. Call `sync(userID:)` on sign-in, sign-out
/// and every foreground. It reads the flags when the cache is older than 15 minutes, then
/// reports this client's capabilities once. Offline, both fail quietly and retry on the
/// next foreground.
@MainActor
final class CoachV2Gate: ObservableObject {
    @Published private(set) var state: CoachV2State = .off

    var isEnabled: Bool { state == .on }

    /// A report the server already has is not sent again for this long.
    static let reportReuseInterval: TimeInterval = 24 * 60 * 60

    private let repository: any CoachV2GateRepository
    private let cache: CoachV2FlagCache
    private let channel: CoachV2Channel
    private let processArguments: [String]
    private let appVersion: String?
    private let appBuild: Int?
    private let now: () -> Date

    private var userID: UUID?
    private var syncing = false
    private var needsAnotherPass = false
    private var lastReport: (userID: UUID, report: CoachV2CapabilityReport, at: Date)?

    init(
        repository: any CoachV2GateRepository = SupabaseCoachV2GateRepository(),
        cache: CoachV2FlagCache = .standard,
        channel: CoachV2Channel = RunSmartFeatures.coachV2Channel,
        processArguments: [String] = ProcessInfo.processInfo.arguments,
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        appBuild: Int? = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.cache = cache
        self.channel = channel
        self.processArguments = processArguments
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.now = now
    }

    nonisolated deinit {}

    /// Pass the signed-in user's id, or nil when signed out or a guest.
    func sync(userID newUserID: UUID?) async {
        if newUserID != userID {
            userID = newUserID
            // Pilot access belongs to one account. Never carry it to the next one.
            if let snapshot = cache.load(), snapshot.userID != newUserID { cache.clear() }
            publish()
        }
        guard newUserID != nil else {
            cache.clear()
            publish()
            return
        }
        // One sync at a time. A second trigger in the same foreground (launch fires both
        // the sign-in task and the scene phase change) sends nothing new. If the account
        // changed meanwhile, the running sync does one more pass for the new account.
        guard !syncing else {
            needsAnotherPass = true
            return
        }
        syncing = true
        defer { syncing = false }

        repeat {
            needsAnotherPass = false
            guard let currentUser = userID else { return }
            await refreshFlagsIfStale(for: currentUser)
            guard userID == currentUser else { continue }
            await reportIfNeeded(for: currentUser)
        } while needsAnotherPass && userID != nil
    }

    private func refreshFlagsIfStale(for user: UUID) async {
        if let snapshot = cache.load(), CoachV2FlagCache.isFresh(snapshot, for: user, now: now()) {
            publish()
            return
        }
        do {
            // Pilot access only changes the answer in App Store builds.
            async let flags = repository.runtimeFlags()
            var pilot = false
            if channel == .appStore { pilot = try await repository.pilotAccess() }
            let flagMap = try await flags
            let v2FlagOn = flagMap["coach_v2"] ?? false
            guard userID == user else { return }
            cache.save(CoachV2FlagSnapshot(userID: user, v2FlagOn: v2FlagOn, pilotAccess: pilot, fetchedAt: now()))
        } catch {
            // Keep the last answer for this user. The server enforces the switch either way.
            if !(error is CancellationError) {
                print("[CoachV2Gate] flag read failed:", error)
            }
        }
        publish()
    }

    private func reportIfNeeded(for user: UUID) async {
        // Never report from a guess. Without flags read for this account, a failed flag
        // or pilot read could overwrite a correct `true` on the server. Retry next foreground.
        guard let snapshot = cache.load(), snapshot.userID == user else { return }
        // Report what this client can do, not the switched state. The server applies the
        // kill switch inside link_is_v2, so reporting `false` while it is off would leave
        // athletes who don't reopen the app looking outdated after the switch returns.
        let report = CoachV2CapabilityReport(
            coachV2: RunSmartFeatures.coachV2WouldBeEnabled(
                channel: channel, processArguments: processArguments, pilotAccess: snapshot.pilotAccess
            ),
            version: appVersion,
            build: appBuild,
            channel: channel
        )
        if let last = lastReport, last.userID == user, last.report == report,
           now().timeIntervalSince(last.at) < Self.reportReuseInterval {
            return
        }
        do {
            try await repository.reportCapabilities(report)
            lastReport = (user, report, now())
        } catch {
            // Offline or the server lacks the migration: try again next foreground.
            if !(error is CancellationError) {
                print("[CoachV2Gate] capability report failed:", error)
            }
        }
    }

    private func publish() {
        let snapshot = userID.flatMap { user in cache.load().flatMap { $0.userID == user ? $0 : nil } }
        guard let snapshot else {
            state = .off
            return
        }
        if RunSmartFeatures.coachV2Enabled(
            channel: channel, processArguments: processArguments,
            pilotAccess: snapshot.pilotAccess, v2FlagOn: snapshot.v2FlagOn
        ) {
            state = .on
        } else if !snapshot.v2FlagOn, RunSmartFeatures.coachV2WouldBeEnabled(
            channel: channel, processArguments: processArguments, pilotAccess: snapshot.pilotAccess
        ) {
            state = .paused
        } else {
            state = .off
        }
    }
}
