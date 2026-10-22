import AVFoundation
import Combine
import Foundation

struct RunCueSettings: Codable, Equatable {
    enum Cadence: String, Codable, CaseIterable, Identifiable {
        case kilometer, halfKilometer, fiveMinutes
        var id: String { rawValue }
        var label: String {
            switch self {
            case .kilometer: "Every 1 km"
            case .halfKilometer: "Every 0.5 km"
            case .fiveMinutes: "Every 5 min"
            }
        }
    }
    var enabled = true
    var cadence: Cadence = .kilometer
    var distance = true
    var pace = true
    var time = true

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: "runLocalCueSettings"),
              let settings = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return settings
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: "runLocalCueSettings")
    }
}

/// Uses moving time rather than wall time. No timer/network dependency, including while locked.
struct RunCueSchedule {
    private var previousDistance = 0.0
    private var previousTime = 0.0
    private var boundaryDistance = 0.0
    private var boundaryTime = 0.0
    private var cadence: RunCueSettings.Cadence?
    private var consumedBucket = 0

    mutating func reset(distance: Double, movingTime: TimeInterval) {
        previousDistance = distance
        previousTime = movingTime
        boundaryDistance = distance
        boundaryTime = movingTime
        cadence = nil
        consumedBucket = 0
    }

    mutating func update(distance: Double, movingTime: TimeInterval, settings: RunCueSettings) -> String? {
        guard distance.isFinite, movingTime.isFinite, distance >= 0, movingTime >= 0 else { return nil }
        if let cadence, cadence != settings.cadence {
            reset(distance: distance, movingTime: movingTime)
            self.cadence = settings.cadence
            return nil
        }
        cadence = settings.cadence
        let step = cadence == .halfKilometer ? 500.0 : 1_000.0
        let oldBucket = cadence == .fiveMinutes ? Int(previousTime / 300) : Int(previousDistance / step)
        let bucket = cadence == .fiveMinutes ? Int(movingTime / 300) : Int(distance / step)
        let sampleDistance = previousDistance
        let sampleTime = previousTime
        previousDistance = distance
        previousTime = movingTime
        guard bucket > max(oldBucket, consumedBucket) else { return nil }
        consumedBucket = bucket
        // Interpolate the exact boundary; GPS callbacks rarely land on 1000.0 m.
        let fraction: Double
        if cadence == .fiveMinutes {
            fraction = movingTime > sampleTime ? (Double(bucket) * 300 - sampleTime) / (movingTime - sampleTime) : 1
        } else {
            fraction = distance > sampleDistance ? (Double(bucket) * step - sampleDistance) / (distance - sampleDistance) : 1
        }
        let crossingDistance = sampleDistance + fraction * (distance - sampleDistance)
        let crossingTime = sampleTime + fraction * (movingTime - sampleTime)
        let meters = crossingDistance - boundaryDistance
        let seconds = crossingTime - boundaryTime
        boundaryDistance = crossingDistance
        boundaryTime = crossingTime
        guard settings.enabled else { return nil }
        var parts: [String] = []
        if settings.distance {
            let km = crossingDistance / 1_000
            parts.append(String(format: "%g %@", km, km == 1 ? "kilometer" : "kilometers"))
        }
        if settings.pace, meters >= 20, seconds > 0 {
            parts.append("Split pace \(Self.duration(seconds / (meters / 1_000))) per kilometer")
        }
        if settings.time { parts.append("Moving time \(Self.duration(crossingTime))") }
        return parts.isEmpty ? nil : parts.joined(separator: ". ") + "."
    }

    mutating func changeCadence(_ newCadence: RunCueSettings.Cadence) {
        cadence = newCadence
        consumedBucket = newCadence == .fiveMinutes ? Int(previousTime / 300) : Int(previousDistance / (newCadence == .halfKilometer ? 500 : 1_000))
        boundaryDistance = previousDistance
        boundaryTime = previousTime
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let remainder = total % 60
        return "\(minutes) minutes \(remainder) seconds"
    }
}

@MainActor
final class LocalRunCueService: NSObject, ObservableObject {
    static let shared = LocalRunCueService()
    @Published var settings: RunCueSettings {
        didSet {
            settings.save()
            if oldValue.cadence != settings.cadence { schedule.changeCadence(settings.cadence) }
            if !settings.enabled { synthesizer.stopSpeaking(at: .immediate) }
        }
    }
    var isEnabled: Bool { settings.enabled }
    var isSpeaking: Bool { synthesizer.isSpeaking }
    private let synthesizer = AVSpeechSynthesizer()
    private var schedule = RunCueSchedule()
    /// Injection avoids starting an audio device in recorder unit tests.
    var speechHandler: ((String) -> Void)?

    private override init() {
        settings = .load()
        super.init()
        // Apple manages the speech session, mixing/ducking and interruptions only
        // while an utterance plays. Never hold a ducking session for an entire run.
        synthesizer.usesApplicationAudioSession = false
    }

    func setEnabled(_ enabled: Bool) { settings.enabled = enabled }
    func begin(distance: Double = 0, movingTime: TimeInterval = 0, recovered: Bool = false) {
        schedule.reset(distance: distance, movingTime: movingTime)
        announce(recovered ? "Run restored. Paused." : "Run started.")
    }
    func update(distance: Double, movingTime: TimeInterval, guide: [WorkoutGuide.Announcement] = []) {
        let split = schedule.update(distance: distance, movingTime: movingTime, settings: settings)
        if let text = Self.combinedText(split: split, guide: guide) {
            // A guide-only cue waits for speech in progress; a split cue keeps its usual priority and
            // carries any step cue with it, so the two never cut each other off in the same second.
            announce(text, queued: split == nil)
        }
    }

    /// One utterance per tick: the split cue first, then the step cue. Pace reminders are dropped
    /// when a split cue is speaking, because the step change that matters is already in it.
    static func combinedText(split: String?, guide: [WorkoutGuide.Announcement]) -> String? {
        let steps = guide.filter { !$0.isReminder }.map(\.text)
        let reminders = guide.filter(\.isReminder).map(\.text)
        let guideText = (steps.isEmpty ? (split == nil ? reminders : []) : steps).joined(separator: " ")
        let parts = [split, guideText.isEmpty ? nil : guideText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func announce(_ text: String, queued: Bool = false) {
        guard settings.enabled else { return }
        VoiceCoachService.shared.cancelPlaybackForLocalCue()
        if let speechHandler { speechHandler(text); return }
        if !queued { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        // A built-in voice works without an account, downloaded enhanced voice, or network.
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
