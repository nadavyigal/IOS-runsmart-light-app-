import SwiftUI

struct WorkoutStep: Identifiable {
    let id = UUID()
    var title: String
    var duration: String
    var target: String
    var note: String
    var tint: Color
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
                tint: tintForType(s.type)
            )
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
            WorkoutStep(title: "Warm Up", duration: "5:00", target: "Easy walk/jog", note: "Let the body wake up", tint: .orange),
            WorkoutStep(title: "Easy Run", duration: dur, target: pace, note: note.isEmpty ? "Conversational pace" : note, tint: .blue),
            WorkoutStep(title: "Cool Down", duration: "5:00", target: "Walk", note: "Lower heart rate gradually", tint: .green)
        ]
    }

    private static func tempoSteps(workout: WorkoutSummary, note: String) -> [WorkoutStep] {
        let pace = derivedPaceLabel(workout: workout) ?? "5:15 /km"
        let dur = durationLabel(workout: workout, warmup: 12, cooldown: 8)
        return [
            WorkoutStep(title: "Warm Up", duration: "12:00", target: "Easy jog", note: "Shake loose, add a few strides", tint: .orange),
            WorkoutStep(title: "Tempo Block", duration: dur, target: pace, note: note.isEmpty ? "Controlled threshold effort" : note, tint: .red),
            WorkoutStep(title: "Cool Down", duration: "8:00", target: "Easy jog", note: "Relax and breathe", tint: .green)
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

        return [
            WorkoutStep(title: "Warm Up", duration: "10:00", target: "Easy jog", note: "Add mobility before speed", tint: .orange),
            WorkoutStep(title: "Repeats", duration: repsLabel, target: target, note: note.isEmpty ? "Jog 200 m between reps" : note, tint: .red),
            WorkoutStep(title: "Cool Down", duration: "10:00", target: "Easy jog", note: "Let heart rate settle", tint: .green)
        ]
    }

    /// Parses interval rep notation such as "8 x 400m", "8 × 400 m", or
    /// "10x200m" into a rep count and a normalized rep-distance label.
    /// Returns nil when the string is a plain total distance (e.g. "6.4 km")
    /// rather than rep notation, so callers never synthesize a rep count by
    /// digit-stripping a total distance.
    static func parseIntervalReps(from distanceString: String) -> (reps: Int, repDistance: String)? {
        let pattern = #"^\s*(\d+)\s*[x×]\s*(\d+(?:\.\d+)?)\s*(km|m|meters|metres)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
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
            WorkoutStep(title: "Settle In", duration: "10:00", target: "Easy jog", note: "Start softer than you think", tint: .orange),
            WorkoutStep(title: "Endurance Run", duration: dur, target: pace, note: note.isEmpty ? "Fuel if over 75 min" : note, tint: .blue),
            WorkoutStep(title: "Finish Smooth", duration: "5:00", target: "Easy", note: "No sprint finish", tint: .green)
        ]
    }

    private static func recoverySteps(note: String) -> [WorkoutStep] {
        [
            WorkoutStep(title: "Easy Walk", duration: "5:00", target: "Zone 1", note: "Just move", tint: .green),
            WorkoutStep(title: "Recovery Jog", duration: "15:00", target: "Zone 1", note: note.isEmpty ? "Breathe easy, no effort" : note, tint: .blue),
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
