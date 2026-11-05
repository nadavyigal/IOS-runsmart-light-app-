import AVFoundation
import Foundation

/// The one coaching-tone list. Stored Supabase values stay the old four-style
/// column. Legacy Strict and Direct stay readable. Direct was saved as
/// `supportive`, so a reloaded row cannot be told apart from Calm.
enum CoachingTone: String, CaseIterable, Identifiable, Equatable {
    case motivating
    case calm
    case technical

    static let options: [CoachingTone] = allCases

    var id: String { rawValue }

    var label: String {
        switch self {
        case .motivating: "Motivating"
        case .calm: "Calm"
        case .technical: "Technical"
        }
    }

    var detail: String {
        switch self {
        case .motivating: "Short push, same facts"
        case .calm: "Quieter, same facts"
        case .technical: "Numbers first"
        }
    }

    var symbol: String {
        switch self {
        case .motivating: "bolt.fill"
        case .calm: "leaf.fill"
        case .technical: "chart.xyaxis.line"
        }
    }

    /// `profiles.coaching_style`.
    var storedStyle: String {
        switch self {
        case .motivating: "encouraging"
        case .calm: "supportive"
        case .technical: "analytical"
        }
    }

    /// Apple system voice. No extra provider and no key on the phone.
    /// Motivating keeps the default rate. Calm is slower. Technical is faster.
    var speechRate: Float {
        switch self {
        case .motivating: AVSpeechUtteranceDefaultSpeechRate
        case .calm: AVSpeechUtteranceDefaultSpeechRate * 0.88
        case .technical: AVSpeechUtteranceDefaultSpeechRate * 1.06
        }
    }

    var pitchMultiplier: Float {
        switch self {
        case .motivating: 1.04
        case .calm: 0.92
        case .technical: 1.0
        }
    }

    static func storedStyle(for raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("motivat") || s.contains("encourag") { return "encouraging" }
        if s.contains("techni") || s.contains("analytic") { return "analytical" }
        if s.contains("strict") || s.contains("challeng") { return "challenging" }
        if s.contains("calm") || s.contains("support") || s.contains("direct") { return "supportive" }
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "encouraging" }
        return "supportive"
    }

    /// What the profile tile shows. Strict and Direct stay words the runner used.
    static func displayLabel(for raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("strict") || s.contains("challeng") { return "Strict" }
        if s.contains("direct") { return "Direct" }
        return voiceTone(for: raw).label
    }

    /// Tone used for cue wording and the system voice.
    /// Old Strict (`challenging`) speaks as Motivating. Old Direct speaks as Calm.
    static func voiceTone(for raw: String) -> CoachingTone {
        switch storedStyle(for: raw) {
        case "analytical": .technical
        case "encouraging": .motivating
        case "challenging": .motivating
        default: .calm
        }
    }
}

enum CoachingToneStore {
    static let defaultsKey = "runsmart.coachingTone"

    static func save(_ tone: CoachingTone, defaults: UserDefaults = .standard) {
        defaults.set(tone.rawValue, forKey: defaultsKey)
    }

    static func load(defaults: UserDefaults = .standard) -> CoachingTone {
        guard let raw = defaults.string(forKey: defaultsKey),
              let tone = CoachingTone(rawValue: raw) else { return .motivating }
        return tone
    }
}

struct CoachingToneSave: Equatable {
    var profile: OnboardingProfile
    var voiceTone: CoachingTone

    static func make(from raw: String, profile: OnboardingProfile) -> CoachingToneSave {
        var updated = profile
        updated.coachingTone = CoachingTone.displayLabel(for: raw)
        return CoachingToneSave(
            profile: updated,
            voiceTone: CoachingTone.voiceTone(for: updated.coachingTone)
        )
    }
}

enum CoachCueEvent: Equatable {
    case started
    case restored
    case paused
    case autoPaused
    case resumed
    case finished(detail: String)
}

struct PreparedCueSpeech: Equatable {
    var text: String
    var rate: Float
    var pitchMultiplier: Float
}

enum CoachCueSpeech {
    static let spokenLanguageNote = "Spoken cues are in English. Distance, pace and time stay the same in every tone."

    static func splitLine(facts: String, tone: CoachingTone) -> String {
        switch tone {
        case .motivating: "Push on. \(facts)"
        case .calm: "Settle in. \(facts)"
        case .technical: "Split check. \(facts)"
        }
    }

    /// Motivating lifecycle sentences stay the ones the app already speaks.
    static func line(for event: CoachCueEvent, tone: CoachingTone) -> String {
        switch event {
        case .started:
            switch tone {
            case .motivating: "Run started."
            case .calm: "Run started. Ease in."
            case .technical: "Run started. Clock is running."
            }
        case .restored:
            switch tone {
            case .motivating: "Run restored. Paused."
            case .calm: "Run restored. Still paused."
            case .technical: "Run restored. Paused. Totals kept."
            }
        case .paused:
            switch tone {
            case .motivating: "Run paused."
            case .calm: "Run paused. Take the rest."
            case .technical: "Run paused. Moving time stopped."
            }
        case .autoPaused:
            switch tone {
            case .motivating: "Auto-paused."
            case .calm: "Auto-paused. Standing still."
            case .technical: "Auto-paused. Speed is under the stop line."
            }
        case .resumed:
            switch tone {
            case .motivating: "Run resumed."
            case .calm: "Run resumed. Settle back in."
            case .technical: "Run resumed. Moving time is counting."
            }
        case .finished(let detail):
            switch tone {
            case .motivating: "Run finished. \(detail)"
            case .calm: "Run finished. Easy work. \(detail)"
            case .technical: "Run finished. Recorded totals. \(detail)"
            }
        }
    }

    static func prepared(text: String, tone: CoachingTone) -> PreparedCueSpeech {
        PreparedCueSpeech(text: text, rate: tone.speechRate, pitchMultiplier: tone.pitchMultiplier)
    }
}
