import Foundation

/// The run facts every debrief generator gets. Built once per run, so the cloud
/// coach and any later generator (for example on-device) see the same input.
struct RunDebriefInput: Hashable {
    let distanceKm: Double
    let durationSeconds: Int
    let averagePaceMinPerKm: Double?
    let averageHeartRateBPM: Int?
    let workoutType: String
    let recentRunsLast7Days: Int
}

/// One way to write a post-run debrief.
/// Return nil to be skipped (no session, model not ready). Throw on failure.
protocol RunDebriefGenerating {
    func generateDebrief(for input: RunDebriefInput) async throws -> PostRunDebriefModel?
}

enum RunDebriefPipeline {
    /// Tries each generator in order and returns the first complete debrief.
    /// A skipped, failed or incomplete result moves on to the next generator.
    /// When none works, the fixed fallback text is returned.
    /// `persist` runs only for a generated debrief, never for the fallback.
    static func debrief(
        for input: RunDebriefInput,
        run: RecordedRun,
        generators: [any RunDebriefGenerating],
        persist: (PostRunDebriefModel) async -> Void = { _ in }
    ) async -> PostRunDebriefModel {
        for generator in generators {
            do {
                guard let candidate = try await generator.generateDebrief(for: input) else { continue }
                guard let complete = candidate.trimmedIfComplete else {
                    print("[RunDebrief] \(type(of: generator)) returned an incomplete debrief, trying next")
                    continue
                }
                await persist(complete)
                return complete
            } catch is CancellationError {
                return .fallback(for: run)
            } catch is RunDebriefTimeoutError {
                print("[RunDebrief] \(type(of: generator)) timed out, trying next")
            } catch {
                print("[RunDebrief] \(type(of: generator)) failed, trying next:", error)
            }
        }
        return .fallback(for: run)
    }
}

struct RunDebriefTimeoutError: Error {}

extension PostRunDebriefModel {
    /// The same debrief with whitespace trimmed, or nil when headline, debrief or tomorrow is empty.
    var trimmedIfComplete: PostRunDebriefModel? {
        let headline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let debrief = debrief.trimmingCharacters(in: .whitespacesAndNewlines)
        let tomorrow = tomorrow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headline.isEmpty, !debrief.isEmpty, !tomorrow.isEmpty else { return nil }
        return PostRunDebriefModel(
            headline: headline,
            debrief: debrief,
            tomorrow: tomorrow,
            planImpact: planImpact,
            source: source
        )
    }
}

/// Today's path: the `coach_message` edge function (`intent: run_debrief`), 12 s timeout.
struct CloudRunDebriefGenerator: RunDebriefGenerating {
    let authUserID: UUID
    let accessToken: String
    var timeoutNanoseconds: UInt64 = 12_000_000_000

    func generateDebrief(for input: RunDebriefInput) async throws -> PostRunDebriefModel? {
        let request = RunSmartDTO.RunDebriefRequestDTO(
            runDistanceKm: input.distanceKm,
            runDurationSeconds: input.durationSeconds,
            averagePaceMinPerKm: input.averagePaceMinPerKm,
            averageHeartRateBPM: input.averageHeartRateBPM,
            workoutType: input.workoutType,
            planPhase: nil,
            recentLoadDays: input.recentRunsLast7Days,
            limitations: []
        )
        // A failed encode throws, so the pipeline logs it as a failure, not a skip.
        let body = try CoachRequestJSON.encode(request, coach: CoachContextSource.shared.context(for: authUserID))
        let client = URLSessionRunSmartAPIClient(
            baseURL: SupabaseManager.functionsBaseURL,
            accessToken: accessToken,
            additionalHeaders: ["apikey": SupabaseManager.supabasePublishableKey]
        )
        let timeout = timeoutNanoseconds
        let response = try await withThrowingTaskGroup(of: RunSmartDTO.RunDebriefResponseDTO.self) { group in
            group.addTask {
                try await client.send(
                    RunSmartAPI.Endpoint(path: "coach_message", method: .post, body: body),
                    as: RunSmartDTO.RunDebriefResponseDTO.self
                )
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
            headline: response.headline,
            debrief: response.debrief,
            tomorrow: response.tomorrow,
            planImpact: response.planImpact,
            source: .ai
        )
    }
}
