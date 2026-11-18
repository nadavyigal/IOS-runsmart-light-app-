import Foundation
import Supabase

// Story 3.1. A human coach writes feedback on one run or one week. The text is the
// coach's own words, stored and shown as written: never generated, never translated.

nonisolated enum CoachFeedbackRPC {
    static let add = "coach_add_feedback"
    static let edit = "coach_edit_feedback"
    static let table = "coach_feedback"
    static let maxLength = 2000
}

/// What a note is about: one run (`runs.id`, bigint) or one week (its first day, `yyyy-MM-dd`).
nonisolated enum CoachFeedbackTarget: Hashable, Codable, Sendable {
    case run(Int64)
    case week(String)

    var key: String {
        switch self {
        case .run(let id): "run-\(id)"
        case .week(let start): "week-\(start)"
        }
    }
}

nonisolated struct CoachFeedback: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let athleteID: UUID
    let runID: Int64?
    let weekStart: String?
    let text: String
    let createdAt: Date
    let editedAt: Date?

    var target: CoachFeedbackTarget? {
        if let runID { return .run(runID) }
        if let weekStart { return .week(weekStart) }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case athleteID = "athlete_id"
        case runID = "run_id"
        case weekStart = "week_start"
        case text
        case createdAt = "created_at"
        case editedAt = "edited_at"
    }

    init(id: UUID, athleteID: UUID, target: CoachFeedbackTarget, text: String, createdAt: Date, editedAt: Date? = nil) {
        self.id = id
        self.athleteID = athleteID
        switch target {
        case .run(let run): runID = run; weekStart = nil
        case .week(let start): runID = nil; weekStart = start
        }
        self.text = text
        self.createdAt = createdAt
        self.editedAt = editedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        athleteID = try c.decode(UUID.self, forKey: .athleteID)
        runID = try c.decodeIfPresent(Int64.self, forKey: .runID)
        weekStart = try c.decodeIfPresent(String.self, forKey: .weekStart)
        text = try c.decode(String.self, forKey: .text)
        createdAt = try Self.date(c.decode(String.self, forKey: .createdAt), key: .createdAt, in: c)
        editedAt = try c.decodeIfPresent(String.self, forKey: .editedAt).map { try Self.date($0, key: .editedAt, in: c) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(athleteID, forKey: .athleteID)
        try c.encodeIfPresent(runID, forKey: .runID)
        try c.encodeIfPresent(weekStart, forKey: .weekStart)
        try c.encode(text, forKey: .text)
        try c.encode(Self.iso(createdAt), forKey: .createdAt)
        try c.encodeIfPresent(editedAt.map(Self.iso), forKey: .editedAt)
    }

    private static func date(_ raw: String, key: CodingKeys, in c: KeyedDecodingContainer<CodingKeys>) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return date }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Bad timestamp \(raw)")
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum CoachFeedbackSession {
    /// The signed-in user, who is the coach on these screens.
    static func currentCoachID() -> UUID? { SupabaseManager.client.auth.currentUser?.id }
}

nonisolated enum CoachFeedbackError: Error, Equatable {
    /// The link is revoked or missing (`not_linked` from the RPC).
    case notLinked
    /// Network or server trouble. The note is kept on the phone and retried.
    case notSent
    /// The server will never accept this exact request (the run is gone, the text is empty or
    /// too long, the note isn't this coach's). It is not retried; the text stays on the phone.
    case rejected

    /// SQLSTATEs the feedback RPCs raise for a request that can't succeed on retry.
    static let permanentCodes: Set<String> = ["22023", "P0002", "23505", "23514"]

    static func map(_ error: Error) -> CoachFeedbackError {
        if let known = error as? CoachFeedbackError { return known }
        if let postgrest = error as? PostgrestError {
            if postgrest.message == "not_linked" { return .notLinked }
            if let code = postgrest.code, permanentCodes.contains(code) { return .rejected }
        }
        return .notSent
    }
}

nonisolated protocol CoachFeedbackServing: Sendable {
    /// `id` is generated on the phone so a retried send never stores the note twice.
    func add(id: UUID, athleteID: UUID, target: CoachFeedbackTarget, text: String) async throws -> CoachFeedback
    func edit(id: UUID, text: String) async throws -> CoachFeedback
    /// The coach's notes for one athlete. RLS returns nothing once the link is revoked.
    func list(athleteID: UUID) async throws -> [CoachFeedback]
}

