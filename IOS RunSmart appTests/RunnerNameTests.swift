import XCTest
@testable import IOS_RunSmart_app

final class RunnerNameTests: XCTestCase {
    func testRealNameIsTrimmed() {
        XCTAssertEqual(RunnerName.resolved("  Nadav \n"), "Nadav")
    }

    func testEmptyAndNilAreNoName() {
        XCTAssertNil(RunnerName.resolved(nil))
        XCTAssertNil(RunnerName.resolved(""))
        XCTAssertNil(RunnerName.resolved("   "))
    }

    func testLegacyPlaceholderIsNoName() {
        XCTAssertNil(RunnerName.resolved("RunSmart Runner"))
        XCTAssertNil(RunnerName.resolved(" runsmart runner "))
    }

    func testHebrewNameIsKept() {
        XCTAssertEqual(RunnerName.resolved("נדב"), "נדב")
    }

    func testLongNameIsCapped() {
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(RunnerName.resolved(long)?.count, RunnerName.maxLength)
    }

    func testForSavingNeverStoresPlaceholder() {
        XCTAssertEqual(RunnerName.forSaving("RunSmart Runner"), "")
        XCTAssertEqual(RunnerName.forSaving(" Dana "), "Dana")
    }

    func testGreetingDropsCommaWithoutName() {
        XCTAssertEqual(RunnerName.greeting("Good morning", name: "Dana"), "Good morning, \u{2068}Dana\u{2069}")
        XCTAssertEqual(RunnerName.greeting("Good morning", name: "RunSmart Runner"), "Good morning")
        XCTAssertEqual(RunnerName.greeting("Good morning", name: nil), "Good morning")
    }

    func testLabelFallsBackToRunner() {
        XCTAssertEqual(RunnerName.label(""), "Runner")
        XCTAssertEqual(RunnerName.label("Dana"), "Dana")
    }

    func testGreetingIsolatesHebrewName() {
        XCTAssertEqual(RunnerName.greeting("Good evening", name: " נדב "), "Good evening, \u{2068}נדב\u{2069}")
    }

    // MARK: One-time name card

    func testPromptShowsOnceForUnnamedOnboardedRunner() {
        XCTAssertTrue(RunnerNamePrompt.shouldShow(name: "", hasCompletedOnboarding: true, dismissed: false))
        XCTAssertTrue(RunnerNamePrompt.shouldShow(name: "RunSmart Runner", hasCompletedOnboarding: true, dismissed: false))
        XCTAssertFalse(RunnerNamePrompt.shouldShow(name: "", hasCompletedOnboarding: true, dismissed: true))
        XCTAssertFalse(RunnerNamePrompt.shouldShow(name: "Dana", hasCompletedOnboarding: true, dismissed: false))
        XCTAssertFalse(RunnerNamePrompt.shouldShow(name: "", hasCompletedOnboarding: false, dismissed: false))
    }

    func testPromptDismissalIsPerAccount() {
        let defaults = UserDefaults(suiteName: "RunnerNameTests.\(UUID().uuidString)")!
        let first = UUID()
        let second = UUID()
        XCTAssertFalse(RunnerNamePrompt.isDismissed(userID: first, defaults: defaults))
        RunnerNamePrompt.dismiss(userID: first, defaults: defaults)
        XCTAssertTrue(RunnerNamePrompt.isDismissed(userID: first, defaults: defaults))
        XCTAssertFalse(RunnerNamePrompt.isDismissed(userID: second, defaults: defaults))
    }
}
