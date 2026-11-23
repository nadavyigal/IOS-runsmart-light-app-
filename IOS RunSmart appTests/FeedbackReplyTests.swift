import Combine
import Supabase
import XCTest
@testable import IOS_RunSmart_app

/// C7.7: the athlete replies to a coach note (one level), and the coach reads the replies.
/// Covers the gate (flag-off, AC6, AC8), send and idempotent flush (AC1), the 1000 limit (AC2),
/// several replies and no edit (AC3), the coach store (AC4), link-ended (AC7), the kill switch
/// (v2_unavailable keeps it) and the coach_note_reply_sent event (no text).

private nonisolated final class FakeReplyRepository: AthleteFeedbackReplyRepository, @unchecked Sendable {
    var sendResults: [Result<Void, Error>] = []
    var serverRows: [FeedbackReplyServerRow] = []
    var mineFails = false
    private(set) var sent: [(id: UUID, feedbackID: UUID, text: String)] = []
    private(set) var mineCalls = 0

    func send(id: UUID, feedbackID: UUID, text: String) async throws {
        sent.append((id, feedbackID, text))
        try (sendResults.isEmpty ? .success(()) : sendResults.removeFirst()).get()
    }

    func mine() async throws -> [FeedbackReplyServerRow] {
        mineCalls += 1
        if mineFails { throw URLError(.notConnectedToInternet) }
        return serverRows
    }
}

private nonisolated final class FakeCoachReplyFetcher: CoachFeedbackReplyFetching, @unchecked Sendable {
    var rows: [CoachFeedbackReply] = []
    var fail = false
    private(set) var listCalls = 0
    private(set) var marked: [[UUID]] = []

    func replies(athleteIDs: [UUID]) async throws -> [CoachFeedbackReply] {
        listCalls += 1
        if fail { throw URLError(.timedOut) }
        return rows
    }

    func markRead(replyIDs: [UUID]) async throws -> Int {
        marked.append(replyIDs)
        return replyIDs.count
    }
}

private nonisolated final class ReplyEventSpy: AnalyticsTracking, @unchecked Sendable {
    var events: [(name: String, properties: [String: Any])] = []
    func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func unregister(_ key: String) {}
    func reset() {}

    var names: [String] { events.map(\.name) }
}

@MainActor
final class FeedbackReplyTests: XCTestCase {
    private let userID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    private let coachID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let otherCoachID = UUID(uuidString: "CCCCCCCC-0000-4000-8000-00000000000C")!
    private let linkID = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let start = Date(timeIntervalSince1970: 1_795_000_000)

