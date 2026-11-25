import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class RunDebriefEventTests: XCTestCase {

    private nonisolated final class AnalyticsSpy: AnalyticsTracking {
        private(set) var events: [(name: String, properties: [String: Any])] = []
        func track(_ event: String, properties: [String: Any]) { events.append((event, properties)) }
        func identify(userId: String, traits: [String: Any]) {}
        func register(properties: [String: Any]) {}
        func reset() {}
    }

    private struct Fake: RunDebriefGenerating {
        enum Behavior { case skip, fail, cancel, timeout, incomplete, generate }
        let attemptName: String
        let behavior: Behavior

        func generateDebrief(for input: RunDebriefInput) async throws -> PostRunDebriefModel? {
            switch behavior {
            case .skip: return nil
            case .fail: throw SomeError()
            case .cancel: throw CancellationError()
            case .timeout: throw RunDebriefTimeoutError()
            case .incomplete: return PostRunDebriefModel(headline: " ", debrief: "x", tomorrow: "y", planImpact: nil, source: .ai)
            case .generate: return PostRunDebriefModel(headline: "Steady", debrief: "Even pace.", tomorrow: "Rest.", planImpact: nil, source: .onDevice)
            }
        }
    }

    private struct SomeError: Error {}

    private let input = RunDebriefInput(distanceKm: 5, durationSeconds: 1_800, averagePaceMinPerKm: 6,
                                        averageHeartRateBPM: nil, workoutType: "easy", recentRunsLast7Days: 2)

    private func makeRun() -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return RecordedRun(id: UUID(), providerActivityID: nil, source: .runSmart, startedAt: start,
                           endedAt: start.addingTimeInterval(1_800), distanceMeters: 5_000, movingTimeSeconds: 1_800,
                           averagePaceSecondsPerKm: 360, averageHeartRateBPM: nil, routePoints: [],
                           routeMatchResult: nil, syncedAt: nil)
    }

    func testPipelineReportsEveryAttemptInOrder() async {
        var attempts: [RunDebriefAttempt] = []
        let result = await RunDebriefPipeline.debrief(
            for: input,
            run: makeRun(),
            generators: [Fake(attemptName: "a", behavior: .skip), Fake(attemptName: "b", behavior: .fail),
                         Fake(attemptName: "c", behavior: .timeout), Fake(attemptName: "d", behavior: .incomplete),
                         Fake(attemptName: "e", behavior: .generate), Fake(attemptName: "f", behavior: .generate)],
            report: { attempts.append($0) }
        )

        XCTAssertEqual(result.headline, "Steady")
        XCTAssertEqual(attempts.map(\.generator), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(attempts.map(\.outcome), [.skipped, .failed, .timedOut, .incomplete, .generated])
        XCTAssertEqual(attempts[1].errorType, "SomeError")
        XCTAssertEqual(attempts[2].errorType, "RunDebriefTimeoutError")
        XCTAssertNil(attempts[4].errorType)
        XCTAssertTrue(attempts.allSatisfy { $0.latencyMs >= 0 })
    }

    func testGeneratorNamesMatchTheEventKeys() {
        XCTAssertEqual(CloudRunDebriefGenerator(authUserID: UUID(), accessToken: "t").attemptName, "cloud")
        if #available(iOS 26.0, *) {
            XCTAssertEqual(OnDeviceDebriefGenerator().attemptName, "on_device")
        }
    }

    private func trackedProperties(_ track: () -> Void) -> [String: Any] {
        let saved = Analytics.shared
        let spy = AnalyticsSpy()
        defer { Analytics.shared = saved }
        Analytics.shared = spy
        track()
        XCTAssertEqual(spy.events.map(\.name), ["run_debrief_generated"])
        return spy.events.first?.properties ?? [:]
    }

    func testEventForOnDeviceSuccess() {
        let props = trackedProperties {
            Analytics.trackRunDebriefGenerated(
                trigger: .liveRun, result: .onDevice, totalLatencyMs: 900,
                attempts: [RunDebriefAttempt(generator: "on_device", outcome: .generated, latencyMs: 850, errorType: nil)],
                onDeviceOptedIn: true, onDeviceUnavailable: nil
            )
        }
        XCTAssertEqual(props["source"] as? String, "on_device")
        XCTAssertEqual(props["latency_ms"] as? Int, 900)
        XCTAssertEqual(props["on_device_opted_in"] as? Bool, true)
        XCTAssertEqual(props["on_device_ready"] as? Bool, true)
        XCTAssertEqual(props["on_device_unavailable_reason"] as? String, "none")
        XCTAssertEqual(props["on_device_outcome"] as? String, "generated")
        XCTAssertEqual(props["on_device_latency_ms"] as? Int, 850)
        XCTAssertEqual(props["cloud_outcome"] as? String, "not_tried")
        XCTAssertNil(props["on_device_error_type"])
    }

    func testEventForOnDeviceFailureFallingBackToCloud() {
        let props = trackedProperties {
            Analytics.trackRunDebriefGenerated(
                trigger: .liveRun, result: .ai, totalLatencyMs: 4_000,
                attempts: [
                    RunDebriefAttempt(generator: "on_device", outcome: .failed, latencyMs: 300, errorType: "GenerationError"),
                    RunDebriefAttempt(generator: "cloud", outcome: .generated, latencyMs: 3_600, errorType: nil),
                ],
                onDeviceOptedIn: true, onDeviceUnavailable: nil
            )
        }
        XCTAssertEqual(props["source"] as? String, "ai")
        XCTAssertEqual(props["on_device_outcome"] as? String, "failed")
        XCTAssertEqual(props["on_device_error_type"] as? String, "GenerationError")
        XCTAssertEqual(props["cloud_outcome"] as? String, "generated")
    }

    func testEventForRunnerWhoDidNotOptInCarriesNoText() {
        let props = trackedProperties {
            Analytics.trackRunDebriefGenerated(
                trigger: .liveRun, result: .fallback, totalLatencyMs: 12_000,
                attempts: [RunDebriefAttempt(generator: "cloud", outcome: .timedOut, latencyMs: 12_000, errorType: "RunDebriefTimeoutError")],
                onDeviceOptedIn: false, onDeviceUnavailable: .language
            )
        }
        XCTAssertEqual(props["on_device_ready"] as? Bool, false)
        XCTAssertEqual(props["on_device_unavailable_reason"] as? String, "language")
        XCTAssertEqual(props["on_device_outcome"] as? String, "not_tried")
        XCTAssertNil(props["on_device_latency_ms"])
        XCTAssertEqual(props["cloud_outcome"] as? String, "timed_out")
        XCTAssertEqual(props["trigger"] as? String, "live_run")
        XCTAssertEqual(Set(props.keys), ["trigger", "source", "latency_ms", "on_device_opted_in", "on_device_ready",
                                         "on_device_unavailable_reason", "on_device_outcome", "cloud_outcome"])
    }

    // MARK: - RunDebriefSession

    private func produce(
        trigger: RunDebriefTrigger = .liveRun,
        generators: [any RunDebriefGenerating],
        compared: inout Int
    ) async -> (PostRunDebriefModel, [(name: String, properties: [String: Any])]) {
        let saved = Analytics.shared
        let spy = AnalyticsSpy()
        defer { Analytics.shared = saved }
        Analytics.shared = spy
        var count = 0
        let result = await RunDebriefSession.produce(
            run: makeRun(), trigger: trigger, generators: generators,
            onDeviceOptedIn: true, onDeviceUnavailable: nil,
            makeInput: { self.input }, persist: { _ in }, compare: { _ in count += 1 }
        )
        compared = count
        return (result, spy.events)
    }

    func testSessionSendsExactlyOneEventWithTheTrigger() async {
        var compared = 0
        let (result, events) = await produce(
            trigger: .importRun,
            generators: [Fake(attemptName: "cloud", behavior: .generate)],
            compared: &compared
        )
        XCTAssertEqual(result.headline, "Steady")
        XCTAssertEqual(events.map(\.name), ["run_debrief_generated"])
        XCTAssertEqual(events.first?.properties["trigger"] as? String, "import")
        XCTAssertEqual(events.first?.properties["cloud_outcome"] as? String, "generated")
    }

    func testSessionWithNoGeneratorSendsOneFallbackEvent() async {
        var compared = 0
        let (result, events) = await produce(generators: [], compared: &compared)
        XCTAssertEqual(result.source, .fallback)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.properties["source"] as? String, "fallback")
        XCTAssertEqual(events.first?.properties["cloud_outcome"] as? String, "not_tried")
        XCTAssertEqual(compared, 0)
    }

    func testCancelledSessionSendsNoEventAndNoCompare() async {
        let saved = Analytics.shared
        let spy = AnalyticsSpy()
        defer { Analytics.shared = saved }
        Analytics.shared = spy
        var compared = 0
        let run = makeRun()
        let input = input
        let generators: [any RunDebriefGenerating] = [Fake(attemptName: "on_device", behavior: .generate),
                                                      Fake(attemptName: "cloud", behavior: .generate)]
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await RunDebriefSession.produce(
                run: run, trigger: .liveRun, generators: generators,
                onDeviceOptedIn: true, onDeviceUnavailable: nil,
                makeInput: { input }, persist: { _ in }, compare: { _ in compared += 1 }
            )
        }
        let result = await task.value
        XCTAssertEqual(result.source, .fallback)
        XCTAssertTrue(spy.events.isEmpty)
        XCTAssertEqual(compared, 0)
    }

    func testGeneratorCancellationWithoutTaskCancelSendsNoEventAndNoCompare() async {
        var compared = 0
        let (result, events) = await produce(
            generators: [Fake(attemptName: "on_device", behavior: .cancel), Fake(attemptName: "cloud", behavior: .generate)],
            compared: &compared
        )
        XCTAssertEqual(result.source, .fallback)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(compared, 0)
    }

    func testOrdinaryFailureStillSendsAFallbackEvent() async {
        var compared = 0
        let (result, events) = await produce(
            generators: [Fake(attemptName: "cloud", behavior: .fail)],
            compared: &compared
        )
        XCTAssertEqual(result.source, .fallback)
        XCTAssertEqual(events.map(\.name), ["run_debrief_generated"])
        XCTAssertEqual(events.first?.properties["cloud_outcome"] as? String, "failed")
    }

    func testCompareRunsOnlyForLiveRunsWithBothGenerators() async {
        let both: [any RunDebriefGenerating] = [Fake(attemptName: "on_device", behavior: .generate),
                                                Fake(attemptName: "cloud", behavior: .generate)]
        var compared = 0
        _ = await produce(trigger: .liveRun, generators: both, compared: &compared)
        XCTAssertEqual(compared, 1)
        for trigger in [RunDebriefTrigger.importRun, .syncNewest, .recovered, .background] {
            _ = await produce(trigger: trigger, generators: both, compared: &compared)
            XCTAssertEqual(compared, 0, trigger.rawValue)
        }
        _ = await produce(trigger: .liveRun, generators: [Fake(attemptName: "cloud", behavior: .generate)], compared: &compared)
        XCTAssertEqual(compared, 0)
    }

    func testCompareLogIsDedupedByRunID() throws {
        let runID = UUID()
        let line = try XCTUnwrap(RunDebriefCompare.line(
            runID: runID, date: Date(), input: input,
            onDevice: .init(headline: "A", debrief: "B", tomorrow: "C", latencyMs: 1, outcome: "generated"),
            cloud: .init(headline: "D", debrief: "E", tomorrow: "F", latencyMs: 2, outcome: "generated")
        ))
        XCTAssertTrue(RunDebriefCompare.hasLine(for: runID, in: line + "\n"))
        XCTAssertFalse(RunDebriefCompare.hasLine(for: UUID(), in: line + "\n"))
    }

    func testCompareLineHasBothSidesAndTheFacts() throws {
        let runID = UUID()
        let line = try XCTUnwrap(RunDebriefCompare.line(
            runID: runID,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            input: input,
            onDevice: .init(headline: "On device", debrief: "A.", tomorrow: "B.", latencyMs: 800, outcome: "generated"),
            cloud: .init(headline: nil, debrief: nil, tomorrow: nil, latencyMs: 12_000, outcome: "error: RunDebriefTimeoutError")
        ))
        XCTAssertFalse(line.contains("\n"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["run_id"] as? String, runID.uuidString)
        XCTAssertEqual((object["on_device"] as? [String: Any])?["headline"] as? String, "On device")
        XCTAssertEqual((object["cloud"] as? [String: Any])?["outcome"] as? String, "error: RunDebriefTimeoutError")
        XCTAssertNil((object["cloud"] as? [String: Any])?["headline"])
        XCTAssertTrue((object["facts"] as? String)?.contains("Distance: 5.00 km") == true)
    }
}
