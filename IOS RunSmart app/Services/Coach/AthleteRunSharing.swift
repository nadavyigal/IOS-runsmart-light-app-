import Combine
import Foundation
import Supabase

// Coach Experience v2, story C7.3: the athlete's effort (RPE) and run note are synced
// and shared with the coach. "Coach" means a HUMAN coach (Coach Mode), not the AI coach.
//
// Server side: supabase/migrations/20261121120000_athlete_run_sharing.sql. The server is
// the real gate (D7): every coach read checks coach_v2_sharing_allowed, and the writes
// refuse notes on runs completed before the ack and RPE older than the 14-day window.
//
// This file keeps the promise on the phone too: with v2 off, without an active link, or
// before the athlete accepts the v2 copy, nothing about effort or notes leaves the device.

extension Notification.Name {
    /// Posted after `ack_coach_consent(2)` succeeds (P9). Sharing refreshes at once.
    static let coachConsentV2Acked = Notification.Name("runsmart.coachConsentV2Acked")
}

enum AthleteRunSharingRPC {
    static let setRPE = "athlete_set_run_rpe"
    static let setNote = "athlete_set_run_note"
    static let setNoteHidden = "athlete_set_run_note_hidden"
    static let coachRunNotes = "coach_get_run_notes"
}

/// The server row's key, as the app upserts the run (`DBRunInsert`).
nonisolated struct RunShareKey: Codable, Hashable, Sendable {
    let sourceProvider: String
    let sourceActivityID: String

    init(sourceProvider: String, sourceActivityID: String) {
        self.sourceProvider = sourceProvider
        self.sourceActivityID = sourceActivityID
    }

    @MainActor
    init(run: RecordedRun) {
        let key = run.runSourceKey
        self.init(sourceProvider: key.sourceProvider, sourceActivityID: key.sourceActivityID)
    }
}

/// One change the athlete made. Only the latest change of each kind per run is kept.
nonisolated enum RunShareChange: Codable, Hashable, Sendable {
    case rpe(Int?)
    case note(String?)
    case noteHidden(Bool)

    enum Kind: String, Codable, Sendable {
        case rpe, note, noteHidden
    }

    var kind: Kind {
        switch self {
        case .rpe: .rpe
        case .note: .note
        case .noteHidden: .noteHidden
        }
    }
}

nonisolated struct PendingRunShare: Codable, Equatable, Sendable, Identifiable {
    /// Client id. A flush removes only this exact item, so a newer edit queued during
    /// the send is never lost.
    let id: UUID
    let ownerID: UUID
    let key: RunShareKey
    let change: RunShareChange
    let createdAt: Date
}

nonisolated enum RunShareWriteResult: String, Decodable, Sendable {
    case saved
    /// The run has no server row yet.
    case missing
}

/// What the outbox does after a failed write (v1.3 section 1.1, offline/outbox AC).
nonisolated enum RunShareFailure: Equatable, Sendable {
    /// Retry on the next foreground: offline, a server error, or `v2_unavailable`
    /// (kill switch on). No athlete data is dropped while the switch is on.
    case keep
    /// The server will never accept it: the link ended, no consent, a run before the
    /// ack, or invalid input.
    case drop

    static let dropTokens = [
        "link_inactive", "consent_required", "note_before_consent", "rpe_before_window",
        "bad_rpe", "note_too_long", "bad_hidden"
    ]

    static func classify(_ error: Error) -> RunShareFailure {
        let message = (error as? PostgrestError)?.message ?? String(describing: error)
        return dropTokens.contains { message.contains($0) } ? .drop : .keep
    }
}

nonisolated protocol AthleteRunSharingRepository: Sendable {
    func write(_ change: RunShareChange, key: RunShareKey) async throws -> RunShareWriteResult
    /// True when the signed-in athlete's run has a server row (owner RLS read).
    func hasServerRow(_ key: RunShareKey, ownerID: UUID) async throws -> Bool
}

