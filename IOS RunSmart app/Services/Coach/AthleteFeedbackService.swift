import Combine
import Foundation
import Supabase

// Story 3.2. The athlete reads the feedback a human coach wrote (Story 3.1). Notes are
// the coach's own words and are shown as written, never translated.

nonisolated enum AthleteFeedbackRPC {
    static let list = "my_coach_feedback"
    static let markRead = "mark_feedback_read"
    /// FR-18b: after this long without feedback, the run's line changes to "Shared with {Coach}".
    static let reviewWindow: TimeInterval = 72 * 3600
}

/// One note as the athlete receives it. `coachName` is stored with the note, so it still
/// shows correctly after the athlete leaves that coach.
nonisolated struct AthleteFeedbackNote: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let coachID: UUID
    let coachName: String
    let runID: Int64?
    /// The `runs` upsert key. The app matches a note to a local run with it.
    let runSourceProvider: String?
    let runSourceActivityID: String?
    let weekStart: String?
    let text: String
    let createdAt: Date
    let editedAt: Date?
    var readAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case coachID = "coach_id"
        case coachName = "coach_name"
        case runID = "run_id"
        case runSourceProvider = "run_source_provider"
        case runSourceActivityID = "run_source_activity_id"
        case weekStart = "week_start"
        case text
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case readAt = "read_at"
    }

    init(id: UUID, coachID: UUID, coachName: String, runID: Int64? = nil, runSourceProvider: String? = nil,
         runSourceActivityID: String? = nil, weekStart: String? = nil, text: String, createdAt: Date,
         editedAt: Date? = nil, readAt: Date? = nil) {
        self.id = id
        self.coachID = coachID
        self.coachName = coachName
        self.runID = runID
        self.runSourceProvider = runSourceProvider
        self.runSourceActivityID = runSourceActivityID
        self.weekStart = weekStart
        self.text = text
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.readAt = readAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        coachID = try c.decode(UUID.self, forKey: .coachID)
        coachName = try c.decode(String.self, forKey: .coachName)
        runID = try c.decodeIfPresent(Int64.self, forKey: .runID)
        runSourceProvider = try c.decodeIfPresent(String.self, forKey: .runSourceProvider)
        runSourceActivityID = try c.decodeIfPresent(String.self, forKey: .runSourceActivityID)
        weekStart = try c.decodeIfPresent(String.self, forKey: .weekStart)
        text = try c.decode(String.self, forKey: .text)
        createdAt = try AthleteFeedbackTimestamp.date(c.decode(String.self, forKey: .createdAt))
        editedAt = try c.decodeIfPresent(String.self, forKey: .editedAt).map(AthleteFeedbackTimestamp.date)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt).map(AthleteFeedbackTimestamp.date)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(coachID, forKey: .coachID)
        try c.encode(coachName, forKey: .coachName)
        try c.encodeIfPresent(runID, forKey: .runID)
        try c.encodeIfPresent(runSourceProvider, forKey: .runSourceProvider)
        try c.encodeIfPresent(runSourceActivityID, forKey: .runSourceActivityID)
        try c.encodeIfPresent(weekStart, forKey: .weekStart)
        try c.encode(text, forKey: .text)
        try c.encode(AthleteFeedbackTimestamp.iso(createdAt), forKey: .createdAt)
        try c.encodeIfPresent(editedAt.map(AthleteFeedbackTimestamp.iso), forKey: .editedAt)
        try c.encodeIfPresent(readAt.map(AthleteFeedbackTimestamp.iso), forKey: .readAt)
    }

    var isRunNote: Bool { runID != nil }

    /// True when this note is about `run`: same source provider and activity id as its `runs` row.
    func matches(_ key: RunSourceKey) -> Bool {
        runSourceProvider == key.sourceProvider && runSourceActivityID == key.sourceActivityID
    }

    /// The week's first day. The server sends a Gregorian SQL date, so it is read with a
    /// Gregorian calendar in `calendar`'s time zone, whatever calendar the device uses.
    func weekStartDate(calendar: Calendar) -> Date? {
        guard let weekStart else { return nil }
        let parts = weekStart.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

nonisolated enum AthleteFeedbackTimestamp {
    static func date(_ raw: String) throws -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad timestamp \(raw)"))
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

nonisolated protocol AthleteFeedbackFetching: Sendable {
    func list() async throws -> [AthleteFeedbackNote]
    /// Sets `read_at` once on the server. Returns the stored time.
    func markRead(id: UUID) async throws -> Date?
}

private nonisolated struct MarkFeedbackReadParams: Encodable, Sendable {
    let p_id: UUID
}

nonisolated struct SupabaseAthleteFeedbackService: AthleteFeedbackFetching {
    func list() async throws -> [AthleteFeedbackNote] {
        try await SupabaseManager.client.rpc(AthleteFeedbackRPC.list).execute().value
    }

    func markRead(id: UUID) async throws -> Date? {
        let raw: String? = try await SupabaseManager.client
            .rpc(AthleteFeedbackRPC.markRead, params: MarkFeedbackReadParams(p_id: id))
            .execute()
            .value
        return try raw.map(AthleteFeedbackTimestamp.date)
    }
}

/// In-memory stand-in for tests and previews.
nonisolated final class MockAthleteFeedbackService: AthleteFeedbackFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [AthleteFeedbackNote]
    var failure: Error?
    var now = Date()
    private(set) var markReadCalls: [UUID] = []

    init(rows: [AthleteFeedbackNote] = []) { self.rows = rows }

    func list() async throws -> [AthleteFeedbackNote] {
        try lock.withLock {
            if let failure { throw failure }
            return rows.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func markRead(id: UUID) async throws -> Date? {
        try lock.withLock {
            markReadCalls.append(id)
            if let failure { throw failure }
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
            if rows[index].readAt == nil { rows[index].readAt = now }
            return rows[index].readAt
        }
    }

    func set(_ rows: [AthleteFeedbackNote]) { lock.withLock { self.rows = rows } }
}

/// The last list, kept per signed-in athlete so notes show offline.
nonisolated struct AthleteFeedbackCache: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ userID: UUID) -> String { "athleteFeedback.cache.\(userID.uuidString)" }

    func load(userID: UUID) -> [AthleteFeedbackNote]? {
        guard let data = defaults.data(forKey: key(userID)) else { return nil }
        return try? JSONDecoder().decode([AthleteFeedbackNote].self, from: data)
    }

    func save(_ notes: [AthleteFeedbackNote], userID: UUID) {
        if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: key(userID)) }
    }
}

