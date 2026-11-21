import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class RunDebriefPipelineTests: XCTestCase {

    private enum Outcome {
        case debrief(PostRunDebriefModel)
        case skip
        case fail(Error)
    }

    private final class FakeGenerator: RunDebriefGenerating {
        let outcome: Outcome
        private(set) var calls = 0

        init(_ outcome: Outcome) { self.outcome = outcome }

        func generateDebrief(for input: RunDebriefInput) async throws -> PostRunDebriefModel? {
            calls += 1
            switch outcome {
            case .debrief(let model): return model
            case .skip: return nil
            case .fail(let error): throw error
            }
        }
    }

    private struct SomeError: Error {}

    private let input = RunDebriefInput(
        distanceKm: 5,
        durationSeconds: 1_800,
        averagePaceMinPerKm: 6,
        averageHeartRateBPM: 150,
        workoutType: "easy",
        recentRunsLast7Days: 3
    )

    private func model(_ headline: String = "Steady 5K", source: PostRunDebriefModel.Source = .ai) -> PostRunDebriefModel {
        PostRunDebriefModel(headline: headline, debrief: "Even pace.", tomorrow: "Rest day.", planImpact: nil, source: source)
    }

    private func makeRun() -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: 150,
            routePoints: [],
            routeMatchResult: nil,
            syncedAt: nil
        )
    }

    func testFirstCompleteDebriefWinsAndIsPersistedOnce() async {
        let first = FakeGenerator(.debrief(model("First")))
        let second = FakeGenerator(.debrief(model("Second")))
        var persisted: [PostRunDebriefModel] = []

        let result = await RunDebriefPipeline.debrief(
            for: input, run: makeRun(), generators: [first, second], persist: { persisted.append($0) }
        )

        XCTAssertEqual(result.headline, "First")
        XCTAssertEqual(persisted, [result])
        XCTAssertEqual(second.calls, 0)
    }

    func testSkippedFailedAndIncompleteGeneratorsFallThroughInOrder() async {
        let skipped = FakeGenerator(.skip)
        let failed = FakeGenerator(.fail(SomeError()))
        let timedOut = FakeGenerator(.fail(RunDebriefTimeoutError()))
        let incomplete = FakeGenerator(.debrief(model("   ")))
        let working = FakeGenerator(.debrief(model("Works")))

        let result = await RunDebriefPipeline.debrief(
            for: input, run: makeRun(), generators: [skipped, failed, timedOut, incomplete, working]
        )

        XCTAssertEqual(result.headline, "Works")
        XCTAssertEqual([skipped, failed, timedOut, incomplete, working].map(\.calls), [1, 1, 1, 1, 1])
    }

    func testNoWorkingGeneratorReturnsFallbackWithoutPersisting() async {
        var persisted = 0
        let result = await RunDebriefPipeline.debrief(
            for: input,
            run: makeRun(),
            generators: [FakeGenerator(.fail(SomeError())), FakeGenerator(.skip)],
            persist: { _ in persisted += 1 }
        )

        XCTAssertEqual(result.source, .fallback)
        XCTAssertEqual(persisted, 0)
    }

    func testCancellationStopsAtOnceWithFallback() async {
        let later = FakeGenerator(.debrief(model()))
        let result = await RunDebriefPipeline.debrief(
            for: input, run: makeRun(), generators: [FakeGenerator(.fail(CancellationError())), later]
        )

        XCTAssertEqual(result.source, .fallback)
        XCTAssertEqual(later.calls, 0)
    }

    func testGeneratedTextIsTrimmed() async {
        let padded = PostRunDebriefModel(headline: " Nice run \n", debrief: "\tEven pace. ", tomorrow: " Rest. ", planImpact: "none", source: .ai)
        let result = await RunDebriefPipeline.debrief(for: input, run: makeRun(), generators: [FakeGenerator(.debrief(padded))])

        XCTAssertEqual(result, PostRunDebriefModel(headline: "Nice run", debrief: "Even pace.", tomorrow: "Rest.", planImpact: "none", source: .ai))
    }
}
