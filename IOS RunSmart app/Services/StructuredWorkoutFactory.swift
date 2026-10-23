import SwiftUI

struct WorkoutStep: Identifiable {
    let id = UUID()
    var title: String
    var duration: String
    var target: String
    var note: String
    var tint: Color
    /// The live-run guide stages this row stands for, built at the same place as the row so the
    /// pre-run list and the guide cannot disagree. Empty when the row has no target the data
    /// really contains; one empty row means the whole workout has no live guide.
    var guideSteps: [GuideStep] = []
}

enum StructuredWorkoutFactory {

    // MARK: - Public API

    static func makeSteps(for workout: WorkoutSummary) -> [WorkoutStep]? {
        if let json = workout.workoutStructure,
           let steps = parseJSON(json) {
            return steps
        }
        return derivedSteps(for: workout)
    }

    /// Live-run guide stages for a planned workout, or nil when any part of it lacks a target the
    /// workout data contains (the run then behaves like a free run).
    static func makeGuideSteps(for workout: WorkoutSummary) -> [GuideStep]? {
        guard let steps = makeSteps(for: workout), !steps.isEmpty,
              steps.allSatisfy({ !$0.guideSteps.isEmpty }) else { return nil }
        return steps.flatMap(\.guideSteps)
    }

    static func makeGuide(for workout: WorkoutSummary) -> WorkoutGuide? {
        makeGuideSteps(for: workout).flatMap { WorkoutGuide(steps: $0) }
    }

    static func derivedPaceLabel(workout: WorkoutSummary) -> String? {
        if let pace = workout.targetPaceSecondsPerKm, pace > 0 {
            return paceLabel(secondsPerKm: pace)
        }
        if let mins = workout.durationMinutes, mins > 0,
           let km = distanceKm(from: workout.distance), km > 0 {
            let sPerKm = Int(Double(mins * 60) / km)
            return paceLabel(secondsPerKm: sPerKm)
        }
        return nil
    }

    static func paceLabel(secondsPerKm: Int) -> String {
        let m = secondsPerKm / 60
        let s = secondsPerKm % 60
        return String(format: "%d:%02d /km", m, s)
    }

    // MARK: - JSON parsing

    private struct JSONWorkoutStructure: Decodable {
        struct Step: Decodable {
            var type: String
            var duration_seconds: Int?
            var description: String?
            var pace_seconds_per_km: Int?
            var note: String?
            var reps_count: Int?
            var rep_distance: String?
        }
        var steps: [Step]
    }

    private static func parseJSON(_ json: String) -> [WorkoutStep]? {
        guard let data = json.data(using: .utf8),
              let structure = try? JSONDecoder().decode(JSONWorkoutStructure.self, from: data),
              !structure.steps.isEmpty else { return nil }

        return structure.steps.map { s in
            let duration: String
            if let reps = s.reps_count, let dist = s.rep_distance {
                duration = "\(reps) × \(dist)"
            } else if let secs = s.duration_seconds {
                duration = formatSeconds(secs)
            } else {
                duration = "--"
            }
            let target: String
            if let pace = s.pace_seconds_per_km, pace > 0 {
                target = paceLabel(secondsPerKm: pace)
            } else {
                target = s.description ?? "Comfortable effort"
            }
            return WorkoutStep(
                title: stepTitle(for: s.type),
                duration: duration,
                target: target,
                note: s.note ?? "",
                tint: tintForType(s.type),
                guideSteps: jsonGuideSteps(for: s)
            )
        }
    }

    private static func jsonGuideSteps(for s: JSONWorkoutStructure.Step) -> [GuideStep] {
        let pace = s.pace_seconds_per_km.flatMap { $0 > 0 ? GuidePaceBand(center: Double($0)) : nil }
        if let reps = s.reps_count {
            guard let dist = s.rep_distance, let meters = parseDistanceMeters(dist) else { return [] }
            return repeatGuideSteps(
                reps: reps,
                repMeters: meters,
                recovery: parseRecovery(from: [s.note, s.description].compactMap { $0 }.joined(separator: ". ")),
                pace: pace
            )
        }
        guard let secs = s.duration_seconds, secs > 0 else { return [] }
        let kind = guideKind(for: s.type)
        return [GuideStep(
            kind: kind,
            target: .duration(seconds: Double(secs)),
            paceBand: (kind == .work || kind == .steady) ? pace : nil
        )]
    }

