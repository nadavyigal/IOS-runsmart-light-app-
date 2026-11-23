import Combine
import Foundation
import UIKit
@preconcurrency import UserNotifications
import Supabase

// Remote push foundation (Coach Experience v2, story C7.10). "Coach" means a HUMAN coach
// (Coach Mode), not the AI coach.
//
// Server side: supabase/migrations/20261122100000_push_tokens_and_prefs.sql (M2a) and
// supabase/functions/_shared/apns.ts.
//
// Rules this file keeps:
// - Everything is behind Coach v2. With v2 off nothing renders, no permission prompt shows and no
//   server call is made. The one exception is sign-out: a token this device registered earlier is
//   removed, so the next account on the phone never gets the last one's pushes.
// - Permission is asked in context only (AC2, AC3): T6 on the coach's first Coach Today, P10 after
//   the athlete's P8 or P9 OK. Never on sign-in (AC4).
// - "Turn on" shows the system prompt only while iOS has not asked yet. After a denial the app never
//   calls it again (AC4); C7.14's settings show "Open Settings" instead.
// - When iOS already allows notifications (the user said yes to RunSmart's reminders earlier), the
//   context moment registers the device directly, with no card: there is nothing to ask.
// - One token per device (AC5). Sign-out removes only this device's token.
// - The first prefs read creates the row with the D6 defaults and this device's time zone (AC9).
//   It happens right after the first token registration; later foregrounds update the zone when it
//   changes.

nonisolated enum RemotePushRole: String, Codable, Sendable, CaseIterable {
    case coach
    case athlete
}

