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

nonisolated enum CoachFeedbackError: Error, Equatable {
    /// The link is revoked or missing (`not_linked` from the RPC).
    case notLinked
    /// Network or server trouble. The note is kept on the phone and retried.
    case notSent

    static func map(_ error: Error) -> CoachFeedbackError {
        if let known = error as? CoachFeedbackError { return known }
        if let postgrest = error as? PostgrestError, postgrest.message == "not_linked" { return .notLinked }
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

/// Unsent text, kept on this phone per athlete and run or week.
nonisolated struct CoachFeedbackDraftStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ athleteID: UUID, _ scope: String) -> String {
        "coachFeedback.draft.\(athleteID.uuidString).\(scope)"
    }

    /// `scope` is a target's `key` for a new note, or `edit-<note id>` for an edit in progress.
    func draft(athleteID: UUID, scope: String) -> String? {
        defaults.string(forKey: key(athleteID, scope))
    }

    func save(_ text: String, athleteID: UUID, scope: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clear(athleteID: athleteID, scope: scope)
        } else {
            defaults.set(text, forKey: key(athleteID, scope))
        }
    }

    func clear(athleteID: UUID, scope: String) {
        defaults.removeObject(forKey: key(athleteID, scope))
    }

    func draft(athleteID: UUID, target: CoachFeedbackTarget) -> String? { draft(athleteID: athleteID, scope: target.key) }
    func save(_ text: String, athleteID: UUID, target: CoachFeedbackTarget) { save(text, athleteID: athleteID, scope: target.key) }
    func clear(athleteID: UUID, target: CoachFeedbackTarget) { clear(athleteID: athleteID, scope: target.key) }
}

/// A note that failed to send. Feedback is the one coach action that queues offline.
nonisolated struct PendingCoachFeedback: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case add, edit }
    let id: UUID
    let athleteID: UUID
    let target: CoachFeedbackTarget
    let text: String
    let kind: Kind
}

/// The queue lives in UserDefaults so it survives a relaunch. Retries reuse the note's id,
/// so a send that reached the server before the connection dropped is not stored twice.
@MainActor
final class CoachFeedbackOutbox {
    static let shared = CoachFeedbackOutbox()
    private let defaults: UserDefaults
    private let key = "coachFeedback.outbox"
    private var flushing = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var pending: [PendingCoachFeedback] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PendingCoachFeedback].self, from: data)) ?? []
    }

    func enqueue(_ item: PendingCoachFeedback) {
        var items = pending.filter { $0.id != item.id }
        items.append(item)
        save(items)
    }

    func remove(id: UUID) { save(pending.filter { $0.id != id }) }

    /// Sends every queued note once. Sent notes and notes for a revoked link leave the
    /// queue; the rest stay for the next reconnect. Returns the notes that were stored.
    @discardableResult
    func flush(using service: any CoachFeedbackServing) async -> [CoachFeedback] {
        guard !flushing else { return [] }
        flushing = true
        defer { flushing = false }
        var stored: [CoachFeedback] = []
        for item in pending {
            do {
                let row: CoachFeedback
                if item.kind == .add {
                    row = try await service.add(id: item.id, athleteID: item.athleteID, target: item.target, text: item.text)
                } else {
                    row = try await service.edit(id: item.id, text: item.text)
                }
                stored.append(row)
                remove(id: item.id)
            } catch {
                if CoachFeedbackError.map(error) == .notLinked { remove(id: item.id) }
            }
        }
        return stored
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
