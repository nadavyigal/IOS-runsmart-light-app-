import Combine
import Foundation
import Supabase

// Coach Experience v2, story C7.4: the athlete's "Pain / something off" flag. "Coach" means a
// HUMAN coach (Coach Mode), not the AI coach.
//
// Server side: supabase/migrations/20261121150000_athlete_run_flags.sql (M1b). A flag is athlete
// health data: the server shares it only while coach_v2_sharing_allowed holds. On the phone the
// flag row shows only while C7.3's sharing context is sharing (v2 on, linked, v2 copy accepted),
// so "{Coach} will see this" is never shown when it is not true (C7.4 AC9).
//
// No plan, AI or flex-week code reads flags (C7.4 AC8). Nothing here feeds the plan engine.

enum RunFlagRPC {
    static let flag = "athlete_flag_run"
    static let remove = "athlete_remove_flag"
    static let coachFlags = "coach_get_athlete_flags"
    static let resolve = "coach_resolve_flag"
}

/// `athlete_run_flags.kind`.
nonisolated enum RunFlagKind: String, Codable, CaseIterable, Sendable {
    case pain
    /// "Something else" to the athlete, "Something off" to the coach (UX spec Part 2, C7.4).
    case off

    var athleteLabel: String { self == .pain ? "Pain" : "Something else" }
    var coachLabel: String { self == .pain ? "Pain" : "Something off" }
}

