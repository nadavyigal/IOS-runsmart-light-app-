import Foundation

/// A pace window in seconds per kilometre. `fast` is the smaller number.
struct GuidePaceBand: Codable, Equatable {
    var fast: Double
    var slow: Double

    /// Plan paces are a single number, so the window is that pace plus or minus `halfWidth`.
    init(center: Double, halfWidth: Double = 5) {
        fast = center - halfWidth
        slow = center + halfWidth
    }

    var label: String {
        "\(RunRecorder.paceLabel(secondsPerKm: fast)) to \(RunRecorder.paceLabel(secondsPerKm: slow))"
    }
}

/// One stage of a planned workout, in the order it is run. Built by
/// `StructuredWorkoutFactory` from the same data as the pre-run step list.
struct GuideStep: Codable, Equatable {
    enum Kind: String, Codable {
        case warmup, work, recovery, cooldown, steady
    }

    enum Target: Codable, Equatable {
        case distance(meters: Double)
        case duration(seconds: Double)
    }

    var kind: Kind
    var target: Target
    var paceBand: GuidePaceBand?
    /// 1-based rep number and rep count, only for work reps of a repeat set.
    var repIndex: Int?
    var repTotal: Int?

    var kindLabel: String {
        switch kind {
        case .warmup: "Warm up"
        case .work: "Work"
        case .recovery: "Recovery"
        case .cooldown: "Cool down"
        case .steady: "Steady"
        }
    }

    /// "Rep 3 of 6 · Work", or just the kind for steps outside a repeat set.
    var title: String {
        if let repIndex, let repTotal { return "Rep \(repIndex) of \(repTotal) · \(kindLabel)" }
        return kindLabel
    }

    /// Short preview for "Next: ...", for example "90 s recovery" or "400 m work".
    var previewLabel: String {
        "\(WorkoutGuideFormat.shortTarget(target)) \(kindLabel.lowercased())"
    }

    /// Spoken at the start of the step, for example
    /// "Rep 3 of 6. 400 metres at 4:30 to 4:40 per kilometre."
    var spokenStart: String {
        var lead: String
        if let repIndex, let repTotal {
            lead = "Rep \(repIndex) of \(repTotal)."
        } else {
            switch kind {
            case .warmup: lead = "Warm up."
            case .work: lead = "Work."
            case .recovery: lead = "Recovery."
            case .cooldown: lead = "Cool down."
            case .steady: lead = "Steady run."
            }
        }
        var text = "\(lead) \(WorkoutGuideFormat.spokenTarget(target))"
        if let paceBand { text += " at \(paceBand.label) per kilometre" }
        return text + "."
    }
}

enum WorkoutGuideFormat {
    static func shortTarget(_ target: GuideStep.Target) -> String {
        switch target {
        case .distance(let meters):
            return meters >= 1_000 ? String(format: "%g km", (meters / 100).rounded() / 10) : "\(Int(meters.rounded())) m"
        case .duration(let seconds):
            let total = Int(seconds.rounded())
            return total >= 120 && total % 60 == 0 ? "\(total / 60) min" : "\(total) s"
        }
    }

    static func spokenTarget(_ target: GuideStep.Target) -> String {
        switch target {
        case .distance(let meters):
            if meters >= 1_000 {
                let km = (meters / 100).rounded() / 10
                return String(format: "%g %@", km, km == 1 ? "kilometre" : "kilometres")
            }
            return "\(Int(meters.rounded())) metres"
        case .duration(let seconds):
            let total = Int(seconds.rounded())
            let minutes = total / 60
            let rest = total % 60
            if total < 120, rest != 0 || minutes == 0 { return "\(total) seconds" }
            let minuteText = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
            return rest == 0 ? minuteText : "\(minuteText) \(rest) seconds"
        }
    }

    /// "400 m left", "1.2 km left" or "1:30 left".
    static func remaining(meters: Double?, seconds: Double?) -> String? {
        if let meters {
            if meters >= 1_000 { return String(format: "%.1f km left", meters / 1_000) }
            return "\(Int(meters.rounded(.up))) m left"
        }
        if let seconds {
            let total = Int(seconds.rounded(.up))
            return String(format: "%d:%02d left", total / 60, total % 60)
        }
        return nil
    }
}

/// Follows a planned workout during a run. It is fed the recorder's moving time and
/// distance, which already exclude paused and auto-paused time, so a pause cannot
/// advance a step. A step ends when its own target (distance or duration) is reached.
///
/// Only the step start points are state, and they are small and `Codable`, so the
/// recorder checkpoint can restore the guide after a crash. Nothing here invents
/// data: it follows the steps it is given and says nothing about pace when a step has
/// no pace band or the recorder has no current pace.
struct WorkoutGuide: Codable, Equatable {
    struct Snapshot: Codable, Equatable {
        var distance: Double
        var movingTime: TimeInterval
    }

    enum PaceStatus: Equatable {
        case inRange, tooFast, tooSlow
    }