nonisolated struct SupabaseAthleteRunSharingRepository: AthleteRunSharingRepository {
    private struct RPEParams: Encodable {
        let p_source_provider: String
        let p_source_activity_id: String
        let p_rpe: Int?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(p_source_provider, forKey: .p_source_provider)
            try container.encode(p_source_activity_id, forKey: .p_source_activity_id)
            try container.encode(p_rpe, forKey: .p_rpe)
        }

        enum CodingKeys: String, CodingKey { case p_source_provider, p_source_activity_id, p_rpe }
    }

    private struct NoteParams: Encodable {
        let p_source_provider: String
        let p_source_activity_id: String
        let p_note: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(p_source_provider, forKey: .p_source_provider)
            try container.encode(p_source_activity_id, forKey: .p_source_activity_id)
            try container.encode(p_note, forKey: .p_note)
        }

        enum CodingKeys: String, CodingKey { case p_source_provider, p_source_activity_id, p_note }
    }

    private struct HiddenParams: Encodable {
        let p_source_provider: String
        let p_source_activity_id: String
        let p_hidden: Bool
    }

    private struct RowID: Decodable { let id: Int64 }

    func write(_ change: RunShareChange, key: RunShareKey) async throws -> RunShareWriteResult {
        let client = SupabaseManager.client
        let raw: String
        switch change {
        case .rpe(let value):
            raw = try await client.rpc(AthleteRunSharingRPC.setRPE, params: RPEParams(
                p_source_provider: key.sourceProvider, p_source_activity_id: key.sourceActivityID, p_rpe: value
            )).execute().value
        case .note(let text):
            raw = try await client.rpc(AthleteRunSharingRPC.setNote, params: NoteParams(
                p_source_provider: key.sourceProvider, p_source_activity_id: key.sourceActivityID, p_note: text
            )).execute().value
        case .noteHidden(let hidden):
            raw = try await client.rpc(AthleteRunSharingRPC.setNoteHidden, params: HiddenParams(
                p_source_provider: key.sourceProvider, p_source_activity_id: key.sourceActivityID, p_hidden: hidden
            )).execute().value
        }
        return RunShareWriteResult(rawValue: raw) ?? .missing
    }

    func hasServerRow(_ key: RunShareKey, ownerID: UUID) async throws -> Bool {
        let ids = Array(Set([key.sourceActivityID, key.sourceActivityID.lowercased()]))
        let rows: [RowID] = try await SupabaseManager.client.from("runs").select("id")
            .eq("auth_user_id", value: ownerID.uuidString)
            .eq("source_provider", value: key.sourceProvider)
            .in("source_activity_id", values: ids)
            .limit(1).execute().value
        return !rows.isEmpty
    }
}

/// What the phone knows about sharing right now.
nonisolated struct RunSharingContext: Equatable, Sendable {
    var v2Enabled = false
    var userID: UUID?
    var linkID: UUID?
    var coachName: String?
    /// `my_coach_consent_status().sharing_active` for this link.
    var sharingActive = false
    /// When this phone first saw sharing active for this link. Never earlier than the
    /// server ack, so the note rule here is at least as strict as the server's.
    var sharingSince: Date?

    static let off = RunSharingContext()
}

/// Pure rules, unit tested. D7 plus C7.3 AC2.
nonisolated enum RunSharingPolicy {
    /// RPE from the 14 days before the ack is backfilled once (D7).
    static let rpeWindow: TimeInterval = 14 * 24 * 60 * 60
    /// A change whose run never gets a server row is dropped after this long.
    static let missingRowGiveUp: TimeInterval = 14 * 24 * 60 * 60

    static func isSharing(_ context: RunSharingContext) -> Bool {
        context.v2Enabled && context.userID != nil && context.linkID != nil
            && context.sharingActive && context.sharingSince != nil
    }

    /// Effort for this run reaches the coach.
    static func sharesRPE(runStartedAt: Date, context: RunSharingContext) -> Bool {
        guard isSharing(context), let since = context.sharingSince else { return false }
        return runStartedAt >= since.addingTimeInterval(-rpeWindow)
    }

    /// The note on this run reaches the coach. Notes on runs completed before the ack
    /// are never synced, even when edited later.
    static func sharesNote(runStartedAt: Date, context: RunSharingContext) -> Bool {
        guard isSharing(context), let since = context.sharingSince else { return false }
        return runStartedAt >= since
    }

    static func shouldSync(_ change: RunShareChange, runStartedAt: Date, context: RunSharingContext) -> Bool {
        switch change {
        case .rpe: sharesRPE(runStartedAt: runStartedAt, context: context)
        case .note: sharesNote(runStartedAt: runStartedAt, context: context)
        // A hide is a privacy action: sent whenever the note could have been shared.
        case .noteHidden: sharesNote(runStartedAt: runStartedAt, context: context)
        }
    }

    /// Runs the one-time backfill sends: RPE set, completed in the last 14 days.
    @MainActor
    static func backfillRuns(_ runs: [RecordedRun], now: Date) -> [RecordedRun] {
        runs.filter { $0.rpe != nil && $0.startedAt >= now.addingTimeInterval(-rpeWindow) && $0.startedAt <= now }
    }
}

