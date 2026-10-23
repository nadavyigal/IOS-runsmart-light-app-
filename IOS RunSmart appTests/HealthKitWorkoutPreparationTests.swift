import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class HealthKitWorkoutPreparationTests: XCTestCase {
    private enum Failure: Error { case rejected }

    func testFailedIdentityMetadataDiscardsAndCannotReachFinish() async {
        var steps: [String] = []
        do {
            try await HealthKitWorkoutPreparation.run(
                beginCollection: { steps.append("begin") },
                addMetadata: { steps.append("metadata"); throw Failure.rejected },
                discard: { steps.append("discard") }
            )
            steps.append("finish")
            XCTFail("Identity metadata failure must abort workout creation")
        } catch {}
        XCTAssertEqual(steps, ["begin", "metadata", "discard"])
    }

    func testFailedCollectionDiscardsWithoutAddingMetadataOrFinishing() async {
        var steps: [String] = []
        do {
            try await HealthKitWorkoutPreparation.run(
                beginCollection: { steps.append("begin"); throw Failure.rejected },
                addMetadata: { steps.append("metadata") },
                discard: { steps.append("discard") }
            )
            steps.append("finish")
            XCTFail("Failed collection must not continue")
        } catch {}
        XCTAssertEqual(steps, ["begin", "discard"])
    }

    func testSuccessfulPreparationKeepsMetadataBeforeFinish() async throws {
        var steps: [String] = []
        try await HealthKitWorkoutPreparation.run(
            beginCollection: { steps.append("begin") },
            addMetadata: { steps.append("metadata") },
            discard: { steps.append("discard") }
        )
        steps.append("finish")
        XCTAssertEqual(steps, ["begin", "metadata", "finish"])
    }
}
