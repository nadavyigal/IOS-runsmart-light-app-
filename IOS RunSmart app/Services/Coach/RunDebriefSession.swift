import Foundation

/// One post-run debrief, start to end: run the generators, send one
/// `run_debrief_generated` event, and hand live runs to the debug compare log.
/// Kept apart from SupabaseRunSmartServices so it can be tested with fake generators.
enum RunDebriefSession {
    static func produce(
        run: RecordedRun,
        trigger: RunDebriefTrigger,
        generators: [any RunDebriefGenerating],
        onDeviceOptedIn: Bool,
        onDeviceUnavailable: OnDeviceDebrief.Unavailable?,
        makeInput: () async -> RunDebriefInput,
        persist: (PostRunDebriefModel) async -> Void,
        compare: (RunDebriefInput) -> Void = { _ in }
    ) async -> PostRunDebriefModel {
        let started = ContinuousClock.now
        var attempts: [RunDebriefAttempt] = []
        var result = PostRunDebriefModel.fallback(for: run)
        var input: RunDebriefInput?
        if !generators.isEmpty {
            let built = await makeInput()
            input = built
            result = await RunDebriefPipeline.debrief(
                for: built,
                run: run,
                generators: generators,
                report: { attempts.append($0) },
                persist: persist
            )
        }

        // A cancelled debrief (the run screen closed) is not a result: no event, no compare.
        // A generator can also throw CancellationError without the task being cancelled,
        // so a `.cancelled` attempt counts too. Ordinary failures still send a fallback event.
        if Task.isCancelled || attempts.contains(where: { $0.outcome == .cancelled }) { return result }

        Analytics.trackRunDebriefGenerated(
            trigger: trigger,
            result: result.source,
            totalLatencyMs: RunDebriefPipeline.milliseconds(since: started),
            attempts: attempts,
            onDeviceOptedIn: onDeviceOptedIn,
            onDeviceUnavailable: onDeviceUnavailable
        )
        if let input, RunDebriefCompare.shouldRecord(trigger: trigger, generatorNames: generators.map(\.attemptName)) {
            compare(input)
        }
        return result
    }
}
