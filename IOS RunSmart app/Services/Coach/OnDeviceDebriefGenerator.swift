import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Opt-in experiment: Apple's on-device model writes the post-run debrief.
/// Off by default. Offered only when the app runs in English and the model is ready,
/// because Apple Intelligence has no Hebrew. The cloud coach stays the next step.
enum OnDeviceDebrief {
    static let optInKey = "runsmart.onDeviceDebrief.optIn"

    /// Why the experiment can't run on this device right now.
    enum Unavailable: String, Equatable {
        case notBuilt = "not_built"
        case osTooOld = "os_too_old"
        case language
        case deviceNotEligible = "device_not_eligible"
        case appleIntelligenceOff = "apple_intelligence_off"
        case modelNotReady = "model_not_ready"
    }

    static var unavailableReason: Unavailable? {
        guard appLanguageIsEnglish else { return .language }
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .osTooOld }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale(identifier: "en")) ? nil : .language
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
            case .modelNotReady: return .modelNotReady
            @unknown default: return .modelNotReady
            }
        }
        #else
        return .notBuilt
        #endif
    }

    static var isReady: Bool { unavailableReason == nil }

    static var appLanguageIsEnglish: Bool {
        (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("en")
    }

    static func isOptedIn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: optInKey)
    }

    /// The on-device generator when the runner opted in, has no linked coach
    /// (a coach's context only reaches the cloud prompt) and the model is ready.
    static func generatorIfEnabled(coachLinked: Bool, defaults: UserDefaults = .standard) -> (any RunDebriefGenerating)? {
        guard isOptedIn(defaults), !coachLinked, isReady else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return OnDeviceDebriefGenerator() }
        #endif
        return nil
    }
}

/// The prompt for the on-device model: a port of `RUN_DEBRIEF_SYSTEM_PROMPT`
/// (supabase/functions/coach_message/coach_prompts.ts). Short, so it fits any context size.
enum OnDeviceDebriefPrompt {
    static let instructions = """
    You are RunSmart Coach. Write a short post-run debrief from the run facts you are given.
    Rules:
    - Use only the facts given. Mention at least one real number from them.
    - Be warm and direct. No filler.
    - Do not diagnose injuries or give medical advice.
    - Do not promise health, fitness or race results.
    - Do not shame any result.
    - Under uncertainty, give conservative guidance.
    """

    static func runSummary(for input: RunDebriefInput) -> String {
        var lines = [
            String(format: "Distance: %.2f km", input.distanceKm),
            "Moving time: \(input.durationSeconds / 60) min \(input.durationSeconds % 60) s",
        ]
        if let pace = input.averagePaceMinPerKm, pace.isFinite, pace > 0 {
            let totalSeconds = Int((pace * 60).rounded())
            lines.append("Average pace: \(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60)) per km")
        }
        if let heartRate = input.averageHeartRateBPM {
            lines.append("Average heart rate: \(heartRate) bpm")
        }
        lines.append("Workout type: \(input.workoutType)")
        lines.append("Runs in the last 7 days: \(input.recentRunsLast7Days)")
        return lines.joined(separator: "\n")
    }

    /// Cuts text to `limit` characters, on a word boundary when one is close.
    static func clip(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cut = String(trimmed.prefix(limit))
        if trimmed[trimmed.index(trimmed.startIndex, offsetBy: limit)].isWhitespace { return cut }
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space])
        }
        return cut
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
nonisolated struct OnDeviceDebriefOutput {
    @Guide(description: "A short reaction to this run, at most 40 characters")
    var headline: String
    @Guide(description: "One or two sentences about the run that use at least one number from the facts, at most 300 characters")
    var debrief: String
    @Guide(description: "One sentence on what this run means for tomorrow, at most 160 characters")
    var tomorrow: String
}

@available(iOS 26.0, *)
struct OnDeviceDebriefGenerator: RunDebriefGenerating {
    let attemptName = "on_device"
    var timeoutNanoseconds: UInt64 = 12_000_000_000

    func generateDebrief(for input: RunDebriefInput) async throws -> PostRunDebriefModel? {
        guard OnDeviceDebrief.isReady else { return nil }
        let instructions = OnDeviceDebriefPrompt.instructions
        let prompt = OnDeviceDebriefPrompt.runSummary(for: input)
        let timeout = timeoutNanoseconds
        let output = try await withThrowingTaskGroup(of: OnDeviceDebriefOutput.self) { group in
            group.addTask {
                let session = LanguageModelSession(instructions: instructions)
                return try await session.respond(to: prompt, generating: OnDeviceDebriefOutput.self).content
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                throw RunDebriefTimeoutError()
            }
            do {
                guard let result = try await group.next() else { throw RunDebriefTimeoutError() }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
        return PostRunDebriefModel(
            headline: OnDeviceDebriefPrompt.clip(output.headline, to: 40),
            debrief: OnDeviceDebriefPrompt.clip(output.debrief, to: 300),
            tomorrow: OnDeviceDebriefPrompt.clip(output.tomorrow, to: 160),
            planImpact: nil,
            source: .onDevice
        )
    }
}
#endif
