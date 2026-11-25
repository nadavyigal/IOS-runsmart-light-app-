import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class OnDeviceDebriefTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "OnDeviceDebriefTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private let input = RunDebriefInput(
        distanceKm: 5.234,
        durationSeconds: 1_865,
        averagePaceMinPerKm: 5.95,
        averageHeartRateBPM: 148,
        workoutType: "easy",
        recentRunsLast7Days: 3
    )

    func testOptInIsOffByDefault() {
        XCTAssertFalse(OnDeviceDebrief.isOptedIn(defaults))
    }

    private func plan(
        optedIn: Bool = true, ready: Bool = true, remoteEnabled: Bool = true,
        coachLinked: Bool = false, hasSession: Bool = true, trigger: RunDebriefTrigger = .liveRun
    ) -> [RunDebriefGeneratorKind] {
        OnDeviceDebrief.generatorPlan(optedIn: optedIn, ready: ready, remoteEnabled: remoteEnabled,
                                      coachLinked: coachLinked, hasSession: hasSession, trigger: trigger)
    }

    func testPlanForOptedInLiveRunIsOnDeviceThenCloud() {
        XCTAssertEqual(plan(), [.onDevice, .cloud])
    }

    func testPlanWithoutOptInIsCloudOnly() {
        XCTAssertEqual(plan(optedIn: false), [.cloud])
    }

    func testRemoteFlagOffIsCloudOnlyEvenWhenOptedIn() {
        XCTAssertEqual(plan(remoteEnabled: false), [.cloud])
    }

    func testModelNotReadyIsCloudOnly() {
        XCTAssertEqual(plan(ready: false), [.cloud])
    }

    func testLinkedCoachIsCloudOnly() {
        XCTAssertEqual(plan(coachLinked: true), [.cloud])
    }

    func testOptedInGuestOnALiveRunGetsOnDeviceOnly() {
        XCTAssertEqual(plan(hasSession: false), [.onDevice])
    }

    func testImportsSyncsAndRecoveredRunsAreCloudOnly() {
        for trigger in [RunDebriefTrigger.importRun, .syncNewest, .recovered, .background] {
            XCTAssertEqual(plan(trigger: trigger), [.cloud], trigger.rawValue)
        }
    }

    func testGuestWithoutOptInGetsNoGenerator() {
        XCTAssertEqual(plan(optedIn: false, hasSession: false), [])
    }

    func testOnDeviceTimeoutIsShorterThanCloud() {
        if #available(iOS 26.0, *) {
            XCTAssertEqual(OnDeviceDebriefGenerator().timeoutNanoseconds, 8_000_000_000)
        }
        XCTAssertEqual(CloudRunDebriefGenerator(authUserID: UUID(), accessToken: "t").timeoutNanoseconds, 12_000_000_000)
    }

    func testNonEnglishAppLanguageHidesTheExperiment() throws {
        try XCTSkipIf(OnDeviceDebrief.appLanguageIsEnglish, "test run is in English; run with -testLanguage he")
        XCTAssertEqual(OnDeviceDebrief.unavailableReason, .language)
        XCTAssertFalse(OnDeviceDebrief.isReady)
    }

    func testOnDeviceSourceIsStoredAsOnDevice() {
        XCTAssertEqual(PostRunDebriefModel.Source.onDevice.rawValue, "on_device")
    }

    func testRunSummaryHasTheFactsAndNoLocation() {
        let summary = OnDeviceDebriefPrompt.runSummary(for: input)
        XCTAssertTrue(summary.contains("Distance: 5.23 km"), summary)
        XCTAssertTrue(summary.contains("Moving time: 31 min 5 s"), summary)
        XCTAssertTrue(summary.contains("Average pace: 5:57 per km"), summary)
        XCTAssertTrue(summary.contains("Average heart rate: 148 bpm"), summary)
        XCTAssertTrue(summary.contains("Workout type: easy"), summary)
        XCTAssertTrue(summary.contains("Runs in the last 7 days: 3"), summary)
        XCTAssertFalse(summary.lowercased().contains("lat"), summary)
    }

    func testRunSummarySkipsMissingPaceAndHeartRate() {
        let sparse = RunDebriefInput(distanceKm: 0, durationSeconds: 0, averagePaceMinPerKm: nil,
                                     averageHeartRateBPM: nil, workoutType: "easy", recentRunsLast7Days: 0)
        let summary = OnDeviceDebriefPrompt.runSummary(for: sparse)
        XCTAssertFalse(summary.contains("pace"))
        XCTAssertFalse(summary.contains("heart rate"))
    }

    func testPromptStaysSmallAndKeepsTheSafetyRules() {
        let total = OnDeviceDebriefPrompt.instructions.count + OnDeviceDebriefPrompt.runSummary(for: input).count
        XCTAssertLessThan(total, 1_500, "keep the on-device prompt far inside the context window")
        XCTAssertTrue(OnDeviceDebriefPrompt.instructions.contains("Do not diagnose injuries or give medical advice."))
        XCTAssertTrue(OnDeviceDebriefPrompt.instructions.contains("Do not promise health, fitness or race results."))
    }

    func testClipKeepsShortTextAndCutsLongTextOnAWord() {
        XCTAssertEqual(OnDeviceDebriefPrompt.clip("  Nice run  ", to: 40), "Nice run")
        let clipped = OnDeviceDebriefPrompt.clip("Steady effort across every kilometre today", to: 20)
        XCTAssertLessThanOrEqual(clipped.count, 20)
        XCTAssertEqual(clipped, "Steady effort across")
    }
}
