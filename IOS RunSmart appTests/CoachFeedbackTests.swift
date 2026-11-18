import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class CoachFeedbackTests: XCTestCase {
    private let athlete = UUID()
    private let coach = UUID()
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "CoachFeedbackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func composer(
        _ request: CoachFeedbackRequest = .onRun(101, weekStart: "2026-11-16"),
        service: MockCoachFeedbackService, outbox: CoachFeedbackOutbox? = nil
    ) -> CoachFeedbackComposerModel {
        CoachFeedbackComposerModel(
            request: request, athleteID: athlete, athleteName: "Yoni", service: service, coachID: coach,
            drafts: CoachFeedbackDraftStore(defaults: defaults),
            outbox: outbox ?? CoachFeedbackOutbox(defaults: defaults)
        )
    }

    func testSendIsDisabledForEmptyOrBlankText() async {
        let service = MockCoachFeedbackService()
        let model = composer(service: service)
        XCTAssertFalse(model.canSend)
        model.text = "   \n  "
        XCTAssertFalse(model.canSend)
        let sent = await model.send()
        XCTAssertNil(sent)
        XCTAssertEqual(service.addCalls, 0)
        model.text = String(repeating: "a", count: 2001)
        XCTAssertFalse(model.canSend, "over the 2000-character limit")
        model.text = "Nice."
        XCTAssertTrue(model.canSend)
    }

    func testChipsInsertAtTheCursorAndNeverSend() {
        let service = MockCoachFeedbackService()
        let model = composer(service: service)
        model.text = "Well done.Keep going."
        model.selection = NSRange(location: 10, length: 0)
        model.insertChip("Strong finish.")
        XCTAssertEqual(model.text, "Well done. Strong finish. Keep going.")
        XCTAssertEqual(model.selection, NSRange(location: 25, length: 0))
        XCTAssertEqual(service.addCalls, 0, "a chip never sends")
        XCTAssertEqual(model.status, .idle)

        let replaced = CoachFeedbackText.insert("Nice steady effort.", into: "Hi XX", at: NSRange(location: 3, length: 2))
        XCTAssertEqual(replaced.text, "Hi Nice steady effort.")
        XCTAssertEqual(CoachFeedbackText.insert("Strong finish.", into: "", at: NSRange(location: 0, length: 0)).text,
                       "Strong finish.")
    }

    func testDraftIsKeptPerRunAndWeekAndRestored() {
        let service = MockCoachFeedbackService()
        let first = composer(service: service)
        first.text = "Draft on the run"
        first.target = .week("2026-11-16")
        XCTAssertEqual(first.text, "", "the week has its own draft")
        first.text = "Draft on the week"
        XCTAssertTrue(first.hasUnsentText)

        let reopened = composer(service: service)
        XCTAssertEqual(reopened.text, "Draft on the run")
        reopened.target = .week("2026-11-16")
        XCTAssertEqual(reopened.text, "Draft on the week")
        reopened.discardDraft()

        let again = composer(.onWeek("2026-11-16"), service: service)
        XCTAssertEqual(again.text, "", "Discard removes the draft")
    }

    func testSuccessStoresTrimmedNoteAndClearsDraft() async {
        let service = MockCoachFeedbackService()
        let model = composer(service: service)
        model.text = "  Good pacing, easy runs should feel easy.  "
        let note = await model.send()
        XCTAssertEqual(note?.text, "Good pacing, easy runs should feel easy.")
        XCTAssertEqual(note?.runID, 101)
        XCTAssertEqual(model.status, .sent)
        XCTAssertFalse(model.hasUnsentText)
        XCTAssertNil(CoachFeedbackDraftStore(defaults: defaults).draft(athleteID: athlete, target: .run(101)))
        XCTAssertEqual(CoachFeedbackCopy.sent("Yoni"), "Sent. Yoni will see this in the app.")
    }

    func testOfflineQueuesThenRetrySendsOnceWithTheSameID() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = CoachFeedbackOutbox(defaults: defaults)
        let model = composer(service: service, outbox: outbox)
        model.text = "Strong finish."
        let failed = await model.send()
        XCTAssertNil(failed)
        XCTAssertEqual(model.status, .notSent)
        XCTAssertEqual(outbox.pending.count, 1)
        XCTAssertEqual(CoachFeedbackDraftStore(defaults: defaults).draft(athleteID: athlete, target: .run(101)),
                       "Strong finish.", "the text stays on this phone")

        // Back online: the reconnect flush sends it, then a manual Retry finds the same row.
        service.failure = nil
        let flushed = await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(flushed.count, 1)
        XCTAssertTrue(outbox.pending.isEmpty)
        let retried = await model.send()
        XCTAssertEqual(retried?.id, flushed.first?.id)
        XCTAssertEqual(service.stored.count, 1, "the note is stored once")
    }

    func testDiscardAfterAFailedSendNeverSendsOnReconnect() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = CoachFeedbackOutbox(defaults: defaults)
        let model = composer(service: service, outbox: outbox)
        model.text = "Not this one."
        _ = await model.send()
        XCTAssertEqual(outbox.pending.count, 1)
        model.discardDraft()
        XCTAssertTrue(outbox.pending.isEmpty, "Discard also drops the queued send")
        service.failure = nil
        await outbox.flush(using: service, coachID: coach)
        XCTAssertTrue(service.stored.isEmpty)
    }

    func testReopenedDraftKeepsTheQueuedIDSoItSendsOnceAndDiscardCancelsIt() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = CoachFeedbackOutbox(defaults: defaults)
        let first = composer(service: service, outbox: outbox)
        first.text = "Strong finish."
        _ = await first.send()

        // Closed with Keep, reopened later, sent again once online.
        service.failure = nil
        let reopened = composer(service: service, outbox: outbox)
        XCTAssertEqual(reopened.text, "Strong finish.")
        let note = await reopened.send()
        await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(service.stored.map(\.id), [note?.id].compactMap { $0 }, "one note, not two")

        // A second failed note, reopened and discarded, is never sent.
        service.failure = .notSent
        let another = composer(.onWeek("2026-11-16"), service: service, outbox: outbox)
        another.text = "Discard me."
        _ = await another.send()
        let reopenedAgain = composer(.onWeek("2026-11-16"), service: service, outbox: outbox)
        reopenedAgain.discardDraft()
        service.failure = nil
        await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(service.stored.count, 1)
        XCTAssertTrue(outbox.pending.isEmpty)
    }

    func testRevisedTextAfterABackgroundSendIsSavedNotDropped() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = CoachFeedbackOutbox(defaults: defaults)
        let model = composer(service: service, outbox: outbox)
        model.text = "Strong finish."
        _ = await model.send()

        // Reconnect: the queue sends the first text while the composer is still open.
        service.failure = nil
        await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(service.stored.map(\.text), ["Strong finish."])

        model.text = "Strong finish, and a smart even pace."
        let note = await model.send()
        XCTAssertEqual(note?.text, "Strong finish, and a smart even pace.")
        XCTAssertEqual(service.stored.map(\.text), ["Strong finish, and a smart even pace."],
                       "one note, carrying the revised text")
        XCTAssertNotNil(note?.editedAt, "it went out already, so it shows Edited")
    }

    func testSameTextAfterABackgroundSendIsNotMarkedEdited() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = CoachFeedbackOutbox(defaults: defaults)
        let model = composer(service: service, outbox: outbox)
        model.text = "Nice steady effort."
        _ = await model.send()
        service.failure = nil
        await outbox.flush(using: service, coachID: coach)
        let note = await model.send()
        XCTAssertNil(note?.editedAt)
        XCTAssertEqual(service.stored.count, 1)
    }

    func testBackgroundFlushRetiresTheDraft() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = CoachFeedbackOutbox(defaults: defaults)
        let model = composer(service: service, outbox: outbox)
        model.text = "Nice steady effort."
        _ = await model.send()
        service.failure = nil
        await outbox.flush(using: service, coachID: coach)
        XCTAssertNil(CoachFeedbackDraftStore(defaults: defaults).draft(athleteID: athlete, target: .run(101)))
        XCTAssertEqual(composer(service: service, outbox: outbox).text, "", "a sent note does not come back as a draft")
    }

    func testQueuedNotesOnlySendWithTheCoachWhoWroteThem() async {
        let service = MockCoachFeedbackService()
        let outbox = CoachFeedbackOutbox(defaults: defaults)
        outbox.enqueue(PendingCoachFeedback(id: UUID(), coachID: coach, athleteID: athlete, target: .run(101),
                                            text: "From coach A", kind: .add))
        let otherCoach = UUID()
        let sentAsOther = await outbox.flush(using: service, coachID: otherCoach)
        XCTAssertTrue(sentAsOther.isEmpty)
        XCTAssertTrue(service.stored.isEmpty, "another signed-in coach never sends it")
        XCTAssertEqual(outbox.pending.count, 1, "it waits for its own coach")

        let signedOut = CoachFeedbackStore(athleteID: athlete, athleteName: "Yoni", service: service,
                                           outbox: outbox, currentCoachID: { nil })
        await signedOut.flush()
        XCTAssertTrue(service.stored.isEmpty, "nothing sends while signed out")

        await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(service.stored.map(\.text), ["From coach A"])
    }

    func testKeepDuringAnEditRestoresTheEditInProgress() throws {
        let original = CoachFeedback(id: UUID(), athleteID: athlete, target: .week("2026-11-16"), text: "Easy week.",
                                     createdAt: Date(timeIntervalSince1970: 0))
        let service = MockCoachFeedbackService(rows: [original])
        let request = try XCTUnwrap(CoachFeedbackRequest.edit(original, weekStart: "2026-11-16"))
        let editing = composer(request, service: service)
        editing.text = "Easy week, well done."
        XCTAssertTrue(editing.hasUnsentText)
        XCTAssertEqual(composer(request, service: service).text, "Easy week, well done.", "Keep restores the edit")
        XCTAssertNil(CoachFeedbackDraftStore(defaults: defaults).draft(athleteID: athlete, target: .week("2026-11-16")),
                     "an edit does not overwrite the week's new-note draft")
        editing.discardDraft()
        XCTAssertEqual(composer(request, service: service).text, "Easy week.", "Discard goes back to the saved note")
    }

    func testRevokedLinkStopsTheComposerAndDropsTheQueue() async {
        let service = MockCoachFeedbackService()
        service.failure = .notLinked
        let outbox = CoachFeedbackOutbox(defaults: defaults)
        outbox.enqueue(PendingCoachFeedback(id: UUID(), coachID: coach, athleteID: athlete, target: .week("2026-11-16"),
                                            text: "Queued", kind: .add))
        let model = composer(service: service, outbox: outbox)
        model.text = "Hi"
        _ = await model.send()
        XCTAssertEqual(model.status, .revoked)
        XCTAssertFalse(model.canSend)
        XCTAssertEqual(CoachFeedbackCopy.left("Yoni"), "Yoni has left your group")
        await outbox.flush(using: service, coachID: coach)
        XCTAssertTrue(outbox.pending.isEmpty, "a note for a revoked link is not retried forever")
    }

    func testEditShowsEditedAndHasNoTargetPicker() async throws {
        let original = CoachFeedback(id: UUID(), athleteID: athlete, target: .run(101), text: "Strong finish.",
                                     createdAt: Date(timeIntervalSince1970: 0))
        let service = MockCoachFeedbackService(rows: [original])
        let request = try XCTUnwrap(CoachFeedbackRequest.edit(original, weekStart: "2026-11-16"))
        let model = composer(request, service: service)
        XCTAssertEqual(model.text, "Strong finish.")
        XCTAssertFalse(model.showsTargetPicker)
        XCTAssertFalse(model.canSend, "unchanged text is not a new save")
        model.text = "Strong finish, well paced."
        let edited = await model.send()
        XCTAssertEqual(edited?.text, "Strong finish, well paced.")
        XCTAssertNotNil(edited?.editedAt, "the note shows Edited")
        XCTAssertEqual(edited?.createdAt, original.createdAt)
        XCTAssertEqual(service.stored.count, 1)

        let store = CoachFeedbackStore(athleteID: athlete, athleteName: "Yoni", service: service,
                                       outbox: CoachFeedbackOutbox(defaults: defaults), currentCoachID: { [coach] in coach })
        await store.load()
        XCTAssertEqual(store.notes(for: .run(101)).first?.editedAt, edited?.editedAt)
        XCTAssertTrue(store.notes(for: .week("2026-11-16")).isEmpty)
    }

    func testParagraphDirectionFollowsEachParagraphsFirstStrongCharacter() {
        XCTAssertTrue(CoachFeedbackText.isRightToLeft("כל הכבוד על הריצה"))
        XCTAssertTrue(CoachFeedbackText.isRightToLeft("5 ק״מ, great pace"), "digits are weak, Hebrew decides")
        XCTAssertFalse(CoachFeedbackText.isRightToLeft("Great pace, כל הכבוד"))
        XCTAssertFalse(CoachFeedbackText.isRightToLeft("5:30 /km"))
        XCTAssertFalse(CoachFeedbackText.isRightToLeft(""))
        let mixed = "Strong finish.\nשבוע טוב"
        XCTAssertEqual(CoachFeedbackText.paragraphs(mixed).map(CoachFeedbackText.isRightToLeft), [false, true])
    }

    func testNoteDecodesFromTheServerRow() throws {
        let json = """
        {"id":"\(UUID())","athlete_id":"\(athlete)","run_id":null,"week_start":"2026-11-16",
         "text":"שבוע טוב","created_at":"2026-11-18T07:00:00.123+00:00","edited_at":null}
        """
        let note = try JSONDecoder().decode(CoachFeedback.self, from: Data(json.utf8))
        XCTAssertEqual(note.target, .week("2026-11-16"))
        XCTAssertEqual(note.text, "שבוע טוב")
        XCTAssertNil(note.editedAt)
    }
}
