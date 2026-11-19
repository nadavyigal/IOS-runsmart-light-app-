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
    static let currentSchemaVersion = 4

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

    /// A guided step can have no pace target, even when the workout has an overall target.
    nonisolated struct WorkoutStepPace: Codable, Hashable {
        let targetSecondsPerKm: Int?
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
        /// Show the km split chip until this time (one pop, then it hides on the next update).
        var splitHighlightUntil: Date?
        var workoutStepPace: WorkoutStepPace?

        init(
            phase: Phase,
            timerStart: Date,
            movingSeconds: Int,
            distanceMeters: Double,
            currentPaceSecondsPerKm: Int? = nil,
            averagePaceSecondsPerKm: Int? = nil,
            lastSplitKilometer: Int? = nil,
            lastSplitPaceSecondsPerKm: Int? = nil,
            gpsAccuracyMeters: Int? = nil,
            splitHighlightUntil: Date? = nil,
            workoutStepPace: WorkoutStepPace? = nil
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
            self.splitHighlightUntil = splitHighlightUntil
            self.workoutStepPace = workoutStepPace
        }

        private enum CodingKeys: String, CodingKey {
            case phase, timerStart, movingSeconds, distanceMeters, currentPaceSecondsPerKm
            case averagePaceSecondsPerKm, lastSplitKilometer, lastSplitPaceSecondsPerKm, gpsAccuracyMeters, splitHighlightUntil
            case workoutStepPace
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
            splitHighlightUntil = try c.decodeIfPresent(Date.self, forKey: .splitHighlightUntil)
            workoutStepPace = try c.decodeIfPresent(WorkoutStepPace.self, forKey: .workoutStepPace)
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
            try c.encodeIfPresent(splitHighlightUntil, forKey: .splitHighlightUntil)
            try c.encodeIfPresent(workoutStepPace, forKey: .workoutStepPace)
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
    /// Keeps the pace layout across both paced and unpaced steps.
    var hasPacedSteps: Bool

    var usesPaceLayout: Bool { hasPacedSteps || (targetPaceSecondsPerKm ?? 0) > 0 }

    func liveTargetPace(for state: ContentState) -> Int? {
        if let step = state.workoutStepPace { return step.targetSecondsPerKm }
        return targetPaceSecondsPerKm.flatMap { $0 > 0 ? $0 : nil }
    }

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runStartedAt: Date,
        workoutTitle: String,
        goalDistanceMeters: Double? = nil,
        targetPaceSecondsPerKm: Int? = nil,
        hasPacedSteps: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.runStartedAt = runStartedAt
        self.workoutTitle = workoutTitle
        self.goalDistanceMeters = goalDistanceMeters
        self.targetPaceSecondsPerKm = targetPaceSecondsPerKm
        self.hasPacedSteps = hasPacedSteps
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, runStartedAt, workoutTitle, goalDistanceMeters, targetPaceSecondsPerKm, hasPacedSteps
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        runStartedAt = try c.decodeIfPresent(Date.self, forKey: .runStartedAt) ?? .distantPast
        workoutTitle = try c.decodeIfPresent(String.self, forKey: .workoutTitle) ?? "Run"
        goalDistanceMeters = try c.decodeIfPresent(Double.self, forKey: .goalDistanceMeters)
        targetPaceSecondsPerKm = try c.decodeIfPresent(Int.self, forKey: .targetPaceSecondsPerKm)
        hasPacedSteps = try c.decodeIfPresent(Bool.self, forKey: .hasPacedSteps) ?? false
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(runStartedAt, forKey: .runStartedAt)
        try c.encode(workoutTitle, forKey: .workoutTitle)
        try c.encodeIfPresent(goalDistanceMeters, forKey: .goalDistanceMeters)
        try c.encodeIfPresent(targetPaceSecondsPerKm, forKey: .targetPaceSecondsPerKm)
        try c.encode(hasPacedSteps, forKey: .hasPacedSteps)
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

/// Deep links from the Live Activity and the widget into the Run tab.
enum RunSmartRunDeepLink {
    static let live = URL(string: "runsmart://run/live")!
    static let debrief = URL(string: "runsmart://run/debrief")!
    static let start = URL(string: "runsmart://run/start")!

    static func isRunLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "runsmart" && url.host?.lowercased() == "run"
    }

    /// The finished card's link names its run, so the app can open that run's report even
    /// after the post-run summary was closed.
    static func debrief(runStartedAt: Date) -> URL {
        var components = URLComponents(url: debrief, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "started", value: String(Int(runStartedAt.timeIntervalSince1970.rounded())))]
        return components.url ?? debrief
    }

    /// The run start a debrief link names, nil for any other link.
    static func debriefRunStartedAt(_ url: URL) -> Date? {
        guard isRunLink(url), url.path == "/debrief",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "started" })?.value,
              let seconds = TimeInterval(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

/// How the current pace compares with the planned target (Direction B).
enum RunLiveActivityPaceTarget {
    /// Seconds either side of the target that still count as on target.
    static let band = 10

    enum Standing: Equatable { case onTarget, fast, slow, unknown }

    static func standing(pace: Int?, target: Int?) -> Standing {
        guard let pace, let target, pace > 0, target > 0 else { return .unknown }
        if pace < target - band { return .fast }
        if pace > target + band { return .slow }
        return .onTarget
    }

    /// "12 s faster than target", "8 s slower than target", "On target".
    static func deltaLabel(pace: Int?, target: Int?) -> String? {
        guard let pace, let target, pace > 0, target > 0 else { return nil }
        let delta = target - pace
        if abs(delta) <= band { return "On target" }
        return delta > 0 ? "\(delta) s faster than target" : "\(-delta) s slower than target"
    }

    static func rangeLabel(target: Int) -> String {
        "Target \(RunLiveActivityFormat.pace(target - band))–\(RunLiveActivityFormat.pace(target + band))"
    }
}