    private static func guideKind(for type: String) -> GuideStep.Kind {
        switch type.lowercased() {
        case "warmup", "warm_up", "warm-up": return .warmup
        case "cooldown", "cool_down", "cool-down": return .cooldown
        case "rest", "recovery", "recovery_jog": return .recovery
        case "tempo", "hill", "hills", "repeat", "repeats": return .work
        default: return .steady
        }
    }

    // MARK: - Derived steps

    private static func derivedSteps(for workout: WorkoutSummary) -> [WorkoutStep]? {
        let note = workout.detail.isEmpty ? "" : workout.detail
        switch workout.kind {
        case .easy:      return easySteps(workout: workout, note: note)
        case .tempo:     return tempoSteps(workout: workout, note: note)
        case .intervals: return intervalSteps(workout: workout, note: note)
        case .hills:     return hillSteps(note: note)
        case .long:      return longRunSteps(workout: workout, note: note)
        case .race:      return raceSteps(note: note)
        case .recovery:  return recoverySteps(note: note)
        case .parkrun:   return easySteps(workout: workout, note: note)
        case .strength:  return nil
        }
    }

    private static func easySteps(workout: WorkoutSummary, note: String) -> [WorkoutStep] {
        let pace = derivedPaceLabel(workout: workout) ?? "6:10 /km"
        let dur = durationLabel(workout: workout, warmup: 5, cooldown: 5)
        return [
            WorkoutStep(title: "Warm Up", duration: "5:00", target: "Easy walk/jog", note: "Let the body wake up", tint: .orange, guideSteps: [timedGuideStep(.warmup, seconds: 300)]),
            WorkoutStep(title: "Easy Run", duration: dur, target: pace, note: note.isEmpty ? "Conversational pace" : note, tint: .blue, guideSteps: mainBlockGuideSteps(workout: workout, warmup: 5, cooldown: 5, kind: .steady)),
            WorkoutStep(title: "Cool Down", duration: "5:00", target: "Walk", note: "Lower heart rate gradually", tint: .green, guideSteps: [timedGuideStep(.cooldown, seconds: 300)])
        ]
    }

    private static func tempoSteps(workout: WorkoutSummary, note: String) -> [WorkoutStep] {
        let pace = derivedPaceLabel(workout: workout) ?? "5:15 /km"
        let dur = durationLabel(workout: workout, warmup: 12, cooldown: 8)
        return [
            WorkoutStep(title: "Warm Up", duration: "12:00", target: "Easy jog", note: "Shake loose, add a few strides", tint: .orange, guideSteps: [timedGuideStep(.warmup, seconds: 720)]),
            WorkoutStep(title: "Tempo Block", duration: dur, target: pace, note: note.isEmpty ? "Controlled threshold effort" : note, tint: .red, guideSteps: mainBlockGuideSteps(workout: workout, warmup: 12, cooldown: 8, kind: .work)),
            WorkoutStep(title: "Cool Down", duration: "8:00", target: "Easy jog", note: "Relax and breathe", tint: .green, guideSteps: [timedGuideStep(.cooldown, seconds: 480)])
        ]
    }

