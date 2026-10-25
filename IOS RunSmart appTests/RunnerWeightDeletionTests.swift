import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class RunnerWeightDeletionTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "RunnerWeightDeletionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDeleteClearsPublishedWeightAndAllStoredPreferences() async {
        let store = RunnerWeightStore(defaults: defaults, healthWeightReader: { _ in 72 })
        store.setManualWeightKg(70)
        store.markWeightSetupOffered()
        await store.requestHealthWeight()
        XCTAssertEqual(store.weightKg, 72)
        XCTAssertTrue(defaults.bool(forKey: "runCalories.healthWeightEnabled"))

        store.clearUserData()

        XCTAssertNil(store.manualWeightKg)
        XCTAssertNil(store.healthWeightKg)
        XCTAssertNil(store.weightKg)
        XCTAssertFalse(store.isReadingHealth)
        XCTAssertTrue(store.shouldOfferWeightSetup)
        for key in ["runCalories.manualWeightKg", "runCalories.healthWeightEnabled", "runCalories.weightSetupOffered"] {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
        XCTAssertNil(RunnerWeightStore(defaults: defaults).weightKg)
    }

    func testHealthRequestFinishingAfterDeletionCannotRestoreWeight() async {
        let gate = DeferredWeightRead()
        let store = RunnerWeightStore(defaults: defaults, healthWeightReader: { _ in await gate.read() })
        let read = Task { await store.requestHealthWeight() }
        await gate.waitUntilStarted()
        XCTAssertTrue(store.isReadingHealth)

        store.clearUserData()
        gate.complete(with: 72)
        await read.value

        XCTAssertNil(store.weightKg)
        XCTAssertNil(store.healthWeightKg)
        XCTAssertFalse(store.isReadingHealth)
        XCTAssertNil(defaults.object(forKey: "runCalories.healthWeightEnabled"))
    }

    func testOldReadCannotEndOrOverwriteNewReadAfterDeletion() async {
        let first = DeferredWeightRead()
        let second = DeferredWeightRead()
        var count = 0
        let store = RunnerWeightStore(defaults: defaults, healthWeightReader: { _ in
            count += 1
            return await (count == 1 ? first : second).read()
        })
        let oldRead = Task { await store.requestHealthWeight() }
        await first.waitUntilStarted()
        store.clearUserData()
        let newRead = Task { await store.requestHealthWeight() }
        await second.waitUntilStarted()

        first.complete(with: 72)
        await oldRead.value
        XCTAssertTrue(store.isReadingHealth)
        XCTAssertNil(store.weightKg)
        second.complete(with: 80)
        await newRead.value
        XCTAssertFalse(store.isReadingHealth)
        XCTAssertEqual(store.weightKg, 80)
    }

    func testHealthOptOutInvalidatesInflightRead() async {
        let gate = DeferredWeightRead()
        let store = RunnerWeightStore(defaults: defaults, healthWeightReader: { _ in await gate.read() })
        store.setManualWeightKg(70)
        let read = Task { await store.requestHealthWeight() }
        await gate.waitUntilStarted()
        store.stopUsingHealthWeight()
        gate.complete(with: 72)
        await read.value

        XCTAssertEqual(store.weightKg, 70)
        XCTAssertNil(store.healthWeightKg)
        XCTAssertFalse(store.isReadingHealth)
        XCTAssertFalse(defaults.bool(forKey: "runCalories.healthWeightEnabled"))
    }

    func testRefreshFinishingAfterDeletionCannotRestoreWeight() async {
        let gate = DeferredWeightRead()
        defaults.set(true, forKey: "runCalories.healthWeightEnabled")
        let store = RunnerWeightStore(defaults: defaults, healthWeightReader: { requested in
            XCTAssertFalse(requested)
            return await gate.read()
        })
        let read = Task { await store.refreshHealthWeightIfEnabled() }
        await gate.waitUntilStarted()
        store.clearUserData()
        gate.complete(with: 72)
        await read.value

        XCTAssertNil(store.weightKg)
        XCTAssertFalse(store.isReadingHealth)
        XCTAssertNil(defaults.object(forKey: "runCalories.healthWeightEnabled"))
    }
}

@MainActor
private final class DeferredWeightRead {
    private var readContinuation: CheckedContinuation<Double?, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func read() async -> Double? {
        await withCheckedContinuation { continuation in
            readContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        if readContinuation != nil { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func complete(with value: Double?) {
        readContinuation?.resume(returning: value)
        readContinuation = nil
    }
}
