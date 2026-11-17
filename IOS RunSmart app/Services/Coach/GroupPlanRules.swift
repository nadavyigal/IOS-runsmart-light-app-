import Foundation

/// Raw values Build my plan sends: `webPlanGoal`, `targetDistanceSlug`,
/// `supabaseExperience`, and `weeklyRunDays` from the 2...7 stepper.
enum GroupPlanRules {
    static let goals = ["habit", "speed", "distance"]
    static let targetDistances = ["5k", "10k", "half-marathon", "marathon"]
    static let levels = ["beginner", "intermediate", "advanced"]
    static let runsPerWeek = 2...7
    static let maxPlanWeeks = 16

    /// Placeholders. The generator has no per-distance minimum; it only caps
    /// a plan at 16 weeks. Nadav/PM to confirm. Matched by the RPC.
    static let minWeeksBeforeRace = [
        "5k": 4,
        "10k": 6,
        "half-marathon": 8,
        "marathon": 12
    ]

    static let pilotNotice = "Plan Mode is set for the pilot."
    static let lockedCaption = "Set for the pilot"
    static let choiceFailedMessage = "Couldn't save your choice. Try again."
    static let savedMessage = "Saved. New athletes who join will get this plan."
    static let settingsFailedMessage = "Couldn't save these settings."
    static let joinerHint = "Athletes who join later get these settings. Athletes already in the group keep their plan."
    static let pastDateMessage = "That date is in the past."
    static let tooCloseMessage = "That race is too close for this distance."
    static let final16WeeksMessage = "The plan covers the final 16 weeks"

    enum DateNotice: Equatable {
        case past
        case tooClose
        case coversFinal16Weeks

        var blocksSave: Bool { self != .coversFinal16Weeks }

        var message: String {
            switch self {
            case .past: GroupPlanRules.pastDateMessage
            case .tooClose: GroupPlanRules.tooCloseMessage
            case .coversFinal16Weeks: GroupPlanRules.final16WeeksMessage
            }
        }
    }

    static func goalTitle(_ raw: String) -> String {
        switch raw {
        case "habit": "Habit"
        case "speed": "Speed"
        case "distance": "Distance"
        default: raw
        }
    }

    static func distanceTitle(_ raw: String) -> String {
        switch raw {
        case "5k": "5K"
        case "10k": "10K"
        case "half-marathon": "Half marathon"
        case "marathon": "Marathon"
        default: raw
        }
    }

    static func levelTitle(_ raw: String) -> String {
        switch raw {
        case "beginner": "Beginner"
        case "intermediate": "Intermediate"
        case "advanced": "Advanced"
        default: raw
        }
    }

    /// Whole days from the start of `today` to the start of `raceDate`.
    /// Negative means the race date is in the past. Matches `race_date - current_date`.
    static func daySpan(from today: Date, to raceDate: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        let race = calendar.startOfDay(for: raceDate)
        return calendar.dateComponents([.day], from: start, to: race).day ?? 0
    }

    /// Generator week count: `ceil(days / 7)`, with no 16-week cap.
    static func weeksUntilRace(daySpan: Int) -> Int {
        guard daySpan > 0 else { return daySpan }
        return Int(ceil(Double(daySpan) / 7.0))
    }

    static func dateNotice(
        raceDate: Date,
        targetDistance: String,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> DateNotice? {
        let days = daySpan(from: today, to: raceDate, calendar: calendar)
        if days < 0 { return .past }
        let weeks = weeksUntilRace(daySpan: days)
        let minimum = minWeeksBeforeRace[targetDistance] ?? 0
        if weeks < minimum { return .tooClose }
        if weeks > maxPlanWeeks { return .coversFinal16Weeks }
        return nil
    }

    static func suggestedDefault(today: Date = Date(), calendar: Calendar = .current) -> GroupPlanSettings {
        let distance = targetDistances[0]
        let weeks = minWeeksBeforeRace[distance] ?? maxPlanWeeks
        let date = calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: today)) ?? today
        return GroupPlanSettings(
            goal: goals[0],
            targetDistance: distance,
            raceDate: date,
            level: levels[0],
            runsPerWeek: 3
        )
    }
}

enum CoachPlanMode: String, Codable, Equatable, CaseIterable {
    case group
    case individual

    var title: String {
        switch self {
        case .group: "Group Plan"
        case .individual: "Individual Plans"
        }
    }

    var explanation: String {
        switch self {
        case .group: "One shared setup for everyone."
        case .individual: "Each athlete gets their own plan."
        }
    }
}

struct GroupPlanSettings: Equatable {
    var goal: String
    var targetDistance: String
    var raceDate: Date
    var level: String
    var runsPerWeek: Int

    func raceDateString(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: calendar.startOfDay(for: raceDate))
    }

    static func raceDate(from string: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}

struct CoachPlanSetup: Equatable {
    var mode: CoachPlanMode?
    var groupPlan: GroupPlanSettings?

    var hasGroupSettings: Bool { groupPlan != nil }
}

nonisolated protocol CoachPlanRepository: Sendable {
    func loadPlanSetup() async throws -> CoachPlanSetup
    func setPlanMode(_ mode: CoachPlanMode) async throws
    func saveGroupPlan(_ settings: GroupPlanSettings) async throws
}