/// Durable queue of sharing writes. Survives a kill and relaunch (UserDefaults), and
/// flushes in order. Idempotent: the server stores a value, not an increment, and only
/// the newest change of each kind per run is queued.
@MainActor
final class AthleteRunSharingOutbox: ObservableObject {
    private let defaults: UserDefaults
    private let key: String
    private var isFlushing = false

    @Published private(set) var pending: [PendingRunShare] {
        didSet { defaults.set(try? JSONEncoder().encode(pending), forKey: key) }
    }

    init(defaults: UserDefaults = .standard, key: String = "coachV2.runShareOutbox.v1") {
        self.defaults = defaults
        self.key = key
        pending = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([PendingRunShare].self, from: $0) } ?? []
    }

    nonisolated deinit {}

    func enqueue(_ item: PendingRunShare) {
        var queue = pending.filter {
            !($0.ownerID == item.ownerID && $0.key == item.key && $0.change.kind == item.change.kind)
        }
        queue.append(item)
        pending = queue
    }

    func isWaiting(ownerID: UUID, key: RunShareKey) -> Bool {
        pending.contains { $0.ownerID == ownerID && $0.key == key }
    }

    /// Counts from one flush. Items are per owner; after a link ends the server answers
    /// link_inactive and the item is dropped.
    struct FlushReport: Equatable {
        var saved = 0
        var dropped = 0
        var kept = 0
    }

    @discardableResult
    func flush(
        ownerID: UUID,
        repository: any AthleteRunSharingRepository,
        now: Date = Date(),
        canSend: (PendingRunShare) -> Bool
    ) async -> FlushReport {
        var report = FlushReport()
        guard !isFlushing else { return report }
        isFlushing = true
        defer { isFlushing = false }
        for item in pending where item.ownerID == ownerID {
            guard pending.contains(item), canSend(item) else {
                report.kept += 1
                continue
            }
            do {
                let result = try await repository.write(item.change, key: item.key)
                if result == .saved || now.timeIntervalSince(item.createdAt) > RunSharingPolicy.missingRowGiveUp {
                    remove(item)
                    if result == .saved { report.saved += 1 } else { report.dropped += 1 }
                } else {
                    report.kept += 1
                }
            } catch is CancellationError {
                report.kept += 1
                return report
            } catch {
                switch RunShareFailure.classify(error) {
                case .drop:
                    remove(item)
                    report.dropped += 1
                case .keep:
                    // Offline or v2_unavailable: the rest would fail the same way.
                    report.kept += 1
                    return report
                }
            }
        }
        return report
    }

    private func remove(_ item: PendingRunShare) {
        pending.removeAll { $0.id == item.id }
    }
}

/// Owns C7.3 on the athlete's phone. The app shell calls `refresh` on sign-in, when the
/// v2 gate or the link changes, and on every foreground. The run services call `record`
/// when the athlete sets effort, saves a note or toggles "Hide note from {Coach}".
@MainActor
final class AthleteRunSharingService: ObservableObject {
    static let shared = AthleteRunSharingService()

    @Published private(set) var context = RunSharingContext.off
    /// Runs confirmed to have a server row (C7.3 AC8).
    @Published private(set) var serverRows: Set<RunShareKey> = []
    @Published private(set) var hiddenNotes: Set<String>

    let outbox: AthleteRunSharingOutbox
    private let consent: any CoachConsentRepository
    private let repository: any AthleteRunSharingRepository
    private let defaults: UserDefaults
    private let analytics: () -> any AnalyticsTracking
    private let now: () -> Date

