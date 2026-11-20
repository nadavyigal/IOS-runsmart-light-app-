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
        XCTAssertEqual(RunnerName.greeting("Good morning", name: "Dana"), "Good morning, Dana")
        XCTAssertEqual(RunnerName.greeting("Good morning", name: "RunSmart Runner"), "Good morning")
        XCTAssertEqual(RunnerName.greeting("Good morning", name: nil), "Good morning")
    }

    func testLabelFallsBackToRunner() {
        XCTAssertEqual(RunnerName.label(""), "Runner")
        XCTAssertEqual(RunnerName.label("Dana"), "Dana")
    }
}