/// Fixed strings for the flag (UX spec C.5 P7, A.6). Names are direction-isolated (C7.15).
nonisolated enum RunFlagCopy {
    static let noteLimit = 500
    static let entry = "Something off?"
    static let notePlaceholder = "What's going on? (optional)"
    static let safety = "If the pain is sharp or doesn't go away, check with a doctor or physio."
    static let removeFlag = "Remove flag"
    static let waiting = "Waiting to send"
    static let markHandled = "Mark handled"
    static let markedHandledToast = "Marked handled · Undo"
    static let runDeleted = "Run deleted"
    static let flagsFailed = "Pain flags didn't load. Try again."

    static func send(coach: String) -> String { BidiText.fill("Send to {Coach}", ["Coach": coach]) }
    static func willSee(coach: String) -> String { BidiText.fill("{Coach} will see this.", ["Coach": coach]) }
    static func sent(coach: String) -> String { BidiText.fill("Sent to {Coach}", ["Coach": coach]) }
    static func saw(coach: String) -> String { BidiText.fill("{Coach} saw this", ["Coach": coach]) }
    /// Link-ended AC (v1.3 section 1.1), adapted from the C7.7 reply copy. [ASSUMPTION]
    static func notSent(coach: String) -> String {
        BidiText.fill("You're no longer linked to {Coach}, so this flag wasn't sent.", ["Coach": coach])
    }
    static func writeTo(athlete: String) -> String { BidiText.fill("Write to {Athlete}", ["Athlete": athlete]) }
    /// Coach failure path (UX spec A.1).
    static func actionFailed(athlete: String) -> String {
        BidiText.fill("1 action couldn't be saved: {Athlete} is no longer linked to you.", ["Athlete": athlete])
    }

    /// The coach's row preview: the first 60 characters of the note (UX spec A.6).
    static func preview(_ note: String?) -> String? {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        return note.count > 60 ? String(note.prefix(60)) + "…" : note
    }

    /// "Pain · 24 Nov" (T4 title) and "Handled by you · 24 Nov".
    static func dayLabel(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    static func title(_ kind: RunFlagKind, date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "\(kind.coachLabel) · \(dayLabel(date, calendar: calendar, locale: locale))"
    }

    static func handledByYou(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "Handled by you · \(dayLabel(date, calendar: calendar, locale: locale))"
    }
}

// MARK: Athlete side

/// A flag this phone sent (or is sending). Kept on the device so P7 can show it under its run.
nonisolated struct AthleteRunFlag: Codable, Equatable, Identifiable, Sendable {
    /// Client id, sent as `p_id`: two flushes store one row.
    let id: UUID
    let ownerID: UUID
    let kind: RunFlagKind
    let note: String?
    /// Nil for the run-less "Something off?" on Today.
    let runKey: RunShareKey?
    let createdAt: Date
    var sent = false
    var resolvedAt: Date?

    enum Status: Equatable { case waiting, sent, seen }

    var status: Status { resolvedAt != nil ? .seen : (sent ? .sent : .waiting) }
    /// "Remove flag" only until the coach marks it handled (C7.4 AC5).
    var canRemove: Bool { resolvedAt == nil }
}

nonisolated struct PendingFlagAction: Codable, Equatable, Identifiable, Sendable {
    enum Action: Codable, Equatable, Sendable {
        case create
        case remove
    }

    let id: UUID
    let flagID: UUID
    let ownerID: UUID
    let action: Action
    let createdAt: Date
}

nonisolated enum RunFlagWriteResult: String, Sendable {
    case saved
    case savedWithoutRun = "saved_without_run"
    case removed
    case missing
}

/// What the outbox does after a failed write (v1.3 section 1.1).
nonisolated enum RunFlagFailure: Equatable, Sendable {
    /// Offline, a server error or `v2_unavailable` (kill switch): keep it and stop this flush.
    case keep
    /// The link ended: drop it and tell the athlete once.
    case linkGone
    /// The coach already handled it (a remove that came too late): keep the flag as seen.
    case alreadyResolved
    /// The server will never take it: drop it.
    case drop

    static func classify(_ error: Error) -> RunFlagFailure {
        let message = (error as? PostgrestError)?.message ?? String(describing: error)
        if message.contains("v2_unavailable") { return .keep }
        if message.contains("link_inactive") { return .linkGone }
        if message.contains("flag_resolved") { return .alreadyResolved }
        let dropTokens = ["consent_required", "bad_kind", "note_too_long", "bad_flag_id"]
        return dropTokens.contains { message.contains($0) } ? .drop : .keep
    }
}

/// The server row the athlete reads through the owner-select policy.
nonisolated struct AthleteFlagServerState: Equatable, Sendable {
    let id: UUID
    let resolvedAt: Date?
}

nonisolated protocol AthleteRunFlagRepository: Sendable {
    func create(_ flag: AthleteRunFlag) async throws -> RunFlagWriteResult
    func remove(flagID: UUID) async throws -> RunFlagWriteResult
    /// The signed-in athlete's flags (owner select).
    func myFlags(ids: [UUID]) async throws -> [AthleteFlagServerState]
}

nonisolated struct SupabaseAthleteRunFlagRepository: AthleteRunFlagRepository {
    private struct CreateParams: Encodable {
        let p_id: UUID
        let p_kind: String
        let p_note: String?
        let p_source_provider: String?
        let p_source_activity_id: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(p_id, forKey: .p_id)
            try container.encode(p_kind, forKey: .p_kind)
            try container.encode(p_note, forKey: .p_note)
            try container.encode(p_source_provider, forKey: .p_source_provider)
            try container.encode(p_source_activity_id, forKey: .p_source_activity_id)
        }

        enum CodingKeys: String, CodingKey { case p_id, p_kind, p_note, p_source_provider, p_source_activity_id }
    }

    private struct RemoveParams: Encodable { let p_id: UUID }

    private struct Row: Decodable {
        let id: UUID
        let resolvedAt: String?
        enum CodingKeys: String, CodingKey { case id, resolvedAt = "resolved_at" }
    }

    func create(_ flag: AthleteRunFlag) async throws -> RunFlagWriteResult {
        let raw: String = try await SupabaseManager.client.rpc(RunFlagRPC.flag, params: CreateParams(
            p_id: flag.id, p_kind: flag.kind.rawValue, p_note: flag.note,
            p_source_provider: flag.runKey?.sourceProvider, p_source_activity_id: flag.runKey?.sourceActivityID
        )).execute().value
        return RunFlagWriteResult(rawValue: raw) ?? .saved
    }

    func remove(flagID: UUID) async throws -> RunFlagWriteResult {
        let raw: String = try await SupabaseManager.client
            .rpc(RunFlagRPC.remove, params: RemoveParams(p_id: flagID)).execute().value
        return RunFlagWriteResult(rawValue: raw) ?? .missing
    }

    func myFlags(ids: [UUID]) async throws -> [AthleteFlagServerState] {
        guard !ids.isEmpty else { return [] }
        let rows: [Row] = try await SupabaseManager.client.from("athlete_run_flags")
            .select("id,resolved_at")
            .in("id", values: ids.map(\.uuidString))
            .execute().value
        return rows.map { AthleteFlagServerState(id: $0.id, resolvedAt: $0.resolvedAt.flatMap(CoachSeenTimestamp.parse)) }
    }
}