private nonisolated struct CoachAddFeedbackParams: Encodable, Sendable {
    let p_athlete: UUID
    let p_run: Int64?
    let p_week_start: String?
    let p_text: String
    let p_id: UUID

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_athlete, forKey: .p_athlete)
        // Always send both keys, null included, so PostgREST picks the 5-argument function.
        try c.encode(p_run, forKey: .p_run)
        try c.encode(p_week_start, forKey: .p_week_start)
        try c.encode(p_text, forKey: .p_text)
        try c.encode(p_id, forKey: .p_id)
    }

    enum CodingKeys: String, CodingKey { case p_athlete, p_run, p_week_start, p_text, p_id }
}

private nonisolated struct CoachEditFeedbackParams: Encodable, Sendable {
    let p_id: UUID
    let p_text: String
}

nonisolated struct SupabaseCoachFeedbackService: CoachFeedbackServing {
    func add(id: UUID, athleteID: UUID, target: CoachFeedbackTarget, text: String) async throws -> CoachFeedback {
        var run: Int64?
        var week: String?
        switch target {
        case .run(let value): run = value
        case .week(let value): week = value
        }
        let rows: [CoachFeedback] = try await SupabaseManager.client
            .rpc(CoachFeedbackRPC.add, params: CoachAddFeedbackParams(
                p_athlete: athleteID, p_run: run, p_week_start: week, p_text: text, p_id: id
            ))
            .execute()
            .value
        guard let row = rows.first else { throw CoachFeedbackError.notSent }
        return row
    }

    func edit(id: UUID, text: String) async throws -> CoachFeedback {
        let rows: [CoachFeedback] = try await SupabaseManager.client
            .rpc(CoachFeedbackRPC.edit, params: CoachEditFeedbackParams(p_id: id, p_text: text))
            .execute()
            .value
        guard let row = rows.first else { throw CoachFeedbackError.notSent }
        return row
    }

    func list(athleteID: UUID) async throws -> [CoachFeedback] {
        try await SupabaseManager.client
            .from(CoachFeedbackRPC.table)
            .select("id,athlete_id,run_id,week_start,text,created_at,edited_at")
            .eq("athlete_id", value: athleteID)
            .order("created_at", ascending: true)
            .execute()
            .value
    }
}

/// In-memory stand-in for tests and previews.
nonisolated final class MockCoachFeedbackService: CoachFeedbackServing, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [CoachFeedback] = []
    var failure: CoachFeedbackError?
    private(set) var addCalls = 0
    var now = Date()

    init(rows: [CoachFeedback] = []) { self.rows = rows }

    func add(id: UUID, athleteID: UUID, target: CoachFeedbackTarget, text: String) async throws -> CoachFeedback {
        try lock.withLock {
            addCalls += 1
            if let failure { throw failure }
            if let existing = rows.first(where: { $0.id == id }) { return existing }
            let row = CoachFeedback(id: id, athleteID: athleteID, target: target,
                                    text: text.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: now)
            rows.append(row)
            return row
        }
    }

    func edit(id: UUID, text: String) async throws -> CoachFeedback {
        try lock.withLock {
            if let failure { throw failure }
            guard let index = rows.firstIndex(where: { $0.id == id }), let target = rows[index].target else {
                throw CoachFeedbackError.notSent
            }
            let old = rows[index]
            rows[index] = CoachFeedback(id: id, athleteID: old.athleteID, target: target,
                                        text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                        createdAt: old.createdAt, editedAt: now)
            return rows[index]
        }
    }

    func list(athleteID: UUID) async throws -> [CoachFeedback] {
        try lock.withLock {
            if let failure { throw failure }
            return rows.filter { $0.athleteID == athleteID }
        }
    }

    var stored: [CoachFeedback] { lock.withLock { rows } }
}