    private static func intervalSteps(workout: WorkoutSummary, note: String) -> [WorkoutStep] {
        // Prefer the plan's own pace; only fall back to a hardcoded default,
        // and when we do, label it estimated so the sheet doesn't assert a
        // precise target the card never showed.
        let derivedPace = derivedPaceLabel(workout: workout)
        let target = derivedPace ?? "4:45 /km (est.)"

        // Parse the rep count from the structured interval notation (e.g.
        // "8 x 400m" → 8 reps × 400 m). Never digit-strip a total distance —
        // that turned "8 x 400m" into "8400" → 21000 reps.
        let repsLabel: String
        if let parsed = parseIntervalReps(from: workout.distance) {
            repsLabel = "\(parsed.reps) × \(parsed.repDistance)"
        } else if !workout.distance.trimmingCharacters(in: .whitespaces).isEmpty {
            // Not rep-notation — show the plan's own distance rather than
            // fabricating a rep count.
            repsLabel = workout.distance
        } else {
            repsLabel = "6 × 400 m"
        }

        // The guide needs the rep count and rep distance from the plan's own notation, and a
        // recovery written in the plan's own text. Without both there is no guide.
        var repeatGuide: [GuideStep] = []
        if let parsed = parseIntervalReps(from: workout.distance),
           let meters = parseDistanceMeters(parsed.repDistance) {
            repeatGuide = repeatGuideSteps(
                reps: parsed.reps,
                repMeters: meters,
                recovery: parseRecovery(from: workout.detail),
                pace: explicitPaceBand(for: workout)
            )
        }

        return [
            WorkoutStep(title: "Warm Up", duration: "10:00", target: "Easy jog", note: "Add mobility before speed", tint: .orange, guideSteps: [timedGuideStep(.warmup, seconds: 600)]),
            WorkoutStep(title: "Repeats", duration: repsLabel, target: target, note: note.isEmpty ? "Recover between reps" : note, tint: .red, guideSteps: repeatGuide),
            WorkoutStep(title: "Cool Down", duration: "10:00", target: "Easy jog", note: "Let heart rate settle", tint: .green, guideSteps: [timedGuideStep(.cooldown, seconds: 600)])
        ]
    }

    /// Parses interval rep notation such as "8 x 400m", "8 × 400 m", or
    /// "10x200m" into a rep count and a normalized rep-distance label.
    /// Returns nil when the string is a plain total distance (e.g. "6.4 km")
    /// rather than rep notation, so callers never synthesize a rep count by
    /// digit-stripping a total distance.
    private static let repNotationRegex = try? NSRegularExpression(
        pattern: #"^\s*(\d+)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(km|m|meters|metres)?"#,
        options: [.caseInsensitive]
    )

    static func parseIntervalReps(from distanceString: String) -> (reps: Int, repDistance: String)? {
        guard let regex = repNotationRegex else { return nil }
        let range = NSRange(distanceString.startIndex..., in: distanceString)
        guard let match = regex.firstMatch(in: distanceString, options: [], range: range),
              let repsRange = Range(match.range(at: 1), in: distanceString),
              let distRange = Range(match.range(at: 2), in: distanceString),
              let reps = Int(distanceString[repsRange]), reps > 0 else { return nil }

        let distValue = String(distanceString[distRange])
        var unit = "m"
        if match.range(at: 3).location != NSNotFound,
           let unitRange = Range(match.range(at: 3), in: distanceString) {
            let raw = distanceString[unitRange].lowercased()
            unit = (raw == "km") ? "km" : "m"
        }
        return (reps, "\(distValue) \(unit)")
    }

    private static func hillSteps(note: String) -> [WorkoutStep] {
        [
            WorkoutStep(title: "Warm Up", duration: "12:00", target: "Easy jog", note: "Find your hill", tint: .orange),
            WorkoutStep(title: "Hill Repeats", duration: "8 × 45 sec", target: "Strong effort", note: note.isEmpty ? "Walk/jog down recovery" : note, tint: .purple),
            WorkoutStep(title: "Cool Down", duration: "8:00", target: "Easy jog", note: "Flat and relaxed", tint: .green)
        ]
    }

    private static func longRunSteps(workout: WorkoutSummary, note: String) -> [WorkoutStep] {
        let pace = derivedPaceLabel(workout: workout) ?? "6:30 /km"
        let dur = durationLabel(workout: workout, warmup: 10, cooldown: 5)
        return [
            WorkoutStep(title: "Settle In", duration: "10:00", target: "Easy jog", note: "Start softer than you think", tint: .orange, guideSteps: [timedGuideStep(.warmup, seconds: 600)]),
            WorkoutStep(title: "Endurance Run", duration: dur, target: pace, note: note.isEmpty ? "Fuel if over 75 min" : note, tint: .blue, guideSteps: mainBlockGuideSteps(workout: workout, warmup: 10, cooldown: 5, kind: .steady)),
            WorkoutStep(title: "Finish Smooth", duration: "5:00", target: "Easy", note: "No sprint finish", tint: .green, guideSteps: [timedGuideStep(.cooldown, seconds: 300)])
        ]
    }