/// Owns C7.4 on the athlete's phone. Follows C7.3's sharing context: refreshed on sign-in, when the
/// link or gate changes and on every foreground, and flushes its outbox each time.
@MainActor
final class AthleteRunFlagService: ObservableObject {
    static let shared = AthleteRunFlagService()
    /// Queued actions older than this are dropped, like the other v2 outboxes.
    static let maxAge: TimeInterval = 14 * 24 * 3600

    @Published private(set) var context = RunSharingContext.off
    @Published private(set) var flags: [AthleteRunFlag] {
        didSet { save(flags, key: flagsKey) }
    }
    @Published private(set) var pending: [PendingFlagAction] {
        didSet { save(pending, key: outboxKey) }
    }
    /// Set when a queued flag was dropped because the link ended. Shown once.
    @Published var linkGoneNotice = false

    private let repository: any AthleteRunFlagRepository
    private let defaults: UserDefaults
    private let analytics: () -> any AnalyticsTracking
    private let now: () -> Date
    private let flagsKey: String
    private let outboxKey: String
    private var flushing = false
    private var subscription: AnyCancellable?

    init(
        repository: any AthleteRunFlagRepository = SupabaseAthleteRunFlagRepository(),
        defaults: UserDefaults = .standard,
        keyPrefix: String = "coachV2.runFlags",
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared },
        now: @escaping () -> Date = Date.init,
        sharing: AnyPublisher<RunSharingContext, Never>? = nil
    ) {
        self.repository = repository
        self.defaults = defaults
        self.analytics = analytics
        self.now = now
        flagsKey = "\(keyPrefix).flags.v1"
        outboxKey = "\(keyPrefix).outbox.v1"
        flags = Self.load([AthleteRunFlag].self, defaults: defaults, key: "\(keyPrefix).flags.v1") ?? []
        pending = Self.load([PendingFlagAction].self, defaults: defaults, key: "\(keyPrefix).outbox.v1") ?? []
        let source = sharing ?? AthleteRunSharingService.shared.$context.eraseToAnyPublisher()
        subscription = source.removeDuplicates().sink { [weak self] next in
            Task { @MainActor in await self?.apply(next) }
        }
    }

    nonisolated deinit {}

    // MARK: Gate

    /// The flag row shows only while this is true (C7.4 AC9: no ack, not v2, solo or flag off hides it).
    var isSharing: Bool { RunSharingPolicy.isSharing(context) }
    var coachName: String? { isSharing ? context.coachName : nil }

    func apply(_ next: RunSharingContext) async {
        context = next
        guard next.v2Enabled, next.userID != nil else { return }
        await flush()
        await refreshStatuses()
    }

    // MARK: What P7 and Today show

    func flags(for run: RecordedRun?) -> [AthleteRunFlag] {
        guard let owner = context.userID else { return [] }
        let key = run.map(RunShareKey.init(run:))
        return flags.filter { $0.ownerID == owner && $0.runKey == key }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Actions

    /// "Send to {Coach}". Does nothing unless sharing (flag-off AC: no event, no queue, no call).
    func send(kind: RunFlagKind, note: String, run: RecordedRun?) async {
        guard isSharing, let owner = context.userID else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let flag = AthleteRunFlag(
            id: UUID(), ownerID: owner, kind: kind,
            note: trimmed.isEmpty ? nil : String(trimmed.prefix(RunFlagCopy.noteLimit)),
            runKey: run.map(RunShareKey.init(run:)), createdAt: now()
        )
        flags.append(flag)
        pending.append(PendingFlagAction(id: UUID(), flagID: flag.id, ownerID: owner, action: .create, createdAt: now()))
        track(.flagCreated(kind: kind, hasRun: run != nil))
        await flush()
    }

    /// "Remove flag" (C7.4 AC5). A flag that never left the phone is just forgotten.
    func remove(_ flag: AthleteRunFlag) async {
        guard flag.canRemove, let owner = context.userID, flag.ownerID == owner else { return }
        track(.flagRemoved)
        if pending.contains(where: { $0.flagID == flag.id && $0.action == .create }) {
            pending.removeAll { $0.flagID == flag.id }
            flags.removeAll { $0.id == flag.id }
            return
        }
        flags.removeAll { $0.id == flag.id }
        pending.append(PendingFlagAction(id: UUID(), flagID: flag.id, ownerID: owner, action: .remove, createdAt: now()))
        await flush()
    }

    /// Sends this account's queued actions in order. Stops at the first one that must wait.
    func flush() async {
        guard !flushing, let owner = context.userID else { return }
        flushing = true
        defer { flushing = false }
        let cutoff = now().addingTimeInterval(-Self.maxAge)
        pending.removeAll { $0.createdAt < cutoff }
        // Creates go out only while sharing. Removes go out whenever this account is signed in.
        let sharing = isSharing
        for item in pending where item.ownerID == owner {
            guard pending.contains(item) else { continue }
            if item.action == .create && !sharing { return }
            do {
                switch item.action {
                case .create:
                    guard let flag = flags.first(where: { $0.id == item.flagID }) else { break }
                    _ = try await repository.create(flag)
                    update(item.flagID) { $0.sent = true }
                case .remove:
                    _ = try await repository.remove(flagID: item.flagID)
                }
                pending.removeAll { $0.id == item.id }
            } catch {
                if error is CancellationError { return }
                switch RunFlagFailure.classify(error) {
                case .keep:
                    return
                case .linkGone:
                    pending.removeAll { $0.id == item.id }
                    if item.action == .create {
                        flags.removeAll { $0.id == item.flagID }
                        linkGoneNotice = true
                    }
                case .alreadyResolved:
                    pending.removeAll { $0.id == item.id }
                case .drop:
                    pending.removeAll { $0.id == item.id }
                    if item.action == .create { flags.removeAll { $0.id == item.flagID } }
                }
            }
        }
    }

    /// Reads "{Coach} saw this" for sent flags. Offline it keeps what it had.
    func refreshStatuses() async {
        guard isSharing, let owner = context.userID else { return }
        let sent = flags.filter { $0.ownerID == owner && $0.sent }
        guard !sent.isEmpty, let states = try? await repository.myFlags(ids: sent.map(\.id)) else { return }
        let byID = Dictionary(states.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // A flag missing from the answer is kept: an empty or partial read must never wipe what the
        // athlete sent. Only a returned row changes the local state.
        for flag in sent {
            if let state = byID[flag.id] { update(flag.id) { $0.resolvedAt = state.resolvedAt } }
        }
    }

    // MARK: Private

    private func update(_ id: UUID, _ change: (inout AthleteRunFlag) -> Void) {
        guard let index = flags.firstIndex(where: { $0.id == id }) else { return }
        var flag = flags[index]
        change(&flag)
        if flags[index] != flag { flags[index] = flag }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func track(_ event: CoachV2Analytics.Event) {
        CoachV2Analytics.track(event, to: analytics())
    }
}

// MARK: Coach side

/// One row of `coach_get_athlete_flags`. `note` is the athlete's text, shown to the coach only.
nonisolated struct CoachRunFlag: Equatable, Identifiable, Sendable {
    let id: UUID
    let athleteID: UUID
    let runID: Int?
    let runDeleted: Bool
    let kind: RunFlagKind
    let note: String?
    let createdAt: Date
    var resolvedAt: Date?
    var resolvedByMe: Bool

    init(
        id: UUID, athleteID: UUID, runID: Int? = nil, runDeleted: Bool = false, kind: RunFlagKind,
        note: String? = nil, createdAt: Date, resolvedAt: Date? = nil, resolvedByMe: Bool = false
    ) {
        self.id = id
        self.athleteID = athleteID
        self.runID = runID
        self.runDeleted = runDeleted
        self.kind = kind
        self.note = note
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolvedByMe = resolvedByMe
    }

    var isOpen: Bool { resolvedAt == nil }
}

nonisolated protocol CoachFlagRepository: Sendable {
    func flags(athleteIDs: [UUID]?, includeResolved: Bool) async throws -> [CoachRunFlag]
    /// Returns the stored `resolved_at`.
    func resolve(flagID: UUID) async throws -> Date?
}

nonisolated struct SupabaseCoachFlagRepository: CoachFlagRepository {
    private struct Params: Encodable {
        let p_athlete_ids: [UUID]?
        let p_include_resolved: Bool

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(p_athlete_ids, forKey: .p_athlete_ids)
            try container.encode(p_include_resolved, forKey: .p_include_resolved)
        }

        enum CodingKeys: String, CodingKey { case p_athlete_ids, p_include_resolved }
    }

    private struct ResolveParams: Encodable { let p_flag_id: UUID }

    private struct Row: Decodable {
        let id: UUID
        let athleteID: UUID
        let runID: Int?
        let runDeleted: Bool
        let kind: String
        let note: String?
        let createdAt: String
        let resolvedAt: String?
        let resolvedByMe: Bool

        enum CodingKeys: String, CodingKey {
            case id, kind, note
            case athleteID = "athlete_id"
            case runID = "run_id"
            case runDeleted = "run_deleted"
            case createdAt = "created_at"
            case resolvedAt = "resolved_at"
            case resolvedByMe = "resolved_by_me"
        }
    }

    func flags(athleteIDs: [UUID]?, includeResolved: Bool) async throws -> [CoachRunFlag] {
        let rows: [Row] = try await SupabaseManager.client
            .rpc(RunFlagRPC.coachFlags, params: Params(p_athlete_ids: athleteIDs, p_include_resolved: includeResolved))
            .execute().value
        return rows.compactMap { row in
            guard let kind = RunFlagKind(rawValue: row.kind), let created = CoachSeenTimestamp.parse(row.createdAt) else {
                return nil
            }
            return CoachRunFlag(
                id: row.id, athleteID: row.athleteID, runID: row.runID, runDeleted: row.runDeleted, kind: kind,
                note: row.note, createdAt: created, resolvedAt: row.resolvedAt.flatMap(CoachSeenTimestamp.parse),
                resolvedByMe: row.resolvedByMe
            )
        }
    }

    func resolve(flagID: UUID) async throws -> Date? {
        let raw: String = try await SupabaseManager.client
            .rpc(RunFlagRPC.resolve, params: ResolveParams(p_flag_id: flagID)).execute().value
        return CoachSeenTimestamp.parse(raw)
    }
}

/// A queued "Mark handled". Sent `CoachFlagStore.undoWindow` after the tap (C7.4 AC7, UX spec A.7 item 11).
nonisolated struct PendingFlagResolve: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { flagID }
    let flagID: UUID
    let athleteID: UUID
    let coachID: UUID
    let flagCreatedAt: Date
    let queuedAt: Date
}

