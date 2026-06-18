import Foundation

enum RunnerIdentityKind: String, CaseIterable, Equatable {
    case enduranceBuilder = "endurance_builder"
    case speedSeeker = "speed_seeker"
    case comebackRunner = "comeback_runner"
    case firstTimer = "first_timer"
    case balancedAthlete = "balanced_athlete"
}

struct RunnerIdentityPresentation: Equatable {
    var kind: RunnerIdentityKind
    var label: String
    var symbolName: String
    var accent: RunnerIdentityAccent
    var headline: String
    var subline: String
    var ctaLabel: String
}

enum RunnerIdentityAccent: Equatable {
    case endurance
    case speed
    case comeback
    case firstTimer
    case balanced
}

struct GoalTimelineProjection: Equatable {
    var weeks: Int
    var milestoneWeek: Int
    var milestoneLabel: String
    var goalLabel: String
    var projectedDate: Date
    var normalizedGoal: GoalTimelineCategory
}

enum GoalTimelineCategory: String, Equatable {
    case habit
    case distance
    case speed
}

enum UserInsightService {

    private static let defaultPaceMinPerKm = 7.0

    static func getRunningIdentity(
        goal: String,
        experience: String,
        paceMinPerKm: Double? = nil
    ) -> RunnerIdentityPresentation {
        let pace = paceMinPerKm ?? defaultPaceMinPerKm
        let goalLower = goal.lowercased()
        let experienceLower = experience.lowercased()

        let kind: RunnerIdentityKind
        if experienceLower.contains("returning") || experienceLower.contains("break") || experienceLower.contains("comeback") {
            kind = .comebackRunner
        } else if experienceLower.contains("getting started") || experienceLower.contains("never run") || experienceLower.contains("new to") {
            kind = .firstTimer
        } else if goalLower.contains("pr") || goalLower.contains("speed") || pace < 5.5 {
            kind = .speedSeeker
        } else if isDistanceGoal(goalLower), pace > 6.5 {
            kind = .enduranceBuilder
        } else {
            kind = .balancedAthlete
        }

        return presentation(for: kind)
    }

    static func projectGoalTimeline(goal: String, experience: String) -> GoalTimelineProjection {
        let category = normalizedGoalCategory(for: goal)
        let fitness = normalizedFitnessLevel(for: experience)
        var weeks = lookupWeeks(goal: category, fitness: fitness, rawGoal: goal)

        if category == .distance, let specific = specificDistanceWeeks(rawGoal: goal, fitness: fitness) {
            weeks = specific
        }

        weeks = min(24, max(4, weeks))
        let milestoneWeek = max(1, weeks / 2)

        var projected = Calendar.current.startOfDay(for: Date())
        projected = Calendar.current.date(byAdding: .day, value: weeks * 7, to: projected) ?? projected

        return GoalTimelineProjection(
            weeks: weeks,
            milestoneWeek: milestoneWeek,
            milestoneLabel: milestoneLabel(for: category),
            goalLabel: goalLabel(for: category, rawGoal: goal),
            projectedDate: projected,
            normalizedGoal: category
        )
    }

    // MARK: - Identity copy (variant C)

