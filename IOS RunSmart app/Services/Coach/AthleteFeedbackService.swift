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
    enum Kind: String, Codable, Sendable { case note, welcome }

    let id: UUID
    let kind: Kind
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
        case id, kind
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
         editedAt: Date? = nil, readAt: Date? = nil, kind: Kind = .note) {
        self.id = id
        self.kind = kind
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
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .note
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
        try c.encode(kind, forKey: .kind)
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

    /// True for `run` or for any copy merged into it (Activity shows one run per activity).
    func matches(_ run: RecordedRun) -> Bool {
        run.feedbackSourceKeys.contains(where: matches)
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

    func hasClaimedWelcome(userID: UUID, linkID: UUID) -> Bool {
        defaults.bool(forKey: "\(key(userID)).welcome.\(linkID)")
    }

    func recordWelcomeClaim(userID: UUID, linkID: UUID) {
        defaults.set(true, forKey: "\(key(userID)).welcome.\(linkID)")
    }
}

extension RecordedRun {
    /// This run's `runs` key plus those of copies merged into it.
    var feedbackSourceKeys: [RunSourceKey] {
        [runSourceKey] + (mergedSourceKeys ?? [])
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
    private let welcomeService: any CoachWelcomeServing
    private var claimsInFlight: Set<UUID> = []
    /// The signed-in account. A list is fetched and saved only while it matches the session.
    private let currentUserID: () -> UUID?
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
         cache: AthleteFeedbackCache = AthleteFeedbackCache(),
         welcomeService: any CoachWelcomeServing = SupabaseCoachWelcomeService(),
         currentUserID: @escaping () -> UUID? = CoachFeedbackSession.currentCoachID) {
        self.service = service
        self.cache = cache
        self.welcomeService = welcomeService
        self.currentUserID = currentUserID
    }

    /// Call when the signed-in athlete changes. Shows that athlete's cached notes at once.
    func beginSession(userID: UUID?) {
        guard self.userID != userID else { return }
        generation += 1
        claimsInFlight = []
        self.userID = userID
        confirmedReads = [:]
        pendingReads = []
        reopenedWhilePending = []
        notes = userID.flatMap { cache.load(userID: $0) } ?? []
        loadState = .idle
    }

    /// Called from Today. A successful empty claim also counts, but transport failures can retry.
    func claimWelcome(for link: CoachLink, refreshIfClaimed: Bool = false) async {
        guard let userID, currentUserID() == userID else { return }
        if cache.hasClaimedWelcome(userID: userID, linkID: link.id) {
            if refreshIfClaimed { await load() }
            return
        }
        guard claimsInFlight.insert(link.id).inserted else { return }
        let session = generation
        // Claiming changes the link on the server. Let the refresh finish if Today disappears.
        await Task { await performWelcomeClaim(for: link, userID: userID, session: session) }.value
    }

    private func performWelcomeClaim(for link: CoachLink, userID: UUID, session: Int) async {
        defer {
            if session == generation { claimsInFlight.remove(link.id) }
        }
        guard session == generation, currentUserID() == userID else { return }
        do {
            try await welcomeService.claim()
            guard session == generation, currentUserID() == userID else { return }
            cache.recordWelcomeClaim(userID: userID, linkID: link.id)
            await load()
        } catch {
            guard session == generation, currentUserID() == userID, !Task.isCancelled else { return }
            loadState = .failed
        }
    }

    func load() async {
        // The request runs as whoever is signed in. Only fetch, and only keep the answer,
        // while that account is this store's athlete, so it is never saved under another one.
        guard let userID, currentUserID() == userID else { return }
        let session = generation
        loadRequest += 1
        let request = loadRequest
        loadState = .loading
        do {
            let rows = try await service.list()
            guard session == generation, request == loadRequest, currentUserID() == userID else { return }
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
        // A welcome row is reused when an athlete rejoins; a read from before it was rewritten no longer counts.
        if let confirmed = confirmedReads[note.id], confirmed >= note.createdAt {
            copy.readAt = confirmed
        } else if pendingReads.contains(note.id) {
            copy.readAt = notes.first { $0.id == note.id }?.readAt
        }
        return copy
    }

    func notes(for run: RecordedRun) -> [AthleteFeedbackNote] {
        notes.filter { $0.isRunNote && $0.matches(run) }.sorted { $0.createdAt < $1.createdAt }
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
        // Its own task, so closing the screen (which cancels the view's task) can't cancel
        // the read or its retry.
        let work = Task { @MainActor in
            for note in unread {
                // Stop if the athlete changed: never send reads for an old session.
                guard session == generation else { return }
                await confirmRead(note.id, session: session)
            }
        }
        await work.value
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

// MARK: - C7.7 Athlete replies to a coach note (one level)
//
// Server: supabase/migrations/20261121180000_coach_feedback_replies.sql (M4). A reply is the
// athlete's own words; the server shares it with the coach only while coach_v2_sharing_allowed
// holds. On the phone, Reply shows only while C7.3's sharing context is sharing and the note is
// from the coach of the current link. With Coach v2 off nothing here renders or calls the server.

nonisolated enum FeedbackReplyRPC {
    static let reply = "athlete_reply_to_feedback"
    static let mine = "my_feedback_replies"
    static let coachReplies = "coach_get_feedback_replies"
    static let coachMarkRead = "coach_mark_reply_read"
}

/// Fixed strings (UX spec C.5 P6, C.6 P6, C.7 item 8). Names are direction-isolated (C7.15).
nonisolated enum FeedbackReplyCopy {
    static let limit = 1000
    /// The counter shows from this many characters (UX spec C.5 P6).
    static let counterFrom = 900
    static let reply = "Reply"
    static let send = "Send"
    static let sent = "Sent"
    static let waiting = "Waiting to send"
    static let couldNotSend = "Couldn't send. We'll try again."
    static let tooLong = "Keep replies under 1000 characters"

    static func placeholder(coach: String) -> String { BidiText.fill("Reply to {Coach}…", ["Coach": coach]) }
    static func composerLabel(coach: String) -> String { BidiText.fill("Reply to {Coach}", ["Coach": coach]) }
    /// C7.7 AC7: the link ended before the outbox flushed.
    static func notSent(coach: String) -> String {
        BidiText.fill("You're no longer linked to {Coach}, so this reply wasn't sent.", ["Coach": coach])
    }
    static func counter(_ count: Int) -> String { "\(count)/\(limit)" }
    /// "You · 14:32" under the athlete's own reply.
    static func you(_ time: String) -> String { "You · \(BidiText.isolate(time))" }
    /// "{Athlete} · 14:32" under a reply on the coach side.
    static func athlete(_ name: String, time: String) -> String {
        BidiText.fill("{Athlete} · ", ["Athlete": name]) + BidiText.isolate(time)
    }
}

/// "14:32" for today, "12 Nov" for an earlier day.
nonisolated enum FeedbackReplyFormat {
    static func time(_ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, inSameDayAs: now) ? "jmm" : "dMMM")
        return formatter.string(from: date)
    }
}

/// Which kind of note a reply answers. Analytics only (v1.3 section 3.8: enums, never text).
nonisolated enum FeedbackReplyTarget: String, Codable, Sendable {
    case run, week, welcome

    init(note: AthleteFeedbackNote) {
        if note.kind == .welcome { self = .welcome } else { self = note.isRunNote ? .run : .week }
    }
}

/// Pure rules, unit tested.
nonisolated enum FeedbackReplyPolicy {
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Server length of what would be sent (Postgres `char_length` on the trimmed text).
    static func length(_ text: String) -> Int { BidiText.serverLength(trimmed(text)) }
    static func showsCounter(_ text: String) -> Bool { length(text) >= FeedbackReplyCopy.counterFrom }
    /// C7.7 AC2: over 1000 the counter turns to the error and Send is disabled.
    static func isTooLong(_ text: String) -> Bool { length(text) > FeedbackReplyCopy.limit }
    static func canSend(_ text: String) -> Bool { length(text) > 0 && !isTooLong(text) }

    /// Reply shows only while sharing, for a note or the welcome from the coach of the current link
    /// (C7.7 AC6: hidden after the link ends; AC8: nothing else takes a reply).
    static func canReply(note: AthleteFeedbackNote, link: CoachLink?, context: RunSharingContext) -> Bool {
        guard RunSharingPolicy.isSharing(context), let link, context.linkID == link.id,
              note.coachID == link.coachID else { return false }
        switch note.kind {
        case .note, .welcome: return true
        }
    }
}

/// A reply this phone sent (or is sending), or one read back from the server.
nonisolated struct AthleteFeedbackReply: Codable, Equatable, Identifiable, Sendable {
    /// Client id, sent as `p_id`: two flushes store one row.
    let id: UUID
    let ownerID: UUID
    let feedbackID: UUID
    let text: String
    let createdAt: Date
    var sent: Bool
    /// The last attempt failed with something other than no connection.
    var retrying = false
    /// For the link-gone line and analytics. Nil on rows read back from the server.
    var coachName: String?
    var target: FeedbackReplyTarget?

    enum Status: Equatable { case waiting, retrying, sent }

    var status: Status { sent ? .sent : (retrying ? .retrying : .waiting) }
}

nonisolated struct PendingFeedbackReply: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let replyID: UUID
    let ownerID: UUID
    let createdAt: Date
}

/// What the outbox does after a failed send (v1.3 section 1.1, M4 header).
nonisolated enum FeedbackReplyFailure: Equatable, Sendable {
    /// No connection: keep it, "Waiting to send".
    case offline
    /// `v2_unavailable` (kill switch) or a server error: keep it, "Couldn't send. We'll try again."
    case keep
    /// The link ended: drop it and tell the athlete once (AC7).
    case linkGone
    /// The server will never take it: drop it.
    case drop

    static let dropTokens = [
        "consent_required", "bad_reply_id", "reply_empty", "reply_too_long",
        "reply_to_reply", "reply_not_allowed", "feedback_not_found",
    ]

    static func classify(_ error: Error) -> FeedbackReplyFailure {
        if error is URLError { return .offline }
        let message = (error as? PostgrestError)?.message ?? String(describing: error)
        if message.contains("v2_unavailable") { return .keep }
        if message.contains("link_inactive") { return .linkGone }
        return dropTokens.contains { message.contains($0) } ? .drop : .keep
    }
}

/// One row of `my_feedback_replies()`.
nonisolated struct FeedbackReplyServerRow: Equatable, Sendable {
    let id: UUID
    let feedbackID: UUID
    let text: String
    let createdAt: Date
}

nonisolated protocol AthleteFeedbackReplyRepository: Sendable {
    /// `athlete_reply_to_feedback(p_feedback_id, p_text, p_id)`. Idempotent by `id`.
    func send(id: UUID, feedbackID: UUID, text: String) async throws
    /// `my_feedback_replies()`: the signed-in athlete's replies, also after leaving.
    func mine() async throws -> [FeedbackReplyServerRow]
}

nonisolated struct SupabaseAthleteFeedbackReplyRepository: AthleteFeedbackReplyRepository {
    private struct SendParams: Encodable {
        let p_feedback_id: UUID
        let p_text: String
        let p_id: UUID
    }

    private struct Row: Decodable {
        let id: UUID
        let feedbackID: UUID
        let text: String
        let createdAt: String
        enum CodingKeys: String, CodingKey { case id, text, feedbackID = "feedback_id", createdAt = "created_at" }
    }

    func send(id: UUID, feedbackID: UUID, text: String) async throws {
        let _: String = try await SupabaseManager.client
            .rpc(FeedbackReplyRPC.reply, params: SendParams(p_feedback_id: feedbackID, p_text: text, p_id: id))
            .execute()
            .value
    }

    func mine() async throws -> [FeedbackReplyServerRow] {
        let rows: [Row] = try await SupabaseManager.client.rpc(FeedbackReplyRPC.mine).execute().value
        return rows.compactMap { row in
            CoachSeenTimestamp.parse(row.createdAt).map {
                FeedbackReplyServerRow(id: row.id, feedbackID: row.feedbackID, text: row.text, createdAt: $0)
            }
        }
    }
}

/// Owns C7.7 on the athlete's phone. Follows C7.3's sharing context (sign-in, link or gate change and
/// every foreground refresh) and flushes its outbox each time.
@MainActor
final class AthleteFeedbackReplyService: ObservableObject {
    static let shared = AthleteFeedbackReplyService()
    /// Queued replies older than this are dropped, like the other v2 outboxes.
    static let maxAge: TimeInterval = 14 * 24 * 3600

    @Published private(set) var context = RunSharingContext.off
    @Published private(set) var replies: [AthleteFeedbackReply] {
        didSet { save(replies, key: repliesKey) }
    }
    @Published private(set) var pending: [PendingFeedbackReply] {
        didSet { save(pending, key: outboxKey) }
    }
    /// Set when a queued reply was dropped because the link ended. Shown once, under that note.
    @Published var linkGoneNotice: (feedbackID: UUID, coachName: String)?

    private let repository: any AthleteFeedbackReplyRepository
    private let defaults: UserDefaults
    private let analytics: () -> any AnalyticsTracking
    private let now: () -> Date
    private let repliesKey: String
    private let outboxKey: String
    private var flushing = false
    private var subscription: AnyCancellable?

    init(
        repository: any AthleteFeedbackReplyRepository = SupabaseAthleteFeedbackReplyRepository(),
        defaults: UserDefaults = .standard,
        keyPrefix: String = "coachV2.feedbackReplies",
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared },
        now: @escaping () -> Date = Date.init,
        sharing: AnyPublisher<RunSharingContext, Never>? = nil
    ) {
        self.repository = repository
        self.defaults = defaults
        self.analytics = analytics
        self.now = now
        repliesKey = "\(keyPrefix).replies.v1"
        outboxKey = "\(keyPrefix).outbox.v1"
        replies = Self.load([AthleteFeedbackReply].self, defaults: defaults, key: "\(keyPrefix).replies.v1") ?? []
        pending = Self.load([PendingFeedbackReply].self, defaults: defaults, key: "\(keyPrefix).outbox.v1") ?? []
        let source = sharing ?? AthleteRunSharingService.shared.$context.eraseToAnyPublisher()
        // No removeDuplicates: C7.3 republishes on every foreground, which is the outbox's retry.
        subscription = source.sink { [weak self] next in
            Task { @MainActor in await self?.apply(next) }
        }
    }

    nonisolated deinit {}

    // MARK: Gate

    /// Replies and Reply render only while Coach v2 is on for a signed-in athlete (flag-off AC).
    var isVisible: Bool { context.v2Enabled && context.userID != nil }

    func canReply(note: AthleteFeedbackNote, link: CoachLink?) -> Bool {
        FeedbackReplyPolicy.canReply(note: note, link: link, context: context)
    }

    func apply(_ next: RunSharingContext) async {
        context = next
        guard isVisible else { return }
        await flush()
        await refresh()
    }

    // MARK: What P6 shows

    /// This athlete's replies under `note`, oldest first. They stay after the link ends (AC6).
    func replies(for note: AthleteFeedbackNote) -> [AthleteFeedbackReply] {
        guard isVisible, let owner = context.userID else { return [] }
        return replies.filter { $0.ownerID == owner && $0.feedbackID == note.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Actions

    /// "Send". Returns false and does nothing unless Reply is allowed and the text fits (AC1, AC2).
    @discardableResult
    func send(_ text: String, note: AthleteFeedbackNote, link: CoachLink?) async -> Bool {
        guard canReply(note: note, link: link), FeedbackReplyPolicy.canSend(text),
              let owner = context.userID else { return false }
        let reply = AthleteFeedbackReply(
            id: UUID(), ownerID: owner, feedbackID: note.id, text: FeedbackReplyPolicy.trimmed(text),
            createdAt: now(), sent: false, coachName: link?.coachName ?? note.coachName,
            target: FeedbackReplyTarget(note: note)
        )
        replies.append(reply)
        pending.append(PendingFeedbackReply(id: UUID(), replyID: reply.id, ownerID: owner, createdAt: now()))
        await flush()
        return true
    }

    /// Sends this account's queued replies in order. Stops at the first one that must wait. Runs even
    /// when no longer sharing, so a reply queued before the link ended gets `link_inactive` (AC7).
    func flush() async {
        guard !flushing, isVisible, let owner = context.userID else { return }
        flushing = true
        defer { flushing = false }
        let cutoff = now().addingTimeInterval(-Self.maxAge)
        let expired = Set(pending.filter { $0.createdAt < cutoff }.map(\.replyID))
        if !expired.isEmpty {
            pending.removeAll { expired.contains($0.replyID) }
            replies.removeAll { expired.contains($0.id) && !$0.sent }
        }
        for item in pending where item.ownerID == owner {
            guard pending.contains(item) else { continue }
            guard let reply = replies.first(where: { $0.id == item.replyID }) else {
                pending.removeAll { $0.id == item.id }
                continue
            }
            do {
                try await repository.send(id: reply.id, feedbackID: reply.feedbackID, text: reply.text)
                update(reply.id) {
                    $0.sent = true
                    $0.retrying = false
                }
                pending.removeAll { $0.id == item.id }
                CoachV2Analytics.track(.coachNoteReplySent(target: reply.target ?? .week), to: analytics())
            } catch {
                if error is CancellationError { return }
                switch FeedbackReplyFailure.classify(error) {
                case .offline:
                    return
                case .keep:
                    update(reply.id) { $0.retrying = true }
                    return
                case .linkGone:
                    pending.removeAll { $0.id == item.id }
                    replies.removeAll { $0.id == reply.id }
                    linkGoneNotice = (reply.feedbackID, reply.coachName ?? "")
                case .drop:
                    pending.removeAll { $0.id == item.id }
                    replies.removeAll { $0.id == reply.id }
                }
            }
        }
    }

    /// Reads this athlete's replies from the server (another phone, a reinstall). A reply missing
    /// from the answer is kept: an empty or partial read never wipes what the athlete wrote.
    func refresh() async {
        guard isVisible, let owner = context.userID,
              let rows = try? await repository.mine() else { return }
        for row in rows {
            if replies.contains(where: { $0.id == row.id }) {
                update(row.id) {
                    $0.sent = true
                    $0.retrying = false
                }
            } else {
                replies.append(AthleteFeedbackReply(
                    id: row.id, ownerID: owner, feedbackID: row.feedbackID, text: row.text,
                    createdAt: row.createdAt, sent: true
                ))
            }
        }
        // A row the server stored but this phone still held as queued: nothing left to send.
        let stored = Set(rows.map(\.id))
        pending.removeAll { $0.ownerID == owner && stored.contains($0.replyID) }
    }

    // MARK: Private

    private func update(_ id: UUID, _ change: (inout AthleteFeedbackReply) -> Void) {
        guard let index = replies.firstIndex(where: { $0.id == id }) else { return }
        var reply = replies[index]
        change(&reply)
        if replies[index] != reply { replies[index] = reply }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