nonisolated enum CoachFlagFailure: Equatable, Sendable {
    /// Offline, a server error or `v2_unavailable`: keep it queued.
    case keep
    /// The link ended, or the flag is gone (removed by the athlete): drop it.
    case drop

    static func classify(_ error: Error) -> CoachFlagFailure {
        let message = (error as? PostgrestError)?.message ?? String(describing: error)
        if message.contains("v2_unavailable") { return .keep }
        let dropTokens = ["link_inactive", "flag_not_found", "consent_required"]
        return dropTokens.contains { message.contains($0) } ? .drop : .keep
    }
}

/// The coach's flags for Coach Today and the day detail, and the "Mark handled" queue with its 5 s undo.
@MainActor
final class CoachFlagStore: ObservableObject {
    static let shared = CoachFlagStore()
    static let undoWindow: TimeInterval = 5
    static let maxAge: TimeInterval = 14 * 24 * 3600

    /// Queued resolves, persisted so a kill and relaunch keeps them.
    @Published private(set) var pending: [PendingFlagResolve] {
        didSet { defaults.set(try? JSONEncoder().encode(pending), forKey: key) }
    }
    /// The flag the "Marked handled · Undo" toast is for, while its undo window is open.
    @Published private(set) var toastFlagID: UUID?
    /// Athletes whose queued action the server refused because the link ended (UX spec A.1).
    @Published var failedAthletes: [UUID] = []
    /// Names of athletes the coach marked flags for on this run of the app, for that failure line. Memory only.
    var knownNames: [UUID: String] = [:]

