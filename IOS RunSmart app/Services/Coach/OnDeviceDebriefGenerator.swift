import Foundation
import PostHog
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why a post-run debrief is being made. Only `liveRun` (the summary right after a
/// run recorded on the Run tab) may use the on-device model; imports, syncs and
/// recovered runs use the cloud coach only.
enum RunDebriefTrigger: String {
    case liveRun = "live_run"
    case recovered
    case importRun = "import"
    case syncNewest = "sync_newest"
    case background
}

enum RunDebriefGeneratorKind: Equatable {
    case onDevice
    case cloud
}

/// Opt-in experiment: Apple's on-device model writes the post-run debrief.
/// Off by default. Offered only when the remote flag is on, the app runs in English
/// and the model is ready (Apple Intelligence has no Hebrew). The cloud coach stays the next step.
enum OnDeviceDebrief {
    static let optInKey = "runsmart.onDeviceDebrief.optIn"
    /// PostHog feature flag. Missing or off = the toggle is hidden and nothing runs on device.
    static let remoteFlagKey = "runsmart-on-device-debrief"

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

    /// Remote kill switch. Debug builds are always on so the experiment can be tested.
    static var remoteEnabled: Bool {
        #if DEBUG
        return true
        #else
        return PostHogSDK.shared.isFeatureEnabled(remoteFlagKey)
        #endif
    }

    /// Whether Settings shows the toggle.
    static var isOffered: Bool { remoteEnabled && isReady }

    static var appLanguageIsEnglish: Bool {
        (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("en")
    }

    static func isOptedIn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: optInKey)
    }

    /// Which generators to ask, in order. On-device only when every condition holds:
    /// opted in, remote flag on, model ready, no linked coach (coach context only reaches
    /// the cloud prompt) and a live run. Cloud only with a signed-in session.
    static func generatorPlan(
        optedIn: Bool,
        ready: Bool,
        remoteEnabled: Bool,
        coachLinked: Bool,
        hasSession: Bool,
        trigger: RunDebriefTrigger
    ) -> [RunDebriefGeneratorKind] {
        var plan: [RunDebriefGeneratorKind] = []
        if optedIn, ready, remoteEnabled, !coachLinked, trigger == .liveRun {
            plan.append(.onDevice)
        }
        if hasSession {
            plan.append(.cloud)
        }
        return plan
    }

    static func makeGenerator() -> (any RunDebriefGenerating)? {
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
    /// 8 s, not the cloud's 12 s: the worst case before the fixed fallback stays near 20 s
    /// (8 s on device, then 12 s cloud). The first call also loads the model, so 6 s would
    /// time out more often and skew the experiment.
    var timeoutNanoseconds: UInt64 = 8_000_000_000

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
