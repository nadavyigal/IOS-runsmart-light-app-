import Foundation

/// Debug builds only: writes the on-device and the cloud debrief for the same run
/// side by side, so the founder can rate about 10 real runs.
/// File: the app's Documents/debrief-compare.jsonl (Xcode > Devices > Download Container).
/// Nothing here is saved to Supabase or sent to analytics.
enum RunDebriefCompare {
    static let fileName = "debrief-compare.jsonl"

    struct Side: Equatable {
        let headline: String?
        let debrief: String?
        let tomorrow: String?
        let latencyMs: Int
        let outcome: String
    }

    /// One JSON line with both sides. Keys are sorted so lines diff cleanly.
    static func line(runID: UUID, date: Date, input: RunDebriefInput, onDevice: Side, cloud: Side) -> String? {
        func side(_ s: Side) -> [String: Any] {
            var out: [String: Any] = ["latency_ms": s.latencyMs, "outcome": s.outcome]
            if let headline = s.headline { out["headline"] = headline }
            if let debrief = s.debrief { out["debrief"] = debrief }
            if let tomorrow = s.tomorrow { out["tomorrow"] = tomorrow }
            return out
        }
        let object: [String: Any] = [
            "run_id": runID.uuidString,
            "date": ISO8601DateFormatter().string(from: date),
            "facts": OnDeviceDebriefPrompt.runSummary(for: input),
            "on_device": side(onDevice),
            "cloud": side(cloud),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    #if DEBUG
    /// Asks each generator on its own and appends one line. Call off the critical path.
    static func record(run: RecordedRun, input: RunDebriefInput, onDevice: any RunDebriefGenerating, cloud: any RunDebriefGenerating) async {
        async let onDeviceSide = side(from: onDevice, input: input)
        async let cloudSide = side(from: cloud, input: input)
        let (left, right) = await (onDeviceSide, cloudSide)
        guard let line = line(runID: run.id, date: Date(), input: input, onDevice: left, cloud: right) else { return }
        print("[RunDebriefCompare]", line)
        append(line)
    }

    private static func side(from generator: any RunDebriefGenerating, input: RunDebriefInput) async -> Side {
        let started = ContinuousClock.now
        do {
            let model = try await generator.generateDebrief(for: input)?.trimmedIfComplete
            return Side(headline: model?.headline, debrief: model?.debrief, tomorrow: model?.tomorrow,
                        latencyMs: RunDebriefPipeline.milliseconds(since: started),
                        outcome: model == nil ? "no_debrief" : "generated")
        } catch {
            return Side(headline: nil, debrief: nil, tomorrow: nil,
                        latencyMs: RunDebriefPipeline.milliseconds(since: started),
                        outcome: "error: \(type(of: error))")
        }
    }

    private static func append(_ line: String) {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = (line + "\n").data(using: .utf8) else { return }
        let url = folder.appendingPathComponent(fileName)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
    #endif
}