    private var defaults: UserDefaults!
    private var repository: FakeReplyRepository!
    private var spy: ReplyEventSpy!
    private var clock: Date!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FeedbackReplyTests.\(UUID().uuidString)")
        repository = FakeReplyRepository()
        spy = ReplyEventSpy()
        clock = start
    }

    private var link: CoachLink {
        CoachLink(id: linkID, coachID: coachID, coachName: "Dana", consentedAt: start.addingTimeInterval(-30 * 86_400))
    }

    private var sharing: RunSharingContext {
        RunSharingContext(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana",
                          sharingActive: true, sharingSince: start.addingTimeInterval(-86_400))
    }

    private func note(id: UUID = UUID(uuidString: "D1000000-0000-4000-8000-00000000000B")!,
                      coach: UUID? = nil, kind: AthleteFeedbackNote.Kind = .note, runID: Int64? = nil) -> AthleteFeedbackNote {
        AthleteFeedbackNote(id: id, coachID: coach ?? coachID, coachName: "Dana", runID: runID,
                            weekStart: runID == nil && kind == .note ? "2026-11-16" : nil,
                            text: "Good week. Keep Thursday easy.", createdAt: start.addingTimeInterval(-3_600), kind: kind)
    }

    private func makeService(keyPrefix: String = "test.replies") -> AthleteFeedbackReplyService {
        AthleteFeedbackReplyService(
            repository: repository, defaults: defaults, keyPrefix: keyPrefix,
            analytics: { [spy] in spy! }, now: { [unowned self] in self.clock },
            sharing: Empty().eraseToAnyPublisher()
        )
    }

    private func sharingService() async -> AthleteFeedbackReplyService {
        let service = makeService()
        await service.apply(sharing)
        return service
    }

    // MARK: Flag-off and the gate

    func testNothingRendersOrCallsWithCoachV2Off() async {
        let service = makeService()
        await service.apply(RunSharingContext(v2Enabled: false, userID: userID, linkID: linkID, coachName: "Dana",
                                              sharingActive: true, sharingSince: start))
        XCTAssertFalse(service.isVisible)
        XCTAssertFalse(service.canReply(note: note(), link: link))
        let accepted = await service.send("hi", note: note(), link: link)
        XCTAssertFalse(accepted)
        XCTAssertTrue(service.replies.isEmpty)
        XCTAssertTrue(repository.sent.isEmpty, "no v2 RPC call")
        XCTAssertEqual(repository.mineCalls, 0, "no v2 read either")
        XCTAssertTrue(spy.events.isEmpty, "no v2 event")
    }

    func testReplyNeedsSharingAndTheCurrentCoach() async {
        let noAck = RunSharingContext(v2Enabled: true, userID: userID, linkID: linkID, coachName: "Dana")
        XCTAssertFalse(FeedbackReplyPolicy.canReply(note: note(), link: link, context: noAck), "no ack")
        XCTAssertFalse(FeedbackReplyPolicy.canReply(note: note(), link: nil, context: sharing), "link ended (AC6)")
        XCTAssertFalse(FeedbackReplyPolicy.canReply(note: note(coach: otherCoachID), link: link, context: sharing),
                       "a note from an earlier coach")
        let otherLink = CoachLink(id: UUID(), coachID: coachID, coachName: "Dana", consentedAt: start)
        XCTAssertFalse(FeedbackReplyPolicy.canReply(note: note(), link: otherLink, context: sharing),
                       "the context is for another link")
        XCTAssertTrue(FeedbackReplyPolicy.canReply(note: note(), link: link, context: sharing))
        XCTAssertTrue(FeedbackReplyPolicy.canReply(note: note(kind: .welcome), link: link, context: sharing),
                      "the welcome is a coach_feedback row")
    }

    // MARK: AC2: the 1000 limit

    func testCounterAndLimitCountServerCharacters() {
        XCTAssertFalse(FeedbackReplyPolicy.showsCounter(String(repeating: "a", count: 899)))
        XCTAssertTrue(FeedbackReplyPolicy.showsCounter(String(repeating: "a", count: 900)))
        XCTAssertTrue(FeedbackReplyPolicy.canSend(String(repeating: "ש", count: 1_000)))
        let over = String(repeating: "a", count: 1_001)
        XCTAssertTrue(FeedbackReplyPolicy.isTooLong(over))
        XCTAssertFalse(FeedbackReplyPolicy.canSend(over), "Send is disabled at 1001")
        XCTAssertFalse(FeedbackReplyPolicy.canSend("  \n "), "blank never sends")
        XCTAssertTrue(FeedbackReplyPolicy.canSend("  " + String(repeating: "a", count: 1_000) + "\n"),
                      "trimmed like the server")
        XCTAssertEqual(FeedbackReplyCopy.tooLong, "Keep replies under 1000 characters")
        XCTAssertEqual(FeedbackReplyCopy.counter(950), "950/1000")
    }

    func testTooLongReplyIsNotQueued() async {
        let service = await sharingService()
        let accepted = await service.send(String(repeating: "a", count: 1_001), note: note(), link: link)
        XCTAssertFalse(accepted)
        XCTAssertTrue(service.replies.isEmpty)
        XCTAssertTrue(repository.sent.isEmpty)
    }

    // MARK: AC1, AC3: send, several replies, analytics

    func testSendShowsSentAndTracksWithoutText() async throws {
        let service = await sharingService()
        let accepted = await service.send("  Thanks, legs felt heavy  ", note: note(), link: link)
        XCTAssertTrue(accepted)

        let call = try XCTUnwrap(repository.sent.first)
        XCTAssertEqual(call.text, "Thanks, legs felt heavy")
        XCTAssertEqual(call.feedbackID, note().id)
        XCTAssertEqual(service.replies(for: note()).map(\.status), [.sent])
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertEqual(spy.names, ["coach_note_reply_sent"])
        XCTAssertEqual(spy.events[0].properties["target"] as? String, "week")
        XCTAssertFalse(spy.events[0].properties.values.contains { ($0 as? String)?.contains("legs") == true },
                       "no reply text in analytics")

        await service.send("One more thing", note: note(), link: link)
        XCTAssertEqual(service.replies(for: note()).map(\.text), ["Thanks, legs felt heavy", "One more thing"],
                       "several replies, oldest first (AC3)")
    }

    func testTargetsForAnalytics() {
        XCTAssertEqual(FeedbackReplyTarget(note: note(runID: 42)), .run)
        XCTAssertEqual(FeedbackReplyTarget(note: note()), .week)
        XCTAssertEqual(FeedbackReplyTarget(note: note(kind: .welcome)), .welcome)
    }

    // MARK: Offline outbox

    func testOfflineReplyWaitsSurvivesRelaunchAndFlushesOnceByClientID() async throws {
        repository.sendResults = [.failure(URLError(.notConnectedToInternet))]
        let service = await sharingService()
        await service.send("Queued while offline", note: note(), link: link)
        XCTAssertEqual(service.replies(for: note()).map(\.status), [.waiting], "Waiting to send")
        XCTAssertEqual(service.pending.count, 1)
        XCTAssertTrue(spy.events.isEmpty, "the event fires only once the server took it")

        // The app is killed and relaunched: the queue and the reply come back from disk.
        let relaunched = makeService()
        await relaunched.apply(sharing)
        XCTAssertEqual(relaunched.replies(for: note()).map(\.status), [.sent])
        XCTAssertTrue(relaunched.pending.isEmpty)
        XCTAssertEqual(repository.sent.count, 2)
        XCTAssertEqual(repository.sent[0].id, repository.sent[1].id, "the same client id on every flush")
        XCTAssertEqual(spy.names, ["coach_note_reply_sent"])
    }

    func testKillSwitchKeepsTheReplyQueued() async {
        repository.sendResults = [.failure(PostgrestError(code: "P0001", message: "v2_unavailable"))]
        let service = await sharingService()
        await service.send("While the switch is on", note: note(), link: link)
        XCTAssertEqual(service.pending.count, 1, "no athlete text is dropped while the kill switch is on")
        XCTAssertEqual(service.replies(for: note()).map(\.status), [.retrying], "Couldn't send. We'll try again.")

        await service.flush()
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertEqual(service.replies(for: note()).map(\.status), [.sent])
    }

    // MARK: AC7: link ended before the flush

    func testLinkEndedDropsTheReplyAndTellsTheAthleteOnce() async {
        repository.sendResults = [.failure(URLError(.notConnectedToInternet))]
        let service = await sharingService()
        await service.send("Queued", note: note(), link: link)

        // The athlete left: no link, Reply hides, but the queue still flushes.
        repository.sendResults = [.failure(PostgrestError(code: "P0001", message: "link_inactive"))]
        await service.apply(RunSharingContext(v2Enabled: true, userID: userID, linkID: nil, coachName: nil))
        XCTAssertFalse(service.canReply(note: note(), link: nil))
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertTrue(service.replies.isEmpty, "nothing reached the coach")
        XCTAssertEqual(service.linkGoneNotice?.feedbackID, note().id)
        XCTAssertEqual(service.linkGoneNotice.map { FeedbackReplyCopy.notSent(coach: $0.coachName) },
                       BidiText.fill("You're no longer linked to {Coach}, so this reply wasn't sent.", ["Coach": "Dana"]))
        XCTAssertTrue(spy.events.isEmpty)
    }

    func testRepliesStayReadableAfterTheLinkEnds() async {
        let service = await sharingService()
        await service.send("Thanks", note: note(), link: link)
        await service.apply(RunSharingContext(v2Enabled: true, userID: userID, linkID: nil, coachName: nil))
        XCTAssertEqual(service.replies(for: note()).map(\.text), ["Thanks"], "AC6: read-only, still shown")
        XCTAssertFalse(service.canReply(note: note(), link: nil))
    }

    func testBadInputIsDropped() async {
        repository.sendResults = [.failure(PostgrestError(code: "22023", message: "reply_to_reply"))]
        let service = await sharingService()
        await service.send("x", note: note(), link: link)
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertTrue(service.replies.isEmpty)
        XCTAssertNil(service.linkGoneNotice)
    }

    func testFailureClassification() {
        XCTAssertEqual(FeedbackReplyFailure.classify(URLError(.timedOut)), .offline)
        XCTAssertEqual(FeedbackReplyFailure.classify(PostgrestError(code: "P0001", message: "v2_unavailable")), .keep)
        XCTAssertEqual(FeedbackReplyFailure.classify(PostgrestError(code: "P0001", message: "link_inactive")), .linkGone)
        for token in FeedbackReplyFailure.dropTokens {
            XCTAssertEqual(FeedbackReplyFailure.classify(PostgrestError(code: "22023", message: token)), .drop, token)
        }
        XCTAssertEqual(FeedbackReplyFailure.classify(PostgrestError(code: "XX000", message: "boom")), .keep)
    }

    // MARK: Server read

    func testRefreshAddsRepliesFromAnotherPhoneAndNeverWipesLocalOnes() async {
        repository.sendResults = [.failure(URLError(.notConnectedToInternet))]
        let service = await sharingService()
        await service.send("Local, waiting", note: note(), link: link)

        let remote = FeedbackReplyServerRow(id: UUID(), feedbackID: note().id, text: "From my iPad",
                                            createdAt: start.addingTimeInterval(-60))
        repository.serverRows = [remote]
        await service.refresh()
        XCTAssertEqual(service.replies(for: note()).map(\.text), ["From my iPad", "Local, waiting"])
        XCTAssertEqual(service.pending.count, 1, "the local reply is still queued")

        repository.serverRows = []
        await service.refresh()
        XCTAssertEqual(service.replies(for: note()).count, 2, "an empty read wipes nothing")
    }

    func testAnotherAccountSeesNothing() async {
        let service = await sharingService()
        await service.send("Mine", note: note(), link: link)
        await service.apply(RunSharingContext(v2Enabled: true, userID: UUID(), linkID: nil, coachName: nil))
        XCTAssertTrue(service.replies(for: note()).isEmpty)
    }

    // MARK: AC4: coach side

    func testCoachStoreReadsRepliesOnlyWhenEnabledAndMarksThemRead() async {
        let athleteID = userID
        let fetcher = FakeCoachReplyFetcher()
        let reply = CoachFeedbackReply(id: UUID(), feedbackID: note().id, athleteID: athleteID, text: "Thanks",
                                       createdAt: start, readAt: nil)
        let stray = CoachFeedbackReply(id: UUID(), feedbackID: UUID(), athleteID: UUID(), text: "other athlete",
                                       createdAt: start, readAt: nil)
        fetcher.rows = [reply, stray]

        let off = CoachFeedbackStore(athleteID: athleteID, athleteName: "Yoni", service: MockCoachFeedbackService(),
                                     currentCoachID: { nil })
        await off.loadReplies()
        XCTAssertTrue(off.replies.isEmpty, "Coach v2 off: no reply call")
        XCTAssertEqual(fetcher.listCalls, 0)

        let store = CoachFeedbackStore(athleteID: athleteID, athleteName: "Yoni", service: MockCoachFeedbackService(),
                                       currentCoachID: { nil })
        store.enableReplies(fetcher)
        await store.loadReplies()
        XCTAssertEqual(store.replies(for: note().id).map(\.text), ["Thanks"])
        XCTAssertEqual(store.replies.count, 1, "another athlete's row is never shown")

        await store.markRepliesRead(store.replies(for: note().id))
        XCTAssertEqual(fetcher.marked, [[reply.id]])
        XCTAssertNotNil(store.replies(for: note().id).first?.readAt)
        await store.markRepliesRead(store.replies(for: note().id))
        XCTAssertEqual(fetcher.marked.count, 1, "already read: no second call")

        fetcher.fail = true
        await store.loadReplies()
        XCTAssertEqual(store.replies.count, 1, "a failed read keeps what was shown")
    }

    func testCoachReplyHeaderIsolatesTheName() {
        XCTAssertEqual(FeedbackReplyCopy.athlete("יוני", time: "14:32"),
                       "\u{2068}יוני\u{2069} · \u{2068}14:32\u{2069}")
        XCTAssertEqual(FeedbackReplyCopy.you("14:32"), "You · \u{2068}14:32\u{2069}")
    }
}