/// Unsent text, kept on this phone per coach, athlete, and run or week. The coach is part of
/// the key, so a different coach signed in on the same phone never sees another coach's draft.
nonisolated struct CoachFeedbackDraftStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ coachID: UUID, _ athleteID: UUID, _ scope: String) -> String {
        "coachFeedback.draft.v2.\(coachID.uuidString).\(athleteID.uuidString).\(scope)"
    }

    /// `scope` is a target's `key` for a new note, or `edit-<note id>` for an edit in progress.
    func draft(coachID: UUID, athleteID: UUID, scope: String) -> String? {
        defaults.string(forKey: key(coachID, athleteID, scope))
    }

    func save(_ text: String, coachID: UUID, athleteID: UUID, scope: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clear(coachID: coachID, athleteID: athleteID, scope: scope)
        } else {
            defaults.set(text, forKey: key(coachID, athleteID, scope))
        }
    }

    func clear(coachID: UUID, athleteID: UUID, scope: String) {
        defaults.removeObject(forKey: key(coachID, athleteID, scope))
    }

    /// Clears the draft only if it still holds `text`, so a newer revision typed meanwhile survives.
    func clear(coachID: UUID, athleteID: UUID, scope: String, ifText text: String) {
        guard let current = draft(coachID: coachID, athleteID: athleteID, scope: scope),
              CoachFeedbackText.trimmed(current) == CoachFeedbackText.trimmed(text) else { return }
        clear(coachID: coachID, athleteID: athleteID, scope: scope)
    }
}

/// A note that failed to send. Feedback is the one coach action that queues offline.
nonisolated struct PendingCoachFeedback: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case add, edit }
    let id: UUID
    /// The signed-in coach who wrote it. Only that coach's session ever sends it.
    let coachID: UUID
    let athleteID: UUID
    let target: CoachFeedbackTarget
    let text: String
    let kind: Kind

    var draftScope: String { kind == .edit ? "edit-\(id.uuidString)" : target.key }
}

/// What happened to one send.
enum CoachFeedbackSendOutcome: Equatable, Sendable {
    case stored(CoachFeedback)
    case failed(CoachFeedbackError)
    /// Not sent: the queue entry was gone or replaced, or another coach is signed in.
    case skipped
}

struct CoachFeedbackFlushResult: Equatable {
    var stored: [CoachFeedback] = []
    /// Athletes whose link turned out revoked while sending.
    var revokedAthletes: Set<UUID> = []
}

/// The queue lives in UserDefaults so it survives a relaunch. Retries reuse the note's id,
/// so a send that reached the server before the connection dropped is not stored twice.
///
/// Every send, from the composer or from a reconnect, runs through `serialized`, one at a
/// time. So a queued replay and a foreground save of the same note never overlap, and each
/// send checks, right before it goes, that its queue entry is unchanged and that its coach
/// is still the one signed in.
@MainActor
final class CoachFeedbackOutbox {
    static let shared = CoachFeedbackOutbox()
    private let defaults: UserDefaults
    private let key = "coachFeedback.outbox.v2"
    private let sessionCoachID: () -> UUID?
    private var tail: Task<Void, Never>?

    init(defaults: UserDefaults = .standard,
         sessionCoachID: @escaping () -> UUID? = CoachFeedbackSession.currentCoachID) {
        self.defaults = defaults
        self.sessionCoachID = sessionCoachID
    }

