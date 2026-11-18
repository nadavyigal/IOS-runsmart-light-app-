import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class CoachWelcomeTests: XCTestCase {
    func testStarterRequiresEditingOrExplicitConfirmation() {
        var draft = CoachWelcomeDraft(savedText: nil)
        XCTAssertEqual(draft.text, "Welcome to the group, {first name}! I'll be following your runs here. Let's build this together.")
        XCTAssertFalse(draft.canSave)
        draft.text += " See you Sunday."
        XCTAssertTrue(draft.canSave)
        draft.text = CoachWelcomeDraft.starter
        XCTAssertFalse(draft.canSave)
        draft.confirmedStarter = true
        XCTAssertTrue(draft.canSave)
    }

    func testAthleteEditorStartsFromTheCoachTemplate() throws {
        let json = #"{"coach_name":"Dana","saved_text":null,"can_edit":true,"default_text":"Hi {first name}!"}"#
        let settings = try JSONDecoder().decode(CoachWelcomeSettings.self, from: Data(json.utf8))
        var draft = CoachWelcomeDraft(savedText: settings.savedText, starter: settings.defaultText)
        XCTAssertEqual(draft.text, "Hi {first name}!")
        XCTAssertFalse(draft.canSave)
        draft.confirmedStarter = true
        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(CoachWelcomeDraft(savedText: nil, starter: "  ").text, CoachWelcomeDraft.starter)
        let legacy = #"{"coach_name":"Dana","saved_text":null,"can_edit":true}"#
        XCTAssertNil(try JSONDecoder().decode(CoachWelcomeSettings.self, from: Data(legacy.utf8)).defaultText)
    }

    func testSavedTemplateCanBeCleared() {
        var draft = CoachWelcomeDraft(savedText: "Hello!")
        XCTAssertFalse(draft.canSave)
        draft.text = " \n "
        XCTAssertTrue(draft.canSave)
    }

    func testHintIsConsumedOncePerCoachAndHiddenWithATemplate() {
        let suite = "CoachWelcomeHintTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coach = UUID()
        let hint = CoachWelcomeHint(defaults: defaults)

        XCTAssertFalse(hint.shouldShow(ownerID: coach, savedText: "Hello!"))
        XCTAssertTrue(hint.shouldShow(ownerID: coach, savedText: nil))
        hint.consume(ownerID: coach)
        XCTAssertFalse(hint.shouldShow(ownerID: coach, savedText: nil))
        XCTAssertTrue(hint.shouldShow(ownerID: UUID(), savedText: nil))
    }

    func testEmptyClaimRetriesOnFailureAndIsRememberedAcrossStores() async {
        let suite = "CoachWelcomeClaimTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = AthleteFeedbackCache(defaults: defaults)
        let athleteID = UUID()
        let link = CoachLink(id: UUID(), coachID: UUID(), coachName: "Dana", consentedAt: .now)
        let service = StubWelcomeService()

        let store = AthleteFeedbackStore(service: MockAthleteFeedbackService(), cache: cache,
                                         welcomeService: service, currentUserID: { athleteID })
        store.beginSession(userID: athleteID)
        await store.claimWelcome(for: link)
        XCTAssertEqual(store.loadState, .failed)
        XCTAssertFalse(cache.hasClaimedWelcome(userID: athleteID, linkID: link.id))

        await store.claimWelcome(for: link)
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(cache.hasClaimedWelcome(userID: athleteID, linkID: link.id))

        let reopened = AthleteFeedbackStore(service: MockAthleteFeedbackService(), cache: cache,
                                            welcomeService: service, currentUserID: { athleteID })
        reopened.beginSession(userID: athleteID)
        await reopened.claimWelcome(for: link)
        let calls = await service.claimCalls
        XCTAssertEqual(calls, 2, "A successful empty claim is remembered for this account and link")
    }

    private actor StubWelcomeService: CoachWelcomeServing {
        private(set) var claimCalls = 0

        func claim() async throws {
            claimCalls += 1
            if claimCalls == 1 { throw URLError(.notConnectedToInternet) }
        }

        func settings(athleteID: UUID?) async throws -> CoachWelcomeSettings {
            throw URLError(.unsupportedURL)
        }

        func save(_ text: String, athleteID: UUID?) async throws {
            throw URLError(.unsupportedURL)
        }
    }

    func testLegacyFeedbackDecodesAsOrdinaryNote() throws {
        let json = """
        {"id":"\(UUID())","coach_id":"\(UUID())","coach_name":"Dana",
         "week_start":"2026-11-16","text":"Great week","created_at":"2026-11-18T00:00:00Z"}
        """
        let note = try JSONDecoder().decode(AthleteFeedbackNote.self, from: Data(json.utf8))
        XCTAssertEqual(note.kind, .note)
    }
}