    private static func presentation(for kind: RunnerIdentityKind) -> RunnerIdentityPresentation {
        switch kind {
        case .enduranceBuilder:
            return RunnerIdentityPresentation(
                kind: kind,
                label: "Endurance Builder",
                symbolName: "mountain.2.fill",
                accent: .endurance,
                headline: "We can already tell — you're in it for the miles, not the medals.",
                subline: "That's the kind of runner who surprises themselves. Let's find out how far.",
                ctaLabel: "I'm ready"
            )
        case .speedSeeker:
            return RunnerIdentityPresentation(
                kind: kind,
                label: "Speed Seeker",
                symbolName: "bolt.fill",
                accent: .speed,
                headline: "You're chasing time, not just distance.",
                subline: "Every second you shave off is earned. We'll help you earn more of them.",
                ctaLabel: "Let's go faster"
            )
        case .comebackRunner:
            return RunnerIdentityPresentation(
                kind: kind,
                label: "Comeback Runner",
                symbolName: "arrow.triangle.2.circlepath",
                accent: .comeback,
                headline: "You're back — and that matters.",
                subline: "The hardest run is often the one after time away. You showed up anyway.",
                ctaLabel: "I'm ready"
            )
        case .firstTimer:
            return RunnerIdentityPresentation(
                kind: kind,
                label: "First Timer",
                symbolName: "leaf.fill",
                accent: .firstTimer,
                headline: "Everyone starts somewhere. Yours starts now.",
                subline: "The runners who stick with it are the ones who start slowly. We've got you.",
                ctaLabel: "Start my journey"
            )
        case .balancedAthlete:
            return RunnerIdentityPresentation(
                kind: kind,
                label: "All-Round Runner",
                symbolName: "figure.run",
                accent: .balanced,
                headline: "You've got a good base. Let's do something with it.",
                subline: "Consistent runners who mix pace and distance improve fastest. That's your path.",
                ctaLabel: "Build on it"
            )
        }
    }

    // MARK: - Timeline lookup

    private static let weeksToGoal: [GoalTimelineCategory: [String: Int]] = [
        .habit: ["beginner": 4, "occasional": 4, "regular": 3],
        .distance: ["beginner": 8, "occasional": 6, "regular": 5],
        .speed: ["beginner": 6, "occasional": 5, "regular": 4]
    ]

    private static func lookupWeeks(goal: GoalTimelineCategory, fitness: String, rawGoal: String) -> Int {
        weeksToGoal[goal]?[fitness] ?? 6
    }

    private static func specificDistanceWeeks(rawGoal: String, fitness: String) -> Int? {
        let lower = rawGoal.lowercased()
        if lower.contains("marathon") { return 24 }
        if lower.contains("half") { return fitness == "beginner" ? 20 : 14 }
        if lower.contains("10k") {
            switch fitness {
            case "beginner": return 14
            case "occasional": return 10
            default: return 8
            }
        }
        if lower.contains("5k") {
            switch fitness {
            case "beginner": return 8
            case "occasional": return 5
            default: return 3
            }
        }
        return nil
    }

    private static func normalizedGoalCategory(for goal: String) -> GoalTimelineCategory {
        let lower = goal.lowercased()
        if lower.contains("just run") || lower.contains("habit") || lower.contains("consistency") {
            return .habit
        }
        if lower.contains("pr") || lower.contains("speed") || lower.contains("faster") {
            return .speed
        }
        if lower.contains("5k") || lower.contains("10k") || lower.contains("half") || lower.contains("marathon") || lower.contains("race") {
            return .distance
        }
        return .habit
    }

    private static func normalizedFitnessLevel(for experience: String) -> String {
        let lower = experience.lowercased()
        if lower.contains("getting started") || lower.contains("building base") || lower.contains("beginner") || lower.contains("new") {
            return "beginner"
        }
        if lower.contains("race") || lower.contains("advanced") || lower.contains("competitive") {
            return "regular"
        }
        return "occasional"
    }

    private static func isDistanceGoal(_ goalLower: String) -> Bool {
        goalLower.contains("5k") || goalLower.contains("10k") || goalLower.contains("half")
            || goalLower.contains("marathon") || goalLower.contains("race") || goalLower.contains("distance")
    }

    private static func milestoneLabel(for category: GoalTimelineCategory) -> String {
        switch category {
        case .habit: return "First consistent week"
        case .distance: return "Halfway there"
        case .speed: return "Feeling the difference"
        }
    }

    private static func goalLabel(for category: GoalTimelineCategory, rawGoal: String) -> String {
        switch category {
        case .habit: return "Running 3× / week"
        case .distance:
            let lower = rawGoal.lowercased()
            if lower.contains("marathon") { return "Marathon ready" }
            if lower.contains("half") { return "Half ready" }
            if lower.contains("10k") { return "10K ready" }
            if lower.contains("5k") { return "5K ready" }
            return "New distance goal"
        case .speed: return "Faster than today"
        }
    }
}