    private static let sinceKey = "coachV2.runSharingSince.v1"
    private static let backfillKey = "coachV2.rpeBackfillDone.v1"
    private static let hiddenKey = "coachV2.hiddenNotes.v1"

    init(
        consent: any CoachConsentRepository = SupabaseCoachConsentRepository(),
        repository: any AthleteRunSharingRepository = SupabaseAthleteRunSharingRepository(),
        outbox: AthleteRunSharingOutbox? = nil,
        defaults: UserDefaults = .standard,
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared },
        now: @escaping () -> Date = Date.init
    ) {
        self.consent = consent
        self.repository = repository
        self.outbox = outbox ?? AthleteRunSharingOutbox(defaults: defaults)
        self.defaults = defaults
        self.analytics = analytics
        self.now = now
        hiddenNotes = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    nonisolated deinit {}

    // MARK: Inputs

    /// With v2 off, signed out or unlinked, it makes no call and shares nothing.
    func refresh(v2Enabled: Bool, userID: UUID?, linkID: UUID?, coachName: String?, localRuns: [RecordedRun]) async {
        guard v2Enabled, let userID, let linkID else {
            context = RunSharingContext(v2Enabled: v2Enabled, userID: userID, linkID: linkID, coachName: coachName)
            return
        }
        var next = RunSharingContext(v2Enabled: true, userID: userID, linkID: linkID, coachName: coachName)
        do {
            if let status = try await consent.status(), status.linkID == linkID, status.sharingActive {
                next.sharingActive = true
                next.sharingSince = sharingSince(for: linkID) ?? recordSharingSince(linkID)
            }
        } catch {
            // Offline: keep the last answer for the same link, so queued changes still flush later.
            if context.userID == userID, context.linkID == linkID {
                next.sharingActive = context.sharingActive
                next.sharingSince = context.sharingSince
            }
        }
        context = next
        if RunSharingPolicy.isSharing(next) {
            backfillIfNeeded(linkID: linkID, ownerID: userID, localRuns: localRuns)
        }
        await flush()
    }

    /// Called after the local store saved the change.
    func record(_ change: RunShareChange, for run: RecordedRun) async {
        // Flag off: no event, no queue, no call (flag-off AC, C7.13 AC3).
        guard context.v2Enabled, context.userID != nil, context.linkID != nil else { return }
        let key = RunShareKey(run: run)
        if case .noteHidden(let hidden) = change {
            setLocalHidden(hidden, key: key)
        }
        let shared = RunSharingPolicy.shouldSync(change, runStartedAt: run.startedAt, context: context)
        switch change {
        case .rpe: track(.runRPESet(shared: shared))
        case .note: track(.runNoteSaved(shared: shared))
        case .noteHidden(let hidden): track(.runNoteHiddenToggled(hidden: hidden))
        }
        guard shared, let owner = context.userID else { return }
        outbox.enqueue(PendingRunShare(id: UUID(), ownerID: owner, key: key, change: change, createdAt: now()))
        await flush()
    }

    func flush() async {
        guard let owner = context.userID else { return }
        let sharing = RunSharingPolicy.isSharing(context)
        await outbox.flush(ownerID: owner, repository: repository, now: now()) { item in
            // Hides go out whenever this account is signed in; effort and notes only while sharing.
            if case .noteHidden = item.change { return true }
            return sharing
        }
    }

    // MARK: What P7 shows

    func sharesRPE(_ run: RecordedRun) -> Bool {
        RunSharingPolicy.sharesRPE(runStartedAt: run.startedAt, context: context) && serverRows.contains(RunShareKey(run: run))
    }

    func sharesNote(_ run: RecordedRun) -> Bool {
        RunSharingPolicy.sharesNote(runStartedAt: run.startedAt, context: context) && serverRows.contains(RunShareKey(run: run))
    }

    func isNoteHidden(_ run: RecordedRun) -> Bool {
        guard let owner = context.userID else { return false }
        return hiddenNotes.contains(Self.hiddenID(owner: owner, key: RunShareKey(run: run)))
    }

    func isWaiting(_ run: RecordedRun) -> Bool {
        guard let owner = context.userID else { return false }
        return outbox.isWaiting(ownerID: owner, key: RunShareKey(run: run))
    }

    /// Looks up the run's server row once, only while sharing. Offline it stays unknown,
    /// so the visibility line stays hidden.
    func resolveServerRow(for run: RecordedRun) async {
        guard RunSharingPolicy.isSharing(context), let owner = context.userID else { return }
        let key = RunShareKey(run: run)
        guard !serverRows.contains(key) else { return }
        if (try? await repository.hasServerRow(key, ownerID: owner)) == true, context.userID == owner {
            serverRows.insert(key)
        }
    }

    // MARK: Private

    private func backfillIfNeeded(linkID: UUID, ownerID: UUID, localRuns: [RecordedRun]) {
        var done = Set(defaults.stringArray(forKey: Self.backfillKey) ?? [])
        guard !done.contains(linkID.uuidString) else { return }
        let runs = RunSharingPolicy.backfillRuns(localRuns, now: now())
        for run in runs {
            outbox.enqueue(PendingRunShare(id: UUID(), ownerID: ownerID, key: RunShareKey(run: run),
                                           change: .rpe(run.rpe), createdAt: now()))
        }
        // The queue is durable and retries, so the job runs once per link.
        done.insert(linkID.uuidString)
        defaults.set(Array(done), forKey: Self.backfillKey)
        track(.rpeBackfillDone(count: runs.count))
    }

    private func sharingSince(for linkID: UUID) -> Date? {
        (defaults.dictionary(forKey: Self.sinceKey) as? [String: Date])?[linkID.uuidString]
    }

    private func recordSharingSince(_ linkID: UUID) -> Date {
        var all = defaults.dictionary(forKey: Self.sinceKey) as? [String: Date] ?? [:]
        let date = now()
        all[linkID.uuidString] = date
        defaults.set(all, forKey: Self.sinceKey)
        return date
    }

    private func setLocalHidden(_ hidden: Bool, key: RunShareKey) {
        guard let owner = context.userID else { return }
        let id = Self.hiddenID(owner: owner, key: key)
        if hidden { hiddenNotes.insert(id) } else { hiddenNotes.remove(id) }
        defaults.set(Array(hiddenNotes), forKey: Self.hiddenKey)
    }

    private static func hiddenID(owner: UUID, key: RunShareKey) -> String {
        "\(owner.uuidString).\(key.sourceProvider).\(key.sourceActivityID)"
    }

    private func track(_ event: CoachV2Analytics.Event) {
        CoachV2Analytics.track(event, to: analytics())
    }
}

