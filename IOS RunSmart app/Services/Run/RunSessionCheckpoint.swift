import Foundation

/// Snapshot of an in-progress run, written to disk so a crash or an iOS kill does
/// not lose it. `RunRecorder` keeps its live state in memory only; this is the
/// minimum needed to rebuild that state (or save the run as it stood) on relaunch.
struct RunSessionCheckpoint: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = RunSessionCheckpoint.currentSchemaVersion
    var startedAt: Date
    var accumulatedPausedSeconds: TimeInterval
    var pausedAt: Date?
    var wasPaused: Bool
    var routePoints: [RunRoutePoint]
    var distanceMeters: Double
    var workoutTitle: String?
    var savedAt: Date
    /// Closed pauses so far. Optional so checkpoints written before this field existed still load.
    var pauseIntervals: [RunPauseInterval]? = nil
    /// Planned-workout guide with its step start points. Optional so older checkpoints still load;
    /// the guide catches up from the recovered moving time and distance when the run resumes.
    var workoutGuide: WorkoutGuide? = nil

    /// Moving time as it stood when the checkpoint was written.
    var movingSecondsAtSave: TimeInterval {
        RunRecorder.movingDuration(
            startedAt: startedAt,
            endedAt: savedAt,
            accumulatedPausedSeconds: accumulatedPausedSeconds,
            activePauseStartedAt: wasPaused ? pausedAt : nil
        )
    }

    /// A checkpoint is only trusted when its fields agree with each other. Anything
    /// else (unknown schema, clock-inconsistent dates, negative or non-finite
    /// totals) is dropped rather than rebuilt into a wrong run.
    var isConsistent: Bool {
        guard schemaVersion == Self.currentSchemaVersion else { return false }
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return false }
        guard accumulatedPausedSeconds.isFinite, accumulatedPausedSeconds >= 0 else { return false }
        guard startedAt <= savedAt else { return false }
        guard accumulatedPausedSeconds <= savedAt.timeIntervalSince(startedAt) else { return false }
        if let pausedAt, pausedAt < startedAt || pausedAt > savedAt { return false }
        return true
    }
}

/// Reads and writes the single active-run checkpoint as a JSON file in Application
/// Support. Route points can run to megabytes on a long run, which is why this is a
/// file and not a `UserDefaults` value like the rest of `RunSmartLocalStore`.
/// A nil `directoryURL` makes the store inert (writes are dropped, reads return nil).
///
/// `save` returns immediately: the caller hands over a value-type snapshot and encoding
/// plus the atomic file write happen on one process-wide serial queue. `delete` waits. Sharing the queue across instances keeps every operation on the file in
/// issue order, so a delete can never be overtaken by an earlier write. `load` runs on
/// the same queue, so it always sees pending writes; tests call `flush()` before
/// inspecting the file directly.
struct RunCheckpointStore {
    static let fileName = "active-run-checkpoint.json"

    private static let queue = DispatchQueue(label: "com.runsmart.run-checkpoint", qos: .utility)

    /// Blocks until every queued save and delete has finished.
    static func flush() {
        queue.sync {}
    }

    /// Production store. Inert while running under XCTest so existing recorder tests,
    /// which build `RunRecorder()` and pause/finish it, never touch the real
    /// Application Support directory or leak a checkpoint into the next test.
    /// Tests that exercise checkpoints inject their own temp-directory store.
    static let shared: RunCheckpointStore = {
        if NSClassFromString("XCTestCase") != nil {
            return RunCheckpointStore(directoryURL: nil)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return RunCheckpointStore(directoryURL: base)
    }()

    let directoryURL: URL?

    init(directoryURL: URL?) {
        self.directoryURL = directoryURL
    }

    private var fileURL: URL? {
        directoryURL?.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    func save(_ checkpoint: RunSessionCheckpoint) {
        guard let directoryURL, let fileURL else { return }
        Self.queue.async {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(checkpoint)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // A failed checkpoint write must never interrupt a live run.
            }
        }
    }

    /// Returns the stored checkpoint, or nil when none exists. A file that cannot be
    /// decoded, has an unknown schema version or is internally inconsistent is deleted.
    func load() -> RunSessionCheckpoint? {
        guard let fileURL else { return nil }
        return Self.queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            guard let checkpoint = try? JSONDecoder().decode(RunSessionCheckpoint.self, from: data),
                  checkpoint.isConsistent else {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            return checkpoint
        }
    }

    /// Synchronous, and still ordered after every earlier queued write. `finish()` and
    /// `saveRecoveredRun()` save the run first and delete the checkpoint second; if the
    /// delete were still queued when the app is killed, the next launch would offer the
    /// already saved run again.
    func delete() {
        guard let fileURL else { return }
        Self.queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
