import XCTest
@testable import IOS_RunSmart_app

final class CoachAssistantTests: XCTestCase {
    func testAssistantContextIsOnlyAvailableForTheAuthenticatedOwner() {
        let source = CoachContextSource()
        let owner = UUID()
        let linked = CoachContext(coachDisplayName: "Dana", linkActive: true, lockedWorkoutIDs: [])
        source.replace(linked, ownerID: owner)
        XCTAssertEqual(source.context(for: owner), linked)
        XCTAssertEqual(source.context(for: UUID()), .solo)
        XCTAssertEqual(source.context(for: nil), .solo)
        source.replace(.solo, ownerID: nil)
        XCTAssertEqual(source.context(for: owner), .solo)
    }

    private struct Payload: Encodable {
        let message: String
    }

    func testCoachModeFlagStaysOffUnlessDebugLaunchArgumentIsSet() {
        XCTAssertFalse(RunSmartFeatures.coachModeEnabled(processArguments: [], isDebugBuild: true))
        XCTAssertFalse(RunSmartFeatures.coachModeEnabled(processArguments: ["-enable-coach-mode"], isDebugBuild: false))
        XCTAssertTrue(RunSmartFeatures.coachModeEnabled(processArguments: ["-enable-coach-mode"], isDebugBuild: true))
    }

    func testSoloContextOmitsTheCoachAndLinkedContextCarriesEmptyLocks() throws {
        let link = CoachLink(id: UUID(), coachID: UUID(), coachName: "Dana", consentedAt: Date())
        XCTAssertEqual(CoachContext.forRequest(link: link, coachModeEnabled: false), .solo)
        XCTAssertEqual(CoachContext.forRequest(link: nil, coachModeEnabled: true), .solo)

        let linked = CoachContext.forRequest(link: link, coachModeEnabled: true)
        XCTAssertEqual(linked.coachDisplayName, "Dana")
        XCTAssertTrue(linked.linkActive)
        XCTAssertEqual(linked.lockedWorkoutIDs, [])

        let soloData = try CoachRequestJSON.encode(Payload(message: "hello"), coach: .solo)
        let soloObject = try JSONSerialization.jsonObject(with: soloData) as? [String: Any]
        XCTAssertEqual(soloObject?["message"] as? String, "hello")
        XCTAssertNil(soloObject?["coachContext"])

        let linkedData = try CoachRequestJSON.encode(Payload(message: "hello"), coach: linked)
        let linkedObject = try JSONSerialization.jsonObject(with: linkedData) as? [String: Any]
        let coach = linkedObject?["coachContext"] as? [String: Any]
        XCTAssertEqual(coach?["coachDisplayName"] as? String, "Dana")
        XCTAssertEqual(coach?["linkActive"] as? Bool, true)
        XCTAssertEqual(coach?["lockedWorkoutIds"] as? [String], [])
    }

    func testLockedWorkoutReplyIsExactAndDoesNotMutate() {
        let provider = FakeLockProvider()
        XCTAssertNil(CoachLockReplyBuilder.replyIfLocked(coachName: "Dana", workoutID: "w1", provider: provider))

        provider.locked = ["w1"]
        let withoutNote = CoachLockReplyBuilder.replyIfLocked(coachName: "Dana", workoutID: "w1", provider: provider)
        XCTAssertEqual(withoutNote, CoachLockReply(message: "That's Dana's workout", noteLinkTitle: nil, note: nil))

        provider.notes["w1"] = "  Keep it easy.  "
        let withNote = CoachLockReplyBuilder.replyIfLocked(coachName: "Dana", workoutID: "w1", provider: provider)
        XCTAssertEqual(withNote?.message, "That's Dana's workout")
        XCTAssertEqual(withNote?.noteLinkTitle, "Read Dana's note")
        XCTAssertEqual(withNote?.note, "Keep it easy.")
        XCTAssertEqual(provider.locked, ["w1"])
        XCTAssertEqual(provider.notes["w1"], "  Keep it easy.  ")
        XCTAssertFalse(UnavailableCoachLockProvider().isLocked(workoutID: "w1"))
        XCTAssertNil(UnavailableCoachLockProvider().note(for: "w1"))
    }

    func testStringAuditRewordsTheEngineOnlyWhileLinked() {
        for swap in CoachAssistantCopy.swaps {
            XCTAssertEqual(CoachAssistantCopy.apply(swap.solo, assistant: false), swap.solo, swap.id)
            XCTAssertEqual(CoachAssistantCopy.apply(swap.linked, assistant: false), swap.linked, swap.id)
            XCTAssertEqual(CoachAssistantCopy.apply(swap.solo, assistant: true), swap.linked, swap.id)
            XCTAssertFalse(swap.linked.localizedCaseInsensitiveContains("your coach"), swap.id)
            XCTAssertFalse(swap.linked.localizedCaseInsensitiveContains("ai coach"), swap.id)
            XCTAssertTrue(swap.linked.localizedCaseInsensitiveContains("runsmart"), swap.id)
        }
        for human in CoachAssistantCopy.humanCoachStrings {
            XCTAssertNil(CoachAssistantCopy.swaps.first { $0.solo == human })
            XCTAssertEqual(CoachAssistantCopy.apply(human, assistant: true), human)
        }
        XCTAssertEqual(CoachConsentCopy.invalidCode, "That code doesn't work. Check it with your coach.")
        XCTAssertEqual(CoachAssistantCopy.chatPrivacy(coachName: "Dana"), "Private to you. Dana can't see this chat.")
        XCTAssertEqual(CoachAssistantCopy.debriefPrivacy, "RunSmart's notes · private to you")
    }

    private final class FakeLockProvider: CoachLockProvider {
        var locked: Set<String> = []
        var notes: [String: String] = [:]

        func isLocked(workoutID: String) -> Bool { locked.contains(workoutID) }
        func note(for workoutID: String) -> String? { notes[workoutID] }
    }
}