// MARK: Coach side (C7.3 AC4)

/// Coach day-detail copy for shared effort and notes. The view wiring belongs to the
/// coach screens (lane B); these are the strings and the note fetch they use.
nonisolated enum CoachRunSharingCopy {
    /// "Effort 7/10". Nil when the athlete did not share effort.
    static func effort(_ rpe: Int?) -> String? {
        guard let rpe, (1...10).contains(rpe) else { return nil }
        return "Effort \(rpe)/10"
    }

    /// The note in quotes. The text keeps its own direction; the caller lays it out with
    /// `naturalTextDirection`.
    static func quotedNote(_ note: String) -> String {
        "\u{201C}\(note)\u{201D}"
    }

    /// The spec attribution (an em dash, then {Athlete}), with the name isolated (C7.15).
    static func attribution(athlete: String) -> String {
        BidiText.fill("\u{2014} {Athlete}", ["Athlete": athlete])
    }
}

nonisolated struct CoachRunNote: Decodable, Equatable, Sendable {
    let runID: Int
    let note: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case note = "athlete_note"
    }
}

nonisolated enum CoachRunNotesFetcher {
    private struct Params: Encodable {
        let p_run_ids: [Int]
    }

    /// Notes the coach may read. The server drops every id it must not answer for.
    static func notes(runIDs: [Int]) async throws -> [Int: String] {
        guard !runIDs.isEmpty else { return [:] }
        let rows: [CoachRunNote] = try await SupabaseManager.client
            .rpc(AthleteRunSharingRPC.coachRunNotes, params: Params(p_run_ids: Array(runIDs.prefix(500))))
            .execute()
            .value
        return Dictionary(rows.map { ($0.runID, $0.note) }, uniquingKeysWith: { _, latest in latest })
    }
}