    private static func recoverySteps(note: String) -> [WorkoutStep] {
        [
            WorkoutStep(title: "Easy Walk", duration: "5:00", target: "Very easy", note: "Just move", tint: .green),
            WorkoutStep(title: "Recovery Jog", duration: "15:00", target: "Very easy", note: note.isEmpty ? "Breathe easy, no effort" : note, tint: .blue),
            WorkoutStep(title: "Stretch", duration: "5:00", target: "Static holds", note: "Hips, calves, glutes", tint: .green)
        ]
    }

    private static func raceSteps(note: String) -> [WorkoutStep] {
        [
            WorkoutStep(title: "Warm Up", duration: "15:00", target: "Easy jog + strides", note: "Arrive fresh, not tired", tint: .orange),
            WorkoutStep(title: "Race", duration: "Goal effort", target: "Race pace", note: note.isEmpty ? "Patient start, steady middle" : note, tint: .red),
            WorkoutStep(title: "Cool Down", duration: "10:00", target: "Easy walk/jog", note: "Recovery starts now", tint: .green)
        ]
    }

    // MARK: - Guide helpers

    private static func timedGuideStep(_ kind: GuideStep.Kind, seconds: Double, pace: GuidePaceBand? = nil) -> GuideStep {
        GuideStep(kind: kind, target: .duration(seconds: seconds), paceBand: pace)
    }

    /// Pace band only from the plan's explicit target pace. The pace label on the pre-run list can
    /// be an average over the whole workout, which is not a target for one block.
    private static func explicitPaceBand(for workout: WorkoutSummary) -> GuidePaceBand? {
        guard let pace = workout.targetPaceSecondsPerKm, pace > 0 else { return nil }
        return GuidePaceBand(center: Double(pace))
    }

    /// The main block of a derived workout, measured the way the pre-run row shows it: the plan's
    /// duration minus warm-up and cool-down when that fits, otherwise the plan's own distance.
    private static func mainBlockGuideSteps(workout: WorkoutSummary, warmup: Int, cooldown: Int, kind: GuideStep.Kind) -> [GuideStep] {
        let pace = explicitPaceBand(for: workout)
        if let mins = workout.durationMinutes, mins > warmup + cooldown {
            return [timedGuideStep(kind, seconds: Double((mins - warmup - cooldown) * 60), pace: pace)]
        }
        guard let target = parseTarget(workout.distance) else { return [] }
        return [GuideStep(kind: kind, target: target, paceBand: pace)]
    }

    /// Reps with a recovery between each pair. Returns [] (no guide) when the recovery is not known:
    /// running reps back to back is not what any plan means.
    private static func repeatGuideSteps(reps: Int, repMeters: Double, recovery: GuideStep.Target?, pace: GuidePaceBand?) -> [GuideStep] {
        guard reps > 0, reps <= 50, repMeters > 0 else { return [] }
        if reps > 1, recovery == nil { return [] }
        var steps: [GuideStep] = []
        for rep in 1...reps {
            steps.append(GuideStep(kind: .work, target: .distance(meters: repMeters), paceBand: pace, repIndex: rep, repTotal: reps))
            if rep < reps, let recovery {
                steps.append(GuideStep(kind: .recovery, target: recovery))
            }
        }
        return steps
    }

    private static let quantityRegex = try? NSRegularExpression(
        pattern: #"^\s*(\d+(?:\.\d+)?)\s*(km|kilometers?|kilometres?|meters?|metres?|miles?|mi|minutes?|mins?|min|seconds?|secs?|sec|s|m)\s*$"#,
        options: [.caseInsensitive]
    )