    struct Announcement: Equatable {
        var text: String
        /// Pace reminders are dropped when a distance cue is speaking at the same moment.
        var isReminder: Bool
    }

    struct Progress: Equatable {
        var index: Int
        var count: Int
        var step: GuideStep
        var remainingMeters: Double?
        var remainingSeconds: Double?
        var next: GuideStep?
    }

    /// Distance a runner may be outside the band before it counts as off pace.
    static let paceTolerance = 5.0
    static let reminderInterval: TimeInterval = 60
    /// Moving seconds after a step starts before pace reminders may speak. The current pace
    /// is a 30 second window, so it is not meaningful right after a rep begins.
    static let reminderGrace: TimeInterval = 20
    static let maximumSteps = 200

    let steps: [GuideStep]
    private(set) var starts: [Snapshot] = [Snapshot(distance: 0, movingTime: 0)]
    private(set) var finishedAt: Snapshot?
    private(set) var last = Snapshot(distance: 0, movingTime: 0)
    private var announcedCount = 0
    private var completionAnnounced = false
    private var lastReminderAt: TimeInterval?

    init?(steps: [GuideStep]) {
        guard !steps.isEmpty, steps.count <= Self.maximumSteps else { return nil }
        self.steps = steps
    }

    var isFinished: Bool { finishedAt != nil }
    var currentIndex: Int? { isFinished ? nil : starts.count - 1 }
    var currentStep: GuideStep? { currentIndex.map { steps[$0] } }

    var progress: Progress? {
        guard let index = currentIndex else { return nil }
        let step = steps[index]
        let start = starts[index]
        var meters: Double?
        var seconds: Double?
        switch step.target {
        case .distance(let target):
            meters = max(0, target - (last.distance - start.distance))
        case .duration(let target):
            seconds = max(0, target - (last.movingTime - start.movingTime))
        }
        return Progress(
            index: index,
            count: steps.count,
            step: step,
            remainingMeters: meters,
            remainingSeconds: seconds,
            next: index + 1 < steps.count ? steps[index + 1] : nil
        )
    }

    /// Nil when the pace is unknown, the step has no band, or the workout is over.
    func paceStatus(currentPace: TimeInterval?) -> PaceStatus? {
        guard let currentPace, currentPace.isFinite, currentPace > 0,
              let band = currentStep?.paceBand else { return nil }
        if currentPace < band.fast - Self.paceTolerance { return .tooFast }
        if currentPace > band.slow + Self.paceTolerance { return .tooSlow }
        return .inRange
    }

    /// Advances the guide and returns what to say. Call once a second while recording.
    mutating func update(distance: Double, movingTime: TimeInterval, currentPace: TimeInterval? = nil) -> [Announcement] {
        guard distance.isFinite, movingTime.isFinite, distance >= 0, movingTime >= 0 else { return [] }
        last = Snapshot(distance: max(distance, last.distance), movingTime: max(movingTime, last.movingTime))
        let startCount = starts.count

        while finishedAt == nil {
            let index = starts.count - 1
            guard let end = endOfStep(index) else { break }
            if index == steps.count - 1 {
                finishedAt = end
            } else {
                starts.append(end)
            }
        }
        if starts.count != startCount || isFinished { lastReminderAt = nil }

        if isFinished {
            guard !completionAnnounced else { return [] }
            completionAnnounced = true
            announcedCount = steps.count
            return [Announcement(text: "Workout complete.", isReminder: false)]
        }
        if announcedCount < starts.count {
            announcedCount = starts.count
            return [Announcement(text: steps[starts.count - 1].spokenStart, isReminder: false)]
        }
        return reminder(currentPace: currentPace).map { [$0] } ?? []
    }

    /// Where the step ends if the latest sample has reached its target. The unit the step
    /// is measured in is exact, so a 400 m rep cannot drift by a GPS fix per rep.
    private func endOfStep(_ index: Int) -> Snapshot? {
        let start = starts[index]
        switch steps[index].target {
        case .distance(let meters):
            guard last.distance - start.distance >= meters else { return nil }
            return Snapshot(distance: start.distance + meters, movingTime: last.movingTime)
        case .duration(let seconds):
            guard last.movingTime - start.movingTime >= seconds else { return nil }
            return Snapshot(distance: last.distance, movingTime: start.movingTime + seconds)
        }
    }

    private mutating func reminder(currentPace: TimeInterval?) -> Announcement? {
        guard let index = currentIndex, steps[index].kind == .work,
              last.movingTime - starts[index].movingTime >= Self.reminderGrace,
              let status = paceStatus(currentPace: currentPace), status != .inRange else { return nil }
        if let lastReminderAt, last.movingTime - lastReminderAt < Self.reminderInterval { return nil }
        lastReminderAt = last.movingTime
        return Announcement(text: status == .tooFast ? "Ease off." : "Pick it up.", isReminder: true)
    }
}
