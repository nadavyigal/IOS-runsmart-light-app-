import XCTest
@testable import IOS_RunSmart_app

final class RunSmartFeatureFlagsTests: XCTestCase {

    func testDefaultIsOff() {
        XCTAssertFalse(RunSmartFeatureFlags.adaptiveCoachEnabled(infoDictionary: [:], processArguments: []))
    }

    func testPlistYESTurnsFlagOn() {
        XCTAssertTrue(RunSmartFeatureFlags.adaptiveCoachEnabled(
            infoDictionary: ["RUNSMART_ADAPTIVE_COACH_ENABLED": "YES"],
            processArguments: []
        ))
    }

    func testPlistNOKeepsFlagOff() {
        XCTAssertFalse(RunSmartFeatureFlags.adaptiveCoachEnabled(
            infoDictionary: ["RUNSMART_ADAPTIVE_COACH_ENABLED": "NO"],
            processArguments: []
        ))
    }

    func testLaunchArgumentOverridesForQA() {
        XCTAssertTrue(RunSmartFeatureFlags.adaptiveCoachEnabled(
            infoDictionary: [:],
            processArguments: ["-RUNSMART_ADAPTIVE_COACH"]
        ))
    }
}
