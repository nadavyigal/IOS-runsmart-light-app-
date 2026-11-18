import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class CoachFeedbackTests: XCTestCase {
    private let athlete = UUID()
    private let coach = UUID()
    /// Who the outbox thinks is signed in. Tests switch it to simulate another coach.
    private var session: UUID?

    private func makeOutbox() -> CoachFeedbackOutbox {
        CoachFeedbackOutbox(defaults: defaults, sessionCoachID: { [unowned self] in self.session })
    }

    private func draft(_ target: CoachFeedbackTarget, coach owner: UUID? = nil) -> String? {
        CoachFeedbackDraftStore(defaults: defaults).draft(coachID: owner ?? coach, athleteID: athlete, scope: target.key)
    }
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "CoachFeedbackTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        session = coach
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
            outbox: outbox ?? makeOutbox()
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
        XCTAssertNil(draft(.run(101)))
        XCTAssertEqual(CoachFeedbackCopy.sent("Yoni"), "Sent. Yoni will see this in the app.")
    }

    func testOfflineQueuesThenRetrySendsOnceWithTheSameID() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = makeOutbox()
        let model = composer(service: service, outbox: outbox)
        model.text = "Strong finish."
        let failed = await model.send()
        XCTAssertNil(failed)
        XCTAssertEqual(model.status, .notSent)
        XCTAssertEqual(outbox.pending.count, 1)
        XCTAssertEqual(draft(.run(101)),
                       "Strong finish.", "the text stays on this phone")

        // Back online: the reconnect flush sends it, then a manual Retry finds the same row.
        service.failure = nil
        let flushed = await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(flushed.stored.count, 1)
        XCTAssertTrue(outbox.pending.isEmpty)
        let retried = await model.send()
        XCTAssertEqual(retried?.id, flushed.stored.first?.id)
        XCTAssertEqual(service.stored.count, 1, "the note is stored once")
    }

    func testDiscardAfterAFailedSendNeverSendsOnReconnect() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = makeOutbox()
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
        let outbox = makeOutbox()
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
        let outbox = makeOutbox()
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
        let outbox = makeOutbox()
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
        let outbox = makeOutbox()
        let model = composer(service: service, outbox: outbox)
        model.text = "Nice steady effort."
        _ = await model.send()
        service.failure = nil
        await outbox.flush(using: service, coachID: coach)
        XCTAssertNil(draft(.run(101)))
        XCTAssertEqual(composer(service: service, outbox: outbox).text, "", "a sent note does not come back as a draft")
    }

    func testQueuedNotesOnlySendWithTheCoachWhoWroteThem() async {
        let service = MockCoachFeedbackService()
        let outbox = makeOutbox()
        outbox.enqueue(PendingCoachFeedback(id: UUID(), coachID: coach, athleteID: athlete, target: .run(101),
                                            text: "From coach A", kind: .add))
        let otherCoach = UUID()
        session = otherCoach
        let sentAsOther = await outbox.flush(using: service, coachID: otherCoach)
        XCTAssertTrue(sentAsOther.stored.isEmpty)
        XCTAssertTrue(service.stored.isEmpty, "another signed-in coach never sends it")
        XCTAssertEqual(outbox.pending.count, 1, "it waits for its own coach")

        session = coach
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
        XCTAssertNil(draft(.week("2026-11-16")),
                     "an edit does not overwrite the week's new-note draft")
        editing.discardDraft()
        XCTAssertEqual(composer(request, service: service).text, "Easy week.", "Discard goes back to the saved note")
    }

    func testRevokedLinkStopsTheComposerAndDropsTheQueue() async {
        let service = MockCoachFeedbackService()
        service.failure = .notLinked
        let outbox = makeOutbox()
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
                                       outbox: makeOutbox(), currentCoachID: { [coach] in coach })
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

    func testRejectedNoteIsNotRetriedAndKeepsItsText() async {
        let service = MockCoachFeedbackService()
        service.failure = .rejected
        let outbox = makeOutbox()
        let model = composer(service: service, outbox: outbox)
        model.text = "On a run that was deleted."
        _ = await model.send()
        XCTAssertEqual(model.status, .rejected)
        XCTAssertTrue(outbox.pending.isEmpty, "a request that can never succeed is not queued")
        XCTAssertEqual(draft(.run(101)), "On a run that was deleted.", "the text stays recoverable")

        // A queued note that the server later rejects leaves the queue but keeps its draft.
        outbox.enqueue(PendingCoachFeedback(id: UUID(), coachID: coach, athleteID: athlete, target: .run(101),
                                            text: "On a run that was deleted.", kind: .add))
        await outbox.flush(using: service, coachID: coach)
        XCTAssertTrue(outbox.pending.isEmpty)
        XCTAssertEqual(draft(.run(101)), "On a run that was deleted.")
    }

    func testBackgroundRevokeMarksTheAthleteScreen() async {
        let service = MockCoachFeedbackService()
        service.failure = .notLinked
        let outbox = makeOutbox()
        outbox.enqueue(PendingCoachFeedback(id: UUID(), coachID: coach, athleteID: athlete, target: .week("2026-11-16"),
                                            text: "Queued", kind: .add))
        let store = CoachFeedbackStore(athleteID: athlete, athleteName: "Yoni", service: service,
                                       outbox: outbox, currentCoachID: { [coach] in coach })
        await store.flush()
        XCTAssertTrue(store.revoked, "the detail screen reloads and shows the athlete left")
        XCTAssertTrue(outbox.pending.isEmpty)
    }

    func testFlushStopsWhenTheSignedInCoachChanges() async {
        let service = MockCoachFeedbackService()
        let outbox = makeOutbox()
        outbox.enqueue(PendingCoachFeedback(id: UUID(), coachID: coach, athleteID: athlete, target: .run(101),
                                            text: "From coach A", kind: .add))
        session = UUID()
        let result = await outbox.flush(using: service, coachID: coach)
        XCTAssertTrue(result.stored.isEmpty)
        XCTAssertTrue(service.stored.isEmpty, "never sent under another coach's session")
        XCTAssertEqual(outbox.pending.count, 1, "kept for its own coach")
    }

    func testDraftsBelongToTheCoachWhoWroteThem() {
        let service = MockCoachFeedbackService()
        let mine = composer(service: service)
        mine.text = "Private draft"
        let other = CoachFeedbackComposerModel(
            request: .onRun(101, weekStart: "2026-11-16"), athleteID: athlete, athleteName: "Yoni",
            service: service, coachID: UUID(), drafts: CoachFeedbackDraftStore(defaults: defaults), outbox: makeOutbox()
        )
        XCTAssertEqual(other.text, "", "another coach on this phone never sees it")
        XCTAssertEqual(composer(service: service).text, "Private draft")
    }

    func testBackgroundSendKeepsANewerDraftRevision() async {
        let service = MockCoachFeedbackService()
        service.failure = .notSent
        let outbox = makeOutbox()
        let model = composer(service: service, outbox: outbox)
        model.text = "First text."
        _ = await model.send()
        model.text = "Revised text, not sent yet."
        service.failure = nil
        await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(service.stored.map(\.text), ["First text."])
        XCTAssertEqual(draft(.run(101)), "Revised text, not sent yet.", "the newer revision survives")
    }

    func testANewerSaveSupersedesAQueuedOlderEdit() async throws {
        let original = CoachFeedback(id: UUID(), athleteID: athlete, target: .run(101), text: "A",
                                     createdAt: Date(timeIntervalSince1970: 0))
        let service = MockCoachFeedbackService(rows: [original])
        let outbox = makeOutbox()
        outbox.enqueue(PendingCoachFeedback(id: original.id, coachID: coach, athleteID: athlete, target: .run(101),
                                            text: "Older edit", kind: .edit))
        let request = try XCTUnwrap(CoachFeedbackRequest.edit(original, weekStart: "2026-11-16"))
        let model = composer(request, service: service, outbox: outbox)
        model.text = "Newest edit"
        _ = await model.send()
        await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(service.stored.map(\.text), ["Newest edit"], "the older queued edit never lands")
    }

    func testFlushRemovesOnlyTheExactEntryItSent() async {
        let service = MockCoachFeedbackService()
        let outbox = makeOutbox()
        let id = UUID()
        let older = PendingCoachFeedback(id: id, coachID: coach, athleteID: athlete, target: .run(101), text: "A", kind: .add)
        let newer = PendingCoachFeedback(id: id, coachID: coach, athleteID: athlete, target: .run(101), text: "B", kind: .add)
        outbox.enqueue(newer)
        outbox.remove(exactly: older)
        XCTAssertEqual(outbox.pending, [newer], "a completion for A never drops the newer B")
    }

    func testSessionThatChangesAfterTheCheckNeverPublishesTheNote() async {
        // The outbox still sees coach A, but the request runs under coach B's session.
        let service = MockCoachFeedbackService()
        service.signedInCoach = UUID()
        let outbox = makeOutbox()
        let model = composer(service: service, outbox: outbox)
        model.text = "From coach A"
        _ = await model.send()
        XCTAssertEqual(model.status, .notSent)
        XCTAssertTrue(service.stored.isEmpty, "the server refuses a request meant for another coach")
        XCTAssertEqual(outbox.pending.map(\.coachID), [coach], "kept queued for coach A")
        await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(outbox.pending.count, 1)
        XCTAssertEqual(draft(.run(101)), "From coach A", "the draft is kept too")
    }

    func testAStaleEditFromAnotherPhoneIsRefusedAndKept() async throws {
        let original = CoachFeedback(id: UUID(), athleteID: athlete, target: .run(101), text: "A",
                                     createdAt: Date(timeIntervalSince1970: 0))
        let service = MockCoachFeedbackService(rows: [original])
        let request = try XCTUnwrap(CoachFeedbackRequest.edit(original, weekStart: "2026-11-16"))
        let model = composer(request, service: service)
        service.editElsewhere(id: original.id, text: "Saved on phone B")
        model.text = "Typed on phone A"
        let saved = await model.send()
        XCTAssertNil(saved)
        XCTAssertEqual(model.status, .conflict)
        XCTAssertEqual(service.stored.map(\.text), ["Saved on phone B"], "the newer save is not overwritten")
        XCTAssertEqual(composer(request, service: service).text, "Typed on phone A", "phone A's text stays on the phone")
    }

    func testAQueuedStaleEditIsDroppedWithoutOverwriting() async {
        let original = CoachFeedback(id: UUID(), athleteID: athlete, target: .run(101), text: "A",
                                     createdAt: Date(timeIntervalSince1970: 0))
        let service = MockCoachFeedbackService(rows: [original])
        let outbox = makeOutbox()
        outbox.enqueue(PendingCoachFeedback(id: original.id, coachID: coach, athleteID: athlete, target: .run(101),
                                            text: "Queued on phone A", kind: .edit, baseRevision: 0))
        service.editElsewhere(id: original.id, text: "Saved on phone B")
        await outbox.flush(using: service, coachID: coach)
        XCTAssertEqual(service.stored.map(\.text), ["Saved on phone B"])
        XCTAssertTrue(outbox.pending.isEmpty, "a conflict is not retried forever")
    }
}
