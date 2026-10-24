import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

@MainActor
final class RunAutoPauseTests: XCTestCase {
    func testStopDebounceAndResume() {
        var detector = RunAutoPauseDetector()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(detector.update(speed: 0.2, at: start, isAutoPaused: false))
        XCTAssertNil(detector.update(speed: 0, at: start.addingTimeInterval(7), isAutoPaused: false))
        XCTAssertEqual(detector.update(speed: 0, at: start.addingTimeInterval(8), isAutoPaused: false), .pause(since: start))
        XCTAssertNil(detector.update(speed: 0.1, at: start.addingTimeInterval(30), isAutoPaused: true))
        XCTAssertEqual(detector.update(speed: 2, at: start.addingTimeInterval(31), isAutoPaused: true), .resume)
    }

    func testUnknownSpeedAndStaleGapCannotInventStop() {
        var detector = RunAutoPauseDetector()
        let start = Date()
        XCTAssertNil(detector.update(speed: 0, at: start, isAutoPaused: false))
        XCTAssertNil(detector.update(speed: -1, at: start.addingTimeInterval(8), isAutoPaused: false))
        XCTAssertNil(detector.update(speed: 0, at: start.addingTimeInterval(9), isAutoPaused: false))
        XCTAssertNil(detector.update(speed: 0, at: start.addingTimeInterval(30), isAutoPaused: false))
        XCTAssertNil(detector.update(speed: .nan, at: start.addingTimeInterval(31), isAutoPaused: false))
    }

    func testRecorderAutoPauseExcludesThirtySecondStopAndManualPauseStaysPaused() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { RunCheckpointStore.flush(); try? FileManager.default.removeItem(at: directory) }
        let recorder = RunRecorder(store: .shared, checkpointStore: RunCheckpointStore(directoryURL: directory))
        recorder.authorizationStatusProvider = { .authorizedWhenInUse }
        recorder.autoPauseEnabledProvider = { true }
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let start = Date()
        func fix(_ seconds: Double, _ meters: Double, _ speed: Double) {
            let stamp = start.addingTimeInterval(seconds)
            let location = CLLocation(coordinate: .init(latitude: 32 + meters / 111_000, longitude: 34), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, course: 0, speed: speed, timestamp: stamp)
            recorder.handleLocationUpdates([location], now: stamp)
        }
        fix(0, 0, 3)
        fix(10, 30, 3)
        fix(11, 30, 0)
        fix(19, 30, 0)
        XCTAssertEqual(recorder.phase, .paused)
        XCTAssertTrue(recorder.isAutoPaused)
        let before = recorder.distanceMeters
        fix(40, 30, 0)
        fix(41, 35, 3)
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertFalse(recorder.isAutoPaused)
        XCTAssertEqual(recorder.distanceMeters, before, accuracy: 0.01)
        fix(51, 65, 3)
        XCTAssertEqual(recorder.movingSeconds, 21, accuracy: 0.01)
        recorder.pause()
        fix(52, 70, 3)
        XCTAssertEqual(recorder.phase, .paused)
        XCTAssertFalse(recorder.isAutoPaused)
        recorder.discard()
    }

    func testDelayedStationaryFixCannotPauseBeforeRunStarted() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { RunCheckpointStore.flush(); try? FileManager.default.removeItem(at: directory) }
        let recorder = RunRecorder(store: .shared, checkpointStore: RunCheckpointStore(directoryURL: directory))
        recorder.authorizationStatusProvider = { .authorizedWhenInUse }
        recorder.autoPauseEnabledProvider = { true }
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let origin = Date()
        func deliver(fix: Double, callback: Double, speed: Double) {
            let point = CLLocation(coordinate: .init(latitude: 32, longitude: 34), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, course: -1, speed: speed, timestamp: origin.addingTimeInterval(fix))
            recorder.handleLocationUpdates([point], now: origin.addingTimeInterval(callback))
        }
        deliver(fix: 90, callback: 100, speed: 0)
        deliver(fix: 91, callback: 101, speed: 0)
        deliver(fix: 99, callback: 109, speed: 0)
        XCTAssertTrue(recorder.isAutoPaused)
        deliver(fix: 110, callback: 120, speed: 3)
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(recorder.movingSeconds, 10, accuracy: 0.01)
        recorder.discard()
    }

    func testDisabledPreferenceNeverPauses() {
        // Detector only participates when enabled; exercise the recorder boundary.
        let recorder = RunRecorder(store: .shared)
        recorder.authorizationStatusProvider = { .authorizedWhenInUse }
        recorder.autoPauseEnabledProvider = { false }
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let start = Date()
        for seconds in [0.0, 1, 10, 20] {
            let stamp = start.addingTimeInterval(seconds)
            recorder.handleLocationUpdates([CLLocation(coordinate: .init(latitude: 32, longitude: 34), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, course: -1, speed: 0, timestamp: stamp)], now: stamp)
        }
        XCTAssertEqual(recorder.phase, .recording)
        recorder.discard()
    }
}