/// The line under a run while the coach hasn't written about it yet (FR-18b).
enum CoachReviewLine: Equatable {
    case willReview(coach: String)
    case shared(coach: String)

    var text: String {
        switch self {
        case .willReview(let coach): "\(coach) will review this run"
        case .shared(let coach): "Shared with \(coach)"
        }
    }

    /// Only for a run recorded in RunSmart while linked, and only until feedback on it exists.
    /// The 72-hour clock starts when the run ended and is read on the phone. No countdown.
    static func forRun(_ run: RecordedRun, link: CoachLink?, hasFeedback: Bool, now: Date) -> CoachReviewLine? {
        guard let link, !hasFeedback,
              run.source == .runSmart, run.providerActivityID == nil,
              run.endedAt > link.consentedAt else { return nil }
        return now.timeIntervalSince(run.endedAt) < AthleteFeedbackRPC.reviewWindow
            ? .willReview(coach: link.coachName)
            : .shared(coach: link.coachName)
    }
}

enum AthleteFeedbackCopy {
    static func loadFailed(_ coach: String) -> String { "Couldn't load \(coach)'s note." }
    static let edited = "Edited"
    static let feedbackRow = "Feedback"
}

/// The signed-in athlete's notes from coaches. Shared by run detail, the post-run summary,
/// the Plan week view, the Today badge, and My coach.
@MainActor
final class AthleteFeedbackStore: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    @Published private(set) var notes: [AthleteFeedbackNote] = []
    @Published private(set) var loadState: LoadState = .idle

    private let service: any AthleteFeedbackFetching
    private let cache: AthleteFeedbackCache
    private var userID: UUID?
    /// Bumped when the athlete changes. Work from an older session never applies.
    private var generation = 0
    /// Bumped on each load. Only the newest load's answer applies.
    private var loadRequest = 0
    /// Reads the server confirmed this session. A list fetched before a read was confirmed
    /// must not bring the badge back.
    private var confirmedReads: [UUID: Date] = [:]
    /// Reads shown on screen but not yet confirmed. Never written to the phone's cache.
    private var pendingReads: Set<UUID> = []
    /// Notes opened again while their first read was still pending: one retry if it fails.
    private var reopenedWhilePending: Set<UUID> = []

    init(service: any AthleteFeedbackFetching = SupabaseAthleteFeedbackService(),
         cache: AthleteFeedbackCache = AthleteFeedbackCache()) {
        self.service = service
        self.cache = cache
    }

    /// Call when the signed-in athlete changes. Shows that athlete's cached notes at once.
    func beginSession(userID: UUID?) {
        guard self.userID != userID else { return }
        generation += 1
        self.userID = userID
        confirmedReads = [:]
        pendingReads = []
        reopenedWhilePending = []
        notes = userID.flatMap { cache.load(userID: $0) } ?? []
        loadState = .idle
    }

    func load() async {
        guard let userID else { return }
        let session = generation
        loadRequest += 1
        let request = loadRequest
        loadState = .loading
        do {
            let rows = try await service.list()
            guard session == generation, request == loadRequest else { return }
            notes = rows.map(reconciled).sorted { $0.createdAt > $1.createdAt }
            persist(userID: userID)
            loadState = .loaded
        } catch {
            guard session == generation, request == loadRequest else { return }
            loadState = .failed
        }
    }

    /// Keeps a read the server already confirmed, or one still pending, over an older list.
    private func reconciled(_ note: AthleteFeedbackNote) -> AthleteFeedbackNote {
        guard note.readAt == nil else { return note }
        var copy = note
        if let confirmed = confirmedReads[note.id] {
            copy.readAt = confirmed
        } else if pendingReads.contains(note.id) {
            copy.readAt = notes.first { $0.id == note.id }?.readAt
        }
        return copy
    }

    func notes(for run: RecordedRun) -> [AthleteFeedbackNote] {
        let key = run.runSourceKey
        return notes.filter { $0.isRunNote && $0.matches(key) }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Week notes whose week starts inside this plan week.
    func notes(weekFrom start: Date, to end: Date, calendar: Calendar) -> [AthleteFeedbackNote] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        return notes.filter { note in
            guard let day = note.weekStartDate(calendar: calendar) else { return false }
            return day >= first && day <= last
        }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Week notes in `month` that no plan week card covers (for example, every workout of
    /// that week was removed). Plan shows them on their own so they stay readable.
    func uncoveredWeekNotes(month: Date, weeks: [(start: Date, end: Date)], calendar: Calendar) -> [AthleteFeedbackNote] {
        notes.filter { note in
            guard let day = note.weekStartDate(calendar: calendar),
                  calendar.isDate(day, equalTo: month, toGranularity: .month) else { return false }
            return !weeks.contains { day >= calendar.startOfDay(for: $0.start) && day <= calendar.startOfDay(for: $0.end) }
        }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Notes from the current coach since this link began. Notes from before leaving, or
    /// from an earlier link, never count as unread.
    func currentNotes(link: CoachLink?) -> [AthleteFeedbackNote] {
        guard let link else { return [] }
        return notes.filter { $0.coachID == link.coachID && $0.createdAt >= link.consentedAt }
    }

    /// The Today badge. Zero when not linked; clears only by reading.
    func unreadCount(link: CoachLink?) -> Int {
        currentNotes(link: link).filter { $0.readAt == nil }.count
    }

    func reviewLine(for run: RecordedRun, link: CoachLink?, now: Date = .now) -> CoachReviewLine? {
        CoachReviewLine.forRun(run, link: link, hasFeedback: !notes(for: run).isEmpty, now: now)
    }

    /// Records that the athlete opened these notes. Shown as read at once; the server sets
    /// `read_at` (SM-3/SM-7). A failed read shows as unread again and is retried the next time
    /// the note opens, or once right away if it was reopened while pending.
    func markRead(_ opened: [AthleteFeedbackNote], now: Date = .now) async {
        let session = generation
        for note in opened where pendingReads.contains(note.id) { reopenedWhilePending.insert(note.id) }
        let unread = opened.filter { note in
            !pendingReads.contains(note.id) && notes.first { $0.id == note.id }?.readAt == nil
        }
        guard !unread.isEmpty else { return }
        for note in unread {
            pendingReads.insert(note.id)
            setReadAt(now, for: note.id)
        }
        for note in unread {
            await confirmRead(note.id, session: session)
        }
    }

    private func confirmRead(_ id: UUID, session: Int) async {
        do {
            let stored = try await service.markRead(id: id)
            guard session == generation else { return }
            pendingReads.remove(id)
            reopenedWhilePending.remove(id)
            let readAt = stored ?? notes.first { $0.id == id }?.readAt ?? .now
            confirmedReads[id] = readAt
            setReadAt(readAt, for: id)
            if let userID { persist(userID: userID) }
        } catch {
            guard session == generation else { return }
            if reopenedWhilePending.remove(id) != nil {
                await confirmRead(id, session: session)
                return
            }
            pendingReads.remove(id)
            setReadAt(nil, for: id)
        }
    }

    private func setReadAt(_ date: Date?, for id: UUID) {
        if let index = notes.firstIndex(where: { $0.id == id }) { notes[index].readAt = date }
    }

    /// Saves the list with only server-confirmed reads, so an offline relaunch never shows a
    /// read the server didn't record.
    private func persist(userID: UUID) {
        let confirmedOnly = notes.map { note -> AthleteFeedbackNote in
            guard pendingReads.contains(note.id) else { return note }
            var copy = note
            copy.readAt = nil
            return copy
        }
        cache.save(confirmedOnly, userID: userID)
    }
}