    /// "400 m", "1.5 km", "45 min" or "90 sec" as a guide target. Anything else, including rep
    /// notation like "8 x 400m" or a bare number, is not a target.
    static func parseTarget(_ text: String) -> GuideStep.Target? {
        guard let regex = quantityRegex else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]), value > 0 else { return nil }
        let unit = text[unitRange].lowercased()
        switch unit {
        case "km", "kilometer", "kilometers", "kilometre", "kilometres": return .distance(meters: value * 1_000)
        case "m", "meter", "meters", "metre", "metres": return .distance(meters: value)
        case "mi", "mile", "miles": return .distance(meters: value * 1_609.344)
        case "min", "mins", "minute", "minutes": return .duration(seconds: value * 60)
        default: return .duration(seconds: value)
        }
    }

    static func parseDistanceMeters(_ text: String) -> Double? {
        if case .distance(let meters)? = parseTarget(text) { return meters }
        return nil
    }

    private static let recoveryKeywordRegex = try? NSRegularExpression(
        pattern: #"\b(recovery|recover|rest)\b|\b(jog|walk)\b[^,;.()]*\bbetween\b"#,
        options: [.caseInsensitive]
    )
    /// A clause about the warm-up or cool-down is never the recovery between reps.
    private static let warmupCooldownRegex = try? NSRegularExpression(
        pattern: #"warm[\s-]?up|cool[\s-]?down"#,
        options: [.caseInsensitive]
    )
    private static let quantityInTextRegex = try? NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(km|meters?|metres?|minutes?|mins?|seconds?|secs?|sec|s|m)\b"#,
        options: [.caseInsensitive]
    )

    /// Recovery written in the plan text, such as "6 x 400m with 90 s recovery" or "Jog 200 m
    /// between reps". Looks only at clauses that name a recovery, so the rep distance is never
    /// mistaken for it. Returns nil when the text gives no usable length.
    static func parseRecovery(from text: String) -> GuideStep.Target? {
        guard let keyword = recoveryKeywordRegex, let quantity = quantityInTextRegex,
              let excluded = warmupCooldownRegex else { return nil }
        let clauses = text.components(separatedBy: CharacterSet(charactersIn: ",;.()")).flatMap {
            $0.components(separatedBy: " with ")
        }
        for clause in clauses {
            let whole = NSRange(clause.startIndex..., in: clause)
            guard excluded.firstMatch(in: clause, options: [], range: whole) == nil,
                  keyword.firstMatch(in: clause, options: [], range: whole) != nil else { continue }
            for match in quantity.matches(in: clause, options: [], range: whole) {
                guard let range = Range(match.range, in: clause),
                      let target = parseTarget(String(clause[range])) else { continue }
                switch target {
                case .duration(let seconds) where (10...600).contains(seconds): return target
                case .distance(let meters) where (20...2_000).contains(meters): return target
                default: continue
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func durationLabel(workout: WorkoutSummary, warmup: Int, cooldown: Int) -> String {
        if let mins = workout.durationMinutes, mins > warmup + cooldown {
            let main = mins - warmup - cooldown
            return "\(main):00"
        }
        return workout.distance
    }

    private static func distanceKm(from distanceString: String) -> Double? {
        let nums = distanceString.components(separatedBy: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted).joined()
        return Double(nums)
    }

    private static func formatSeconds(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 { return "\(m):00" }
        return String(format: "%d:%02d", m, s)
    }

    private static func stepTitle(for type: String) -> String {
        switch type.lowercased() {
        case "warmup", "warm_up", "warm-up": return "Warm Up"
        case "cooldown", "cool_down", "cool-down": return "Cool Down"
        case "rest", "recovery_jog": return "Recovery"
        case "repeat", "repeats": return "Repeats"
        case "run", "main": return "Run"
        case "tempo": return "Tempo Block"
        case "hill", "hills": return "Hill Repeats"
        default: return type.capitalized
        }
    }

    private static func tintForType(_ type: String) -> Color {
        switch type.lowercased() {
        case "warmup", "warm_up", "warm-up": return .orange
        case "cooldown", "cool_down", "cool-down": return .green
        case "tempo", "race", "repeat", "repeats": return .red
        case "hill", "hills": return .purple
        default: return .blue
        }
    }
}