/// Matches `push_tokens.environment`. Debug builds get sandbox tokens; TestFlight and App Store
/// builds (Release, aps-environment = production) get production tokens.
nonisolated enum RemotePushEnvironment: String, Sendable {
    case sandbox
    case production

    static var current: RemotePushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

enum RemotePushRPC {
    static let register = "register_push_token"
    static let unregister = "unregister_push_token"
    static let prefs = "my_notification_prefs"
    static let setTimeZone = "set_notification_time_zone"
}

/// The P10 sheet's subject.
nonisolated struct RemotePushAthletePrimer: Identifiable, Equatable, Sendable {
    let coachName: String
    var id: String { coachName }
}

// MARK: Repository

nonisolated struct RemoteNotificationPrefs: Decodable, Equatable, Sendable {
    let timeZone: String

    enum CodingKeys: String, CodingKey {
        case timeZone = "time_zone"
    }
}

nonisolated protocol RemotePushRepository: Sendable {
    func register(token: String, environment: RemotePushEnvironment, bundleID: String?) async throws
    func unregister(token: String) async throws
    /// `my_notification_prefs`: the first call creates the row.
    func prefs(timeZone: String) async throws -> RemoteNotificationPrefs
    func setTimeZone(_ timeZone: String) async throws
}

nonisolated struct SupabaseRemotePushRepository: RemotePushRepository {
    private struct RegisterParams: Encodable {
        let p_token: String
        let p_env: String
        let p_bundle_id: String?
    }

    private struct TokenParams: Encodable {
        let p_token: String
    }

    private struct ZoneParams: Encodable {
        let p_time_zone: String
    }

    func register(token: String, environment: RemotePushEnvironment, bundleID: String?) async throws {
        try await SupabaseManager.client
            .rpc(RemotePushRPC.register, params: RegisterParams(p_token: token, p_env: environment.rawValue, p_bundle_id: bundleID))
            .execute()
    }

    func unregister(token: String) async throws {
        try await SupabaseManager.client
            .rpc(RemotePushRPC.unregister, params: TokenParams(p_token: token))
            .execute()
    }

    func prefs(timeZone: String) async throws -> RemoteNotificationPrefs {
        try await SupabaseManager.client
            .rpc(RemotePushRPC.prefs, params: ZoneParams(p_time_zone: timeZone))
            .execute()
            .value
    }

    func setTimeZone(_ timeZone: String) async throws {
        try await SupabaseManager.client
            .rpc(RemotePushRPC.setTimeZone, params: ZoneParams(p_time_zone: timeZone))
            .execute()
    }
}

// MARK: System

/// The iOS calls, behind a protocol so tests can count them.
protocol RemotePushSystem {
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Shows the system prompt. Callers only call it while the status is `.notDetermined`.
    func requestAuthorization() async throws -> Bool
    func registerForRemoteNotifications()
    /// Drops this device's APNs token, so a push already addressed to it can no longer arrive.
    func unregisterForRemoteNotifications()
}

struct LiveRemotePushSystem: RemotePushSystem {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        // Through PushService so the existing permission funnel events stay complete.
        try await PushService.shared.requestAuthorization()
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func unregisterForRemoteNotifications() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}

// MARK: Device state

/// What this device remembers, per account where it matters.
nonisolated struct RemotePushDeviceState: Codable, Equatable, Sendable {
    struct Registration: Codable, Equatable, Sendable {
        var userID: UUID
        var token: String
        var sentAt: Date
    }

    /// A token whose server row a sign-out could not remove (offline, error or timeout).
    struct PendingUnregister: Codable, Equatable, Sendable {
        var userID: UUID
        var token: String
    }

    /// T6 / P10 answered ("Turn on" or "Not now"), per account. Never shown again after that.
    var answered: [String: Set<RemotePushRole>] = [:]
    /// T6 / P10 shown at least once, per account (for `push_permission_prompted`).
    var shown: [String: Set<RemotePushRole>] = [:]
    /// The token this device registered, and for whom.
    var registration: Registration?
    /// Retried when that same account is signed in again (only its own session may remove it).
    var pendingUnregister: PendingUnregister?
    /// The time zone last stored in `notification_prefs`, per account. Present once the row exists.
    var prefsTimeZone: [String: String] = [:]

    func didAnswer(_ role: RemotePushRole, user: UUID) -> Bool {
        answered[user.uuidString]?.contains(role) ?? false
    }

    func didShow(_ role: RemotePushRole, user: UUID) -> Bool {
        shown[user.uuidString]?.contains(role) ?? false
    }
}

nonisolated struct RemotePushStateStore: @unchecked Sendable {
    static let standard = RemotePushStateStore(defaults: .standard)

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "coachV2.remotePush.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> RemotePushDeviceState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(RemotePushDeviceState.self, from: data) else {
            return RemotePushDeviceState()
        }
        return state
    }

    func save(_ state: RemotePushDeviceState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: Registrar

@MainActor
final class RemotePushRegistrar: ObservableObject {
    static let shared = RemotePushRegistrar()

    /// T6 card on Coach Today.
    @Published private(set) var showsCoachPrimer = false
    /// P10 sheet after P8 / P9.
    @Published private(set) var athletePrimer: RemotePushAthletePrimer?
    @Published private(set) var isWorking = false
    /// The one-line notice after a tap whose target is gone (AC8).
    @Published var tapNotice: String?

    /// A token is sent again at most once a day when it has not changed.
    static let tokenRefreshInterval: TimeInterval = 24 * 60 * 60

    private let repository: any RemotePushRepository
    private let system: any RemotePushSystem
    private let store: RemotePushStateStore
    private let analytics: () -> any AnalyticsTracking
    private let timeZone: () -> String
    private let bundleID: String?
    private let environment: RemotePushEnvironment
    private let now: () -> Date
    private let unregisterTimeout: TimeInterval

    private(set) var userID: UUID?
    private(set) var v2Enabled = false
    /// A token iOS handed over that the server has not stored yet.
    private(set) var pendingToken: String?
    private var isRetryingUnregister = false

    init(
        repository: any RemotePushRepository = SupabaseRemotePushRepository(),
        system: any RemotePushSystem = LiveRemotePushSystem(),
        store: RemotePushStateStore = .standard,
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared },
        timeZone: @escaping () -> String = { TimeZone.current.identifier },
        bundleID: String? = Bundle.main.bundleIdentifier,
        environment: RemotePushEnvironment = .current,
        now: @escaping () -> Date = Date.init,
        unregisterTimeout: TimeInterval = 3
    ) {
        self.repository = repository
        self.system = system
        self.store = store
        self.analytics = analytics
        self.timeZone = timeZone
        self.bundleID = bundleID
        self.environment = environment
        self.now = now
        self.unregisterTimeout = unregisterTimeout
    }

    nonisolated deinit {}

    /// Call on sign-in, sign-out and whenever the v2 gate changes.
    func update(userID newUserID: UUID?, v2Enabled enabled: Bool) {
        if newUserID != userID {
            userID = newUserID
            pendingToken = nil
            showsCoachPrimer = false
            athletePrimer = nil
            tapNotice = nil
        }
        v2Enabled = enabled && newUserID != nil
        if !v2Enabled {
            showsCoachPrimer = false
            athletePrimer = nil
        }
    }

    // MARK: Context moments

    /// AC2: the coach opened Coach Today with v2 on.
    func coachTodayOpened() async {
        await contextMoment(.coach) { [weak self] in self?.showsCoachPrimer = true }
    }

    /// AC3: the athlete tapped OK on P8 (join) or P9 (notice) with v2 on.
    func athleteConsentAcknowledged(coachName: String) async {
        await contextMoment(.athlete) { [weak self] in
            self?.athletePrimer = RemotePushAthletePrimer(coachName: coachName)
        }
    }

    private func contextMoment(_ role: RemotePushRole, show: () -> Void) async {
        guard v2Enabled, let user = userID else { return }
        let status = await system.authorizationStatus()
        guard v2Enabled, userID == user else { return }
        switch status {
        case .notDetermined:
            var state = store.load()
            guard !state.didAnswer(role, user: user) else { return }
            show()
            if !state.didShow(role, user: user) {
                state.shown[user.uuidString, default: []].insert(role)
                store.save(state)
                CoachV2Analytics.track(.pushPermissionPrompted(role: role), to: analytics())
            }
        case .authorized, .provisional, .ephemeral:
            // iOS already allows notifications: register in this context, nothing to ask.
            system.registerForRemoteNotifications()
        case .denied:
            // Never prompt again. C7.14 shows "Open Settings".
            break
        @unknown default:
            break
        }
    }

    /// "Turn on" on T6 / P10, or later from C7.14's settings.
    func turnOn(_ role: RemotePushRole) async {
        guard v2Enabled, let user = userID, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        markAnswered(role, user: user)
        hidePrimer(role)

        switch await system.authorizationStatus() {
        case .notDetermined:
            let granted: Bool
            do {
                granted = try await system.requestAuthorization()
            } catch {
                // An API failure is not the user's answer: no result event, nothing registered.
                return
            }
            CoachV2Analytics.track(.pushPermissionResult(role: role, granted: granted), to: analytics())
            guard granted, v2Enabled, userID == user else { return }
            system.registerForRemoteNotifications()
        case .authorized, .provisional, .ephemeral:
            system.registerForRemoteNotifications()
        case .denied:
            break
        @unknown default:
            break
        }
    }

    /// "Not now", or swiping P10 away: no system prompt.
    func notNow(_ role: RemotePushRole) {
        guard let user = userID else { return }
        markAnswered(role, user: user)
        hidePrimer(role)
    }

    // MARK: Tokens

    /// From the app delegate.
    func didRegister(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard v2Enabled, let user = userID else {
            pendingToken = token
            return
        }
        await send(token: token, for: user)
    }

    func didFailToRegister(_ error: Error) {
        print("[RemotePush] registration failed:", error.localizedDescription)
    }

    private func send(token: String, for user: UUID) async {
        var state = store.load()
        if let registration = state.registration, registration.userID == user, registration.token == token,
           now().timeIntervalSince(registration.sentAt) < Self.tokenRefreshInterval,
           now() >= registration.sentAt {
            pendingToken = nil
            return
        }
        do {
            try await repository.register(token: token, environment: environment, bundleID: bundleID)
        } catch {
            // Offline or the server lacks M2a: send again on the next foreground.
            if !(error is CancellationError) { print("[RemotePush] token register failed:", error) }
            pendingToken = token
            return
        }
        guard userID == user else { return }
        pendingToken = nil
        state = store.load()
        state.registration = .init(userID: user, token: token, sentAt: now())
        // The server moved this token's row to this account, so an old removal no longer applies.
        if state.pendingUnregister?.token == token { state.pendingUnregister = nil }
        store.save(state)
        await ensurePrefs(for: user)
    }

    /// AC9: the first read creates the row with this device's zone.
    private func ensurePrefs(for user: UUID) async {
        guard store.load().prefsTimeZone[user.uuidString] == nil else { return }
        let zone = timeZone()
        do {
            let prefs = try await repository.prefs(timeZone: zone)
            guard userID == user else { return }
            var stored = prefs.timeZone
            if stored != zone {
                // The row was created on another device in another zone. This device is where the
                // user is now.
                try await repository.setTimeZone(zone)
                stored = zone
            }
            var state = store.load()
            state.prefsTimeZone[user.uuidString] = stored
            store.save(state)
        } catch {
            if !(error is CancellationError) { print("[RemotePush] prefs read failed:", error) }
        }
    }

    // MARK: Foreground and sign-out

    /// Every foreground with v2 on: send a token that failed, refresh this device's token, and
    /// update the stored time zone when it changed.
    func foreground() async {
        await retryPendingUnregister()
        guard v2Enabled, let user = userID else { return }
        if let token = pendingToken {
            await send(token: token, for: user)
        } else if store.load().registration?.userID == user {
            switch await system.authorizationStatus() {
            case .authorized, .provisional, .ephemeral:
                // iOS may rotate the token; the callback re-sends only a new one (or once a day).
                system.registerForRemoteNotifications()
            default:
                break
            }
        }
        guard v2Enabled, userID == user else { return }
        var state = store.load()
        if store.load().registration?.userID == user, state.prefsTimeZone[user.uuidString] == nil {
            await ensurePrefs(for: user)
            return
        }
        let zone = timeZone()
        guard let stored = state.prefsTimeZone[user.uuidString], stored != zone else { return }
        do {
            try await repository.setTimeZone(zone)
            state = store.load()
            state.prefsTimeZone[user.uuidString] = zone
            store.save(state)
        } catch {
            if !(error is CancellationError) { print("[RemotePush] time zone update failed:", error) }
        }
    }

    /// AC5: before the session ends. Removes only this device's token, bounded so an offline
    /// sign-out never waits long. The local record goes either way.
    /// When the server call fails or times out, the old account's row stays live, and the next
    /// person on this phone would get its coach pushes (pain flags included). So the device drops
    /// its APNs token: pushes to the old row then fail at Apple (410) instead of arriving here.
    /// The removal is kept and retried the next time that same account is signed in.
    func signOut() async {
        showsCoachPrimer = false
        athletePrimer = nil
        tapNotice = nil
        pendingToken = nil
        var state = store.load()
        guard let registration = state.registration else { return }
        let removed = await unregisterBounded(token: registration.token)
        state = store.load()
        state.registration = nil
        if removed {
            if state.pendingUnregister?.token == registration.token { state.pendingUnregister = nil }
        } else {
            system.unregisterForRemoteNotifications()
            state.pendingUnregister = .init(userID: registration.userID, token: registration.token)
        }
        store.save(state)
    }

    /// The server half of a sign-out that failed earlier. Runs only while that same account is
    /// signed in, since `unregister_push_token` removes the caller's own rows only.
    func retryPendingUnregister() async {
        guard !isRetryingUnregister, let user = userID,
              let pending = store.load().pendingUnregister, pending.userID == user else { return }
        var state = store.load()
        if let registration = state.registration, registration.userID == user, registration.token == pending.token {
            // The same account registered this token again since: the row is live on purpose.
            state.pendingUnregister = nil
            store.save(state)
            return
        }
        isRetryingUnregister = true
        defer { isRetryingUnregister = false }
        guard await unregisterBounded(token: pending.token) else { return }
        state = store.load()
        if state.pendingUnregister == pending { state.pendingUnregister = nil }
        if let registration = state.registration, registration.userID == user, registration.token == pending.token {
            // Registered again while the removal ran: send it once more on the next foreground.
            state.registration = nil
            if userID == user { pendingToken = pending.token }
        }
        store.save(state)
    }

    /// True only when the server call finished without an error inside the timeout.
    private func unregisterBounded(token: String) async -> Bool {
        let repository = repository
        let timeout = unregisterTimeout
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    try await repository.unregister(token: token)
                    return true
                } catch {
                    if !(error is CancellationError) { print("[RemotePush] unregister failed:", error) }
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    // MARK: Taps

    /// AC8: a tapped remote push. Returns the route; the caller opens it.
    func route(for payload: RemotePushPayload, context: RemotePushRouteContext) -> RemotePushRoute {
        let route = RemotePushRouter.route(payload, context: context)
        if context.v2Enabled {
            CoachV2Analytics.track(.pushOpened(kind: payload.kind), to: analytics())
            tapNotice = route.notice
        }
        return route
    }

    // MARK: Helpers

    private func markAnswered(_ role: RemotePushRole, user: UUID) {
        var state = store.load()
        state.answered[user.uuidString, default: []].insert(role)
        store.save(state)
    }

    private func hidePrimer(_ role: RemotePushRole) {
        switch role {
        case .coach: showsCoachPrimer = false
        case .athlete: athletePrimer = nil
        }
    }
}

extension Notification.Name {
    /// C7.10 AC3: the athlete tapped OK on P8 (join) or P9 (notice). `object` is the coach's name.
    static let remotePushAthleteContext = Notification.Name("runsmart.remotePushAthleteContext")
}
