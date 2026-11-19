import ActivityKit
import Foundation

/// Shared Live Activity payload for an in-progress run (WP-38 S14b).
///
/// The state carries raw numbers, not preformatted strings, so the clock can be drawn by the
/// system timer view (no per-second updates) and the extension owns all formatting.
/// Decoding is tolerant: an activity written by an older build decodes with defaults, and
/// `schemaVersion` tells the app to end it instead of rendering half a state.
struct RunRecordingLiveActivityAttributes: ActivityAttributes {
    /// Bump whenever `ContentState` or the attributes change shape.
    static let currentSchemaVersion = 2

    enum Phase: String, Codable, Hashable {
        /// Recording, but GPS is weak or missing since Start.
        case acquiring
        case running
        case paused
        case autoPaused
        case finished

        var isClockRunning: Bool { self == .running || self == .acquiring }
        var isPausedLike: Bool { self == .paused || self == .autoPaused }

        var statusLabel: String {
            switch self {
            case .acquiring: "Finding GPS"
            case .running: "Recording"
            case .paused: "Paused"
            case .autoPaused: "Auto-paused"
            case .finished: "Finished"
            }
        }
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        /// `now - movingSeconds` when the state was built. With `phase.isClockRunning` the
        /// timer view counts up from here; otherwise it shows `movingSeconds` frozen.
        var timerStart: Date
        var movingSeconds: Int
        var distanceMeters: Double
        var currentPaceSecondsPerKm: Int?
        var averagePaceSecondsPerKm: Int?
        var lastSplitKilometer: Int?
        var lastSplitPaceSecondsPerKm: Int?
        var gpsAccuracyMeters: Int?

        init(
            phase: Phase,
            timerStart: Date,
            movingSeconds: Int,
            distanceMeters: Double,
            currentPaceSecondsPerKm: Int? = nil,
            averagePaceSecondsPerKm: Int? = nil,
            lastSplitKilometer: Int? = nil,
            lastSplitPaceSecondsPerKm: Int? = nil,
            gpsAccuracyMeters: Int? = nil
        ) {
            self.phase = phase
            self.timerStart = timerStart
            self.movingSeconds = movingSeconds
            self.distanceMeters = distanceMeters
            self.currentPaceSecondsPerKm = currentPaceSecondsPerKm
            self.averagePaceSecondsPerKm = averagePaceSecondsPerKm
            self.lastSplitKilometer = lastSplitKilometer
            self.lastSplitPaceSecondsPerKm = lastSplitPaceSecondsPerKm
            self.gpsAccuracyMeters = gpsAccuracyMeters
        }

        private enum CodingKeys: String, CodingKey {
            case phase, timerStart, movingSeconds, distanceMeters, currentPaceSecondsPerKm
            case averagePaceSecondsPerKm, lastSplitKilometer, lastSplitPaceSecondsPerKm, gpsAccuracyMeters
            case isPaused // schema 1
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let legacyPaused = try c.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
            phase = try c.decodeIfPresent(Phase.self, forKey: .phase) ?? (legacyPaused ? .paused : .running)
            timerStart = try c.decodeIfPresent(Date.self, forKey: .timerStart) ?? Date()
            movingSeconds = try c.decodeIfPresent(Int.self, forKey: .movingSeconds) ?? 0
            distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
            currentPaceSecondsPerKm = try c.decodeIfPresent(Int.self, forKey: .currentPaceSecondsPerKm)
            averagePaceSecondsPerKm = try c.decodeIfPresent(Int.self, forKey: .averagePaceSecondsPerKm)
            lastSplitKilometer = try c.decodeIfPresent(Int.self, forKey: .lastSplitKilometer)
            lastSplitPaceSecondsPerKm = try c.decodeIfPresent(Int.self, forKey: .lastSplitPaceSecondsPerKm)
            gpsAccuracyMeters = try c.decodeIfPresent(Int.self, forKey: .gpsAccuracyMeters)
        }

        nonisolated func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(phase, forKey: .phase)
            try c.encode(timerStart, forKey: .timerStart)
            try c.encode(movingSeconds, forKey: .movingSeconds)
            try c.encode(distanceMeters, forKey: .distanceMeters)
            try c.encodeIfPresent(currentPaceSecondsPerKm, forKey: .currentPaceSecondsPerKm)
            try c.encodeIfPresent(averagePaceSecondsPerKm, forKey: .averagePaceSecondsPerKm)
            try c.encodeIfPresent(lastSplitKilometer, forKey: .lastSplitKilometer)
            try c.encodeIfPresent(lastSplitPaceSecondsPerKm, forKey: .lastSplitPaceSecondsPerKm)
            try c.encodeIfPresent(gpsAccuracyMeters, forKey: .gpsAccuracyMeters)
        }

        /// End of the moving-time range the timer view shows when the clock is stopped.
        var frozenClockEnd: Date { timerStart.addingTimeInterval(TimeInterval(movingSeconds)) }
    }

    var schemaVersion: Int
    /// The recorder's `startedAt`; ties the activity to one run across app launches.
    var runStartedAt: Date
    var workoutTitle: String
    /// Planned distance for the run, nil for free runs or plans without a numeric distance.
    var goalDistanceMeters: Double?
    /// Planned target pace, nil for free runs or plans without a target.
    var targetPaceSecondsPerKm: Int?

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runStartedAt: Date,
        workoutTitle: String,
        goalDistanceMeters: Double? = nil,
        targetPaceSecondsPerKm: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.runStartedAt = runStartedAt
        self.workoutTitle = workoutTitle
        self.goalDistanceMeters = goalDistanceMeters
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, runStartedAt, workoutTitle, goalDistanceMeters, targetPaceSecondsPerKm
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        runStartedAt = try c.decodeIfPresent(Date.self, forKey: .runStartedAt) ?? .distantPast
        workoutTitle = try c.decodeIfPresent(String.self, forKey: .workoutTitle) ?? "Run"
        goalDistanceMeters = try c.decodeIfPresent(Double.self, forKey: .goalDistanceMeters)
        targetPaceSecondsPerKm = try c.decodeIfPresent(Int.self, forKey: .targetPaceSecondsPerKm)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(runStartedAt, forKey: .runStartedAt)
        try c.encode(workoutTitle, forKey: .workoutTitle)
        try c.encodeIfPresent(goalDistanceMeters, forKey: .goalDistanceMeters)
        try c.encodeIfPresent(targetPaceSecondsPerKm, forKey: .targetPaceSecondsPerKm)
    }
}

/// Formatting shared by the extension views and the app's tests.
enum RunLiveActivityFormat {
    static func distanceKm(_ meters: Double) -> String {
        String(format: "%.2f", max(0, meters) / 1_000)
    }

    static func pace(_ secondsPerKm: Int?) -> String {
        guard let secondsPerKm, secondsPerKm > 0 else { return "--" }
        return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
    }
}