    var pending: [PendingCoachFeedback] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingCoachFeedback].self, from: data)) ?? []
    }

    func enqueue(_ item: PendingCoachFeedback) {
        var items = pending.filter { $0.id != item.id }
        items.append(item)
        save(items)
    }

    /// Removes every queued version of a note (a newer foreground result supersedes them).
    func remove(id: UUID) { save(pending.filter { $0.id != id }) }

    /// Removes only this exact entry, so a newer version queued meanwhile stays scheduled.
    func remove(exactly item: PendingCoachFeedback) { save(pending.filter { $0 != item }) }

    /// The id of a queued new note, so a reopened draft keeps the same id as its queued copy.
    func pendingID(coachID: UUID, athleteID: UUID, target: CoachFeedbackTarget) -> UUID? {
        pending.last { $0.kind == .add && $0.coachID == coachID && $0.athleteID == athleteID && $0.target == target }?.id
    }

    private var drafts: CoachFeedbackDraftStore { CoachFeedbackDraftStore(defaults: defaults) }

    /// Runs `operation` after every earlier send has finished.
    private func serialized<T: Sendable>(_ operation: @escaping @MainActor () async -> T) async -> T {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    /// One request. If an add finds its id already stored with older text (an earlier send that
    /// reached the server), the newer text is saved as an edit instead of being dropped.
    private func deliver(_ item: PendingCoachFeedback, using service: any CoachFeedbackServing) async throws -> CoachFeedback {
        switch item.kind {
        case .add:
            let stored = try await service.add(id: item.id, athleteID: item.athleteID, target: item.target, text: item.text)
            return stored.text == item.text ? stored : try await service.edit(id: item.id, text: item.text)
        case .edit:
            return try await service.edit(id: item.id, text: item.text)
        }
    }

    /// The composer's Send. Queues the note when the network fails.
    func send(_ item: PendingCoachFeedback, using service: any CoachFeedbackServing) async -> CoachFeedbackSendOutcome {
        await serialized { [self] in
            guard sessionCoachID() == item.coachID else { return .skipped }
            do {
                let row = try await deliver(item, using: service)
                remove(id: item.id)
                drafts.clear(coachID: item.coachID, athleteID: item.athleteID, scope: item.draftScope, ifText: item.text)
                return .stored(row)
            } catch {
                let failure = CoachFeedbackError.map(error)
                switch failure {
                case .notLinked:
                    remove(id: item.id)
                    drafts.clear(coachID: item.coachID, athleteID: item.athleteID, scope: item.draftScope)
                case .notSent:
                    enqueue(item)
                case .rejected:
                    remove(id: item.id)
                }
                return .failed(failure)
            }
        }
    }

    /// Sends the signed-in coach's queued notes once, in order. It stops if the signed-in coach
    /// changes, leaving the rest queued for their own coach. A stored note clears its draft only
    /// if the draft still holds the sent text. Revoked and rejected notes leave the queue.
    @discardableResult
    func flush(using service: any CoachFeedbackServing, coachID: UUID) async -> CoachFeedbackFlushResult {
        var result = CoachFeedbackFlushResult()
        for item in pending where item.coachID == coachID {
            let outcome: CoachFeedbackSendOutcome? = await serialized { [self] in
                guard sessionCoachID() == coachID else { return nil }
                // Discarded, sent, or replaced while earlier items were sending.
                guard pending.contains(item) else { return .skipped }
                do {
                    let row = try await deliver(item, using: service)
                    remove(exactly: item)
                    drafts.clear(coachID: item.coachID, athleteID: item.athleteID, scope: item.draftScope, ifText: item.text)
                    return .stored(row)
                } catch {
                    let failure = CoachFeedbackError.map(error)
                    switch failure {
                    case .notLinked:
                        remove(exactly: item)
                        drafts.clear(coachID: item.coachID, athleteID: item.athleteID, scope: item.draftScope)
                    case .rejected:
                        // Never retried; the draft keeps the text so the coach can fix it.
                        remove(exactly: item)
                    case .notSent:
                        break
                    }
                    return .failed(failure)
                }
            }
            guard let outcome else { break }
            switch outcome {
            case .stored(let row): result.stored.append(row)
            case .failed(.notLinked): result.revokedAthletes.insert(item.athleteID)
            default: break
            }
        }
        return result
    }

    private func save(_ items: [PendingCoachFeedback]) {
        if items.isEmpty {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}

nonisolated enum CoachFeedbackText {
    static let chips = [
        "Great job getting out there.",
        "Nice steady effort.",
        "Good pacing, easy runs should feel easy.",
        "Strong finish.",
        "Shorter week is fine, rest is training.",
        "See you at Saturday's run."
    ]

    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func canSend(_ text: String) -> Bool {
        let value = trimmed(text)
        return !value.isEmpty && value.count <= CoachFeedbackRPC.maxLength
    }

    /// Inserts a chip at the cursor (replacing any selected text) with a space on each side
    /// where needed. Returns the new text and the cursor after the inserted chip.
    static func insert(_ chip: String, into text: String, at selection: NSRange) -> (text: String, cursor: NSRange) {
        let ns = text as NSString
        let range = NSRange(location: min(max(selection.location, 0), ns.length),
                            length: max(0, min(selection.length, ns.length - min(max(selection.location, 0), ns.length))))
        let before = ns.substring(to: range.location)
        let after = ns.substring(from: range.location + range.length)
        let lead = before.isEmpty || before.last?.isWhitespace == true ? "" : " "
        let trail = after.isEmpty || after.first?.isWhitespace == true ? "" : " "
        let inserted = lead + chip + trail
        let result = before + inserted + after
        let cursor = (before as NSString).length + (lead + chip as NSString).length
        return (result, NSRange(location: cursor, length: 0))
    }

    /// Paragraph direction from the first strong character (Unicode bidi rule P2).
    /// Hebrew and Arabic start RTL; Latin starts LTR; a paragraph with neither follows LTR.
    static func isRightToLeft(_ paragraph: String) -> Bool {
        for scalar in paragraph.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
            default:
                if scalar.properties.isAlphabetic { return false }
            }
        }
        return false
    }

    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
    }
}