    private let repository: any CoachFlagRepository
    private let defaults: UserDefaults
    private let key: String
    private let tracker: () -> any AnalyticsTracking
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var flushing = false
    /// Called after a resolve is queued, undone or answered, so Coach Today can rebuild.
    var onChange: (() -> Void)?

    init(
        repository: any CoachFlagRepository = SupabaseCoachFlagRepository(),
        defaults: UserDefaults = .standard,
        key: String = "coachV2.flagResolveOutbox.v1",
        tracker: @escaping () -> any AnalyticsTracking = { Analytics.shared },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.repository = repository
        self.defaults = defaults
        self.key = key
        self.tracker = tracker
        self.now = now
        self.sleep = sleep
        pending = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([PendingFlagResolve].self, from: $0) } ?? []
    }

    nonisolated deinit {}

    /// Open flags the coach has not just marked handled on this phone.
    func openFlags(_ flags: [CoachRunFlag]) -> [CoachRunFlag] {
        let queued = Set(pending.map(\.flagID))
        return flags.filter { $0.isOpen && !queued.contains($0.id) }
    }

    func isWaiting(_ flagID: UUID) -> Bool { pending.contains { $0.flagID == flagID } }

    /// Reads the coach's flags. Throws so Coach Today can show "Pain flags didn't load".
    func load(athleteIDs: [UUID]?, includeResolved: Bool = false) async throws -> [CoachRunFlag] {
        try await repository.flags(athleteIDs: athleteIDs, includeResolved: includeResolved)
    }

    /// "Mark handled": queued at once, sent after the undo window.
    func markHandled(_ flag: CoachRunFlag, coachID: UUID) {
        guard flag.isOpen, !isWaiting(flag.id) else { return }
        pending.append(PendingFlagResolve(
            flagID: flag.id, athleteID: flag.athleteID, coachID: coachID, flagCreatedAt: flag.createdAt, queuedAt: now()
        ))
        toastFlagID = flag.id
        onChange?()
        Task { [weak self, sleep] in
            await sleep(Self.undoWindow)
            await self?.windowClosed(flag.id, coachID: coachID)
        }
    }

    /// "Undo" on the toast. Only while the call has not left the phone.
    func undo(_ flagID: UUID) {
        guard pending.contains(where: { $0.flagID == flagID && now().timeIntervalSince($0.queuedAt) < Self.undoWindow }) else {
            return
        }
        pending.removeAll { $0.flagID == flagID }
        if toastFlagID == flagID { toastFlagID = nil }
        onChange?()
    }

    private func windowClosed(_ flagID: UUID, coachID: UUID) async {
        if toastFlagID == flagID { toastFlagID = nil }
        await flush(coachID: coachID)
    }

    /// Sends resolves whose undo window has passed. Stops at the first one that must wait.
    func flush(coachID: UUID) async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        let current = now()
        pending.removeAll { current.timeIntervalSince($0.queuedAt) > Self.maxAge }
        for item in pending where item.coachID == coachID {
            guard current.timeIntervalSince(item.queuedAt) >= Self.undoWindow, pending.contains(item) else { continue }
            do {
                let resolvedAt = try await repository.resolve(flagID: item.flagID) ?? now()
                pending.removeAll { $0.flagID == item.flagID }
                let minutes = max(0, Int(resolvedAt.timeIntervalSince(item.flagCreatedAt) / 60))
                CoachV2Analytics.track(.flagResolved(minutesOpen: minutes), to: tracker())
                onChange?()
            } catch {
                if error is CancellationError { return }
                switch CoachFlagFailure.classify(error) {
                case .keep:
                    return
                case .drop:
                    pending.removeAll { $0.flagID == item.flagID }
                    if !failedAthletes.contains(item.athleteID) { failedAthletes.append(item.athleteID) }
                    onChange?()
                }
            }
        }
    }
}
