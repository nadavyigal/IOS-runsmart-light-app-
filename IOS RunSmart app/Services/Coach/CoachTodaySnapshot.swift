import Foundation

// Coach Today (story C7.1, UX spec A.3 to A.8). "Coach" means a HUMAN coach (Coach Mode).
//
// Pure logic: the 7-day dots, the groups, the one reason chip per row, the order, and the
// sentences VoiceOver reads. No view code and no network. Data comes from the existing
// `coach_get_athletes_workouts` and `coach_get_athletes_runs` results, plus `coach_roster_summary`
// for the "new since last visit" counts (C7.2).
//
// Left for later stories, so nothing here renders an empty header for them: the pain group
// (C7.4) and milestone tags (C7.16).

/// One day of the 7-day strip. Each state has its own shape and a text label. Color is the second channel.
enum CoachTodayDayState: String, CaseIterable, Equatable {
    case done, partial, missed, rest, planned, extra
    /// The runs call failed, so this day cannot be told apart. Never shown as missed.
    case unknown

    /// SF Symbol for the dots strip. Distinct shapes: filled, half, slashed, dash, ring, plus, dotted.
    var glyph: String {
        switch self {
        case .done: "circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .missed: "circle.slash"
        case .rest: "minus"
        case .planned: "circle"
        case .extra: "plus.circle.fill"
        case .unknown: "circle.dotted"
        }
    }

    /// Coach label from the grammar table.
    var label: String {
        switch self {
        case .done: "Done"
        case .partial: "Partial"
        case .missed: "Missed"
        case .rest: "Rest"
        case .planned: "Not done yet"
        case .extra: "Extra run"
        case .unknown: "Unknown"
        }
    }

    init(_ marker: CoachDayMarker) {
        switch marker {
        case .done: self = .done
        case .partial: self = .partial
        case .missed: self = .missed
        case .rest: self = .rest
        case .planned: self = .planned
        case .extra: self = .extra
        }
    }
}

/// Why a row is urgent. Lower `priority` is more urgent (UX spec A.3 item 5). C7.4 adds pain and
/// something off above these.
enum CoachTodayReason: String, Equatable, CaseIterable {
    case missedToday = "missed_today"
    case missedYesterday = "missed_yesterday"
    case behind
    // C7.2: something new since the coach last opened the athlete. Never urgent on its own.
    case reply
    case newRun = "new_run"
    case changedGoal = "changed_goal"
    case changedWorkout = "changed_workout"

    var priority: Int {
        switch self {
        case .missedToday: 10
        case .missedYesterday: 11
        case .behind: 20
        case .reply: 30
        case .newRun: 31
        case .changedGoal: 32
        case .changedWorkout: 33
        }
    }

    /// The "New to review" reasons (C7.2).
    var isNew: Bool { priority >= 30 }

    var chip: String {
        switch self {
        case .missedToday: "Missed today"
        case .missedYesterday: "Missed yesterday"
        case .behind: "Behind"
        case .reply: "Reply"
        case .newRun: "New run"
        case .changedGoal: "Changed goal"
        case .changedWorkout: "Changed your workout"
        }
    }

    var spoken: String {
        switch self {
        case .missedToday: "Missed today"
        case .missedYesterday: "Missed yesterday"
        case .behind: "Behind this week"
        case .reply: "Replied to your note"
        case .newRun: "New run"
        case .changedGoal: "Changed goal"
        case .changedWorkout: "Changed your workout"
        }
    }

    var icon: String {
        switch self {
        case .missedToday, .missedYesterday: "exclamationmark.circle"
        case .behind: "arrow.down.right.circle"
        case .reply: "arrowshape.turn.up.left"
        case .newRun: "figure.run"
        case .changedGoal: "flag"
        case .changedWorkout: "calendar.badge.exclamationmark"
        }
    }

    /// The most specific "new" reason for an athlete, in chip order (UX spec A.3 item 5). Nil when nothing is new.
    static func newReason(for news: CoachAthleteNews?) -> CoachTodayReason? {
        guard let news, news.total > 0 else { return nil }
        if news.newReplies > 0 { return .reply }
        if news.newRuns > 0 { return .newRun }
        if news.newEvents > 0 {
            switch news.latestEventKind {
            case .athleteSkip, .athleteMove: return .changedWorkout
            case .goalChange, nil: return .changedGoal
            }
        }
        // Only flags are new. C7.4 gives them their own chip and group.
        return nil
    }
}

/// The groups of T1, in screen order (UX spec A.3 item 3).
enum CoachTodayGroup: Int, CaseIterable, Comparable {
    case missedToday, missedYesterday, behind, newToReview, onTrack, restToday
    /// Used only while the runs call failed: nobody can be called on track or behind.
    case athletes
    case noPlan

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var needsYou: Bool { self == .missedToday || self == .missedYesterday || self == .behind }

    /// On track, Rest today and No plan yet start collapsed (UX spec A.3).
    var startsCollapsed: Bool { self == .onTrack || self == .restToday || self == .noPlan }

    func title(count: Int) -> String {
        switch self {
        case .missedToday: "Missed today (\(count))"
        case .missedYesterday: "Missed yesterday (\(count))"
        case .behind: "Behind this week (\(count))"
        case .newToReview: "New to review (\(count))"
        case .onTrack: "On track (\(count))"
        case .restToday: "Rest today (\(count))"
        case .athletes: "Athletes (\(count))"
        case .noPlan: "No plan yet (\(count))"
        }
    }
}

struct CoachTodayDay: Equatable, Identifiable {
    let iso: String
    let date: Date
    let state: CoachTodayDayState
    /// The sentence VoiceOver reads when the dots strip is stepped to this day.
    let spoken: String
    var id: String { iso }
}

struct CoachTodayRow: Identifiable, Equatable {
    let athlete: CoachAthleteSummary
    let group: CoachTodayGroup
    let reason: CoachTodayReason?
    /// Shown only as text in the second line, never as a second chip.
    let secondaryReason: CoachTodayReason?
    let days: [CoachTodayDay]
    /// Second line: "Tempo 6 km · Not done yet", "Rest", "Waiting for a plan".
    let todayLine: String
    /// The same facts without direction marks, for VoiceOver.
    let todaySpoken: String
    /// "{x} of {y} this week". Nil while runs are unknown or there is no plan.
    let weekProgress: String?
    let missedThisWeek: Int
    /// The day the row opens on, the reason's day (UX spec A.3 item 8).
    let focusDayISO: String
    /// C7.2: the "{n} new" number since the coach last opened this athlete. 0 shows no dot and no text.
    var newCount: Int = 0
    /// C7.2: the oldest new item, for the order inside "New to review".
    var oldestNewAt: Date?
    var id: UUID { athlete.athleteID }

    /// "{n} new" (UX spec A.6). Nil when nothing is new, so the dot never appears without its text.
    var newLabel: String? { newCount > 0 ? "\(newCount) new" : nil }
    var name: String { athlete.displayName }

    func count(_ state: CoachTodayDayState) -> Int { days.count { $0.state == state } }

    /// "4 done · 1 partial · 1 rest", the text line used from AX3 up (UX spec A.8).
    var daysSummaryText: String {
        let parts: [(CoachTodayDayState, String)] = [
            (.done, "done"), (.partial, "partial"), (.missed, "missed"), (.rest, "rest"),
            (.extra, "extra"), (.planned, "to do"), (.unknown, "unknown")
        ]
        let shown = parts.compactMap { state, word in
            count(state) > 0 ? "\(count(state)) \(word)" : nil
        }
        return shown.isEmpty ? "No days" : shown.joined(separator: " · ")
    }

    /// The one VoiceOver sentence for the row (UX spec A.8).
    var spokenSentence: String {
        let newPart = newLabel.map { " \($0)." } ?? ""
        guard athlete.hasActivePlan else {
            if let reason, reason.isNew { return "\(name). \(reason.spoken). Waiting for a plan.\(newPart)" }
            return "\(name). Waiting for a plan.\(newPart)"
        }
        var parts = [name + "."]
        if let reason { parts.append(reason.spoken + ".") }
        parts.append("Today: \(todaySpoken).")
        if count(.unknown) == days.count {
            parts.append("Last 7 days: unknown, runs didn't load.")
        } else {
            var line = "Last 7 days: \(count(.done)) done, \(count(.partial)) partial, \(count(.missed)) missed, \(count(.rest)) rest"
            if count(.extra) > 0 { line += ", \(count(.extra)) extra" }
            parts.append(line + ".")
        }
        return parts.joined(separator: " ") + newPart
    }
}

struct CoachTodaySnapshot: Equatable {
    let generatedAt: Date
    let calendar: Calendar
    let runsLoaded: Bool
    /// In display order: group first, then the order inside the group.
    let rows: [CoachTodayRow]

    var athleteCount: Int { rows.count }
    var needCount: Int { rows.count { $0.group.needsYou } }
    var planCount: Int { rows.count { $0.group != .noPlan } }

    /// Groups that have rows. A group with no rows has no header.
    var groups: [CoachTodayGroup] {
        CoachTodayGroup.allCases.filter { group in rows.contains { $0.group == group } }
    }

    func rows(in group: CoachTodayGroup) -> [CoachTodayRow] { rows.filter { $0.group == group } }

    /// What changes the screen. If a refresh leaves this equal, nothing needs a "New updates" pill.
    var layoutSignature: [String] {
        rows.map { row in
            let days = row.days.map(\.state.rawValue).joined(separator: ",")
            return [row.id.uuidString, row.group.rawValue.description, row.reason?.rawValue ?? "-",
                    row.secondaryReason?.rawValue ?? "-", row.todayLine, row.weekProgress ?? "-", days,
                    String(row.newCount)]
                .joined(separator: "|")
        } + [runsLoaded ? "runs" : "no-runs"]
    }

    /// Header line under "Today, {weekday} {d} {Mon}" (UX spec A.3, A.5, A.6).
    var summaryLine: String? {
        if athleteCount == 0 { return "No athletes yet" }
        if planCount == 0 { return "Nobody has a plan yet" }
        // With the runs call failed nobody can be called caught up.
        guard runsLoaded else { return nil }
        switch needCount {
        case 0: return "You're caught up for today"
        case 1: return "1 athlete needs you"
        default: return "\(needCount) athletes need you"
        }
    }

    /// Sub-line of the caught-up state: "{n} on track · {m} rest days".
    var caughtUpDetail: String? {
        guard runsLoaded, planCount > 0, needCount == 0 else { return nil }
        let onTrack = rows.count { $0.group == .onTrack }
        let rest = rows.count { $0.group == .restToday }
        return "\(onTrack) on track · \(rest) rest \(rest == 1 ? "day" : "days")"
    }

    /// "Today, Tue 24 Nov". The weekday and month words follow the coach's locale.
    func headerTitle(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "EEE d MMM"
        return "Today, " + formatter.string(from: generatedAt)
    }
}

// MARK: Builder

extension CoachTodaySnapshot {
    /// - Parameters:
    ///   - workouts: every workout from the 7-day window to the end of the training week.
    ///   - runs: runs from the 7-day window. Pass `runsLoaded: false` (and any runs) when the runs call
    ///     failed: every day then reads "unknown" and nobody is put in a missed or behind group.
    ///   - news: C7.2 counts from `coach_roster_summary`. An athlete with something new and nothing urgent
    ///     goes to "New to review". Empty (the call failed, or the pair is not v2) shows no markers.
    static func make(
        athletes: [CoachAthleteSummary], workouts: [CoachWorkoutSummary], runs: [CoachRunSummary],
        runsLoaded: Bool = true, news: [UUID: CoachAthleteNews] = [:], now: Date, week: CoachAthleteWeek,
        locale: Locale = .current
    ) -> CoachTodaySnapshot {
        let calendar = week.calendar
        let workoutsByAthlete = Dictionary(grouping: workouts, by: \.athleteID)
        let runsByAthlete = Dictionary(grouping: runs, by: \.athleteID)
        let todayISO = CoachReadDay.iso(now, calendar: calendar)
        let yesterdayISO = CoachReadDay.iso(calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar)
        let afterCutoff = calendar.component(.hour, from: now) >= WorkoutAdherence.missedCutoffHour
        let boundary = WorkoutAdherence.missedBoundary(now: now, calendar: calendar)
        let weekStartISO = CoachReadDay.iso(week.interval.start, calendar: calendar)
        let weekEndISO = CoachReadDay.iso(week.lastDay, calendar: calendar)

        let built = athletes.map { athlete -> (row: CoachTodayRow, earliestMissed: String?) in
            let athleteWorkouts = workoutsByAthlete[athlete.athleteID, default: []]
            let days = CoachAthleteDays.recentDays(
                workouts: athleteWorkouts, runs: runsByAthlete[athlete.athleteID, default: []],
                now: now, calendar: calendar
            )
            let states = days.map { runsLoaded ? CoachTodayDayState(Self.marker(of: $0)) : .unknown }
            let todayDay = days[days.count - 1]
            let hasPlan = athlete.hasActivePlan

            let weekDays = days.filter { week.contains($0.date) }
            let weekItems = weekDays.flatMap(\.workouts)
            let missedDays = zip(days, states).filter { $0.1 == .missed }.map(\.0.iso)
            let missedThisWeek = weekDays.count { day in missedDays.contains(day.iso) }

            var reasons: [CoachTodayReason] = []
            if runsLoaded && hasPlan {
                if afterCutoff {
                    if missedDays.contains(todayISO) { reasons.append(.missedToday) }
                } else if missedDays.contains(yesterdayISO) {
                    reasons.append(.missedYesterday)
                }
                if missedThisWeek >= 2 || weekToDateBelowEightyPercent(weekItems, boundary: boundary) {
                    reasons.append(.behind)
                }
            }
            let athleteNews = news[athlete.athleteID]
            let newCount = athleteNews?.total ?? 0
            if let newReason = CoachTodayReason.newReason(for: athleteNews) { reasons.append(newReason) }
            reasons.sort { $0.priority < $1.priority }
            let reason = reasons.first
            let secondary = reasons.dropFirst().first

            let group: CoachTodayGroup
            if reason?.isNew == true {
                // New and nothing urgent (UX spec A.3 item 3.4). No runs or no plan needed for this.
                group = .newToReview
            } else if !hasPlan {
                group = .noPlan
            } else if !runsLoaded {
                group = .athletes
            } else {
                switch reason {
                case .missedToday: group = .missedToday
                case .missedYesterday: group = .missedYesterday
                case .behind: group = .behind
                case .reply, .newRun, .changedGoal, .changedWorkout: group = .newToReview
                case nil: group = todayDay.workouts.isEmpty ? .restToday : .onTrack
                }
            }

            let plannedThisWeek = athleteWorkouts.filter {
                WorkoutAdherence.counts($0) && $0.scheduledDate >= weekStartISO && $0.scheduledDate <= weekEndISO
            }.count
            let doneThisWeek = weekItems.count { $0.state == .done }
            let focus: String
            switch reason {
            case .missedYesterday: focus = yesterdayISO
            case .behind: focus = weekDays.last { missedDays.contains($0.iso) }?.iso ?? todayISO
            case .missedToday, .reply, .newRun, .changedGoal, .changedWorkout, nil: focus = todayISO
            }
            let line = CoachTodayFormat.todayLine(
                hasPlan: hasPlan, day: todayDay, runsLoaded: runsLoaded, secondary: secondary, isolated: true
            )
            let spoken = CoachTodayFormat.todayLine(
                hasPlan: hasPlan, day: todayDay, runsLoaded: runsLoaded, secondary: nil, isolated: false, spoken: true
            )
            let dayList = zip(days, states).map { day, state in
                CoachTodayDay(
                    iso: day.iso, date: day.date, state: state,
                    spoken: CoachTodayFormat.daySentence(day, state: state, calendar: calendar, locale: locale)
                )
            }
            let row = CoachTodayRow(
                athlete: athlete, group: group, reason: reason, secondaryReason: secondary, days: dayList,
                todayLine: line, todaySpoken: spoken,
                weekProgress: runsLoaded && hasPlan ? "\(doneThisWeek) of \(plannedThisWeek) this week" : nil,
                missedThisWeek: missedThisWeek, focusDayISO: focus,
                newCount: newCount, oldestNewAt: newCount > 0 ? athleteNews?.oldestNewAt : nil
            )
            return (row, missedDays.first)
        }

        // More urgent first (more misses), then the oldest miss, then name. Ties end on the id so
        // the order never depends on the server's row order.
        let ordered = built.sorted { lhs, rhs in
            if lhs.row.group != rhs.row.group { return lhs.row.group < rhs.row.group }
            if lhs.row.group == .newToReview, lhs.row.oldestNewAt != rhs.row.oldestNewAt {
                // The oldest unhandled item first (UX spec A.3 item 6).
                return (lhs.row.oldestNewAt ?? .distantFuture) < (rhs.row.oldestNewAt ?? .distantFuture)
            }
            if lhs.row.group.needsYou {
                if lhs.row.missedThisWeek != rhs.row.missedThisWeek {
                    return lhs.row.missedThisWeek > rhs.row.missedThisWeek
                }
                if lhs.earliestMissed != rhs.earliestMissed {
                    return (lhs.earliestMissed ?? "9999") < (rhs.earliestMissed ?? "9999")
                }
            }
            let compared = lhs.row.name.localizedStandardCompare(rhs.row.name)
            return compared == .orderedSame ? lhs.row.id.uuidString < rhs.row.id.uuidString : compared == .orderedAscending
        }.map(\.row)

        return CoachTodaySnapshot(generatedAt: now, calendar: calendar, runsLoaded: runsLoaded, rows: ordered)
    }

    private static func marker(of day: CoachDay) -> CoachDayMarker { day.marker }

    /// The 80% rule for the week to date: workouts that were due, each credited with how much of the
    /// plan the athlete did (a done workout counts as all of it). Below 80% on average is behind.
    /// ASSUMPTION (UX spec A.3 item 3): "the 80% rule failing for the week to date" reads this way.
    static func weekToDateBelowEightyPercent(_ items: [CoachDayWorkout], boundary: String) -> Bool {
        let due = items.filter { $0.workout.scheduledDate < boundary }
        guard !due.isEmpty else { return false }
        let credits = due.map { item -> Double in
            switch item.state {
            case .done, .extra: return 1
            case .missed, .planned: return 0
            case .partial:
                guard let run = item.run else { return 0 }
                if item.workout.plannedDistance > 0 { return min(run.distanceKm / item.workout.plannedDistance, 1) }
                if let minutes = item.workout.plannedDurationMinutes, minutes > 0 {
                    return min(Double(run.durationSeconds) / (Double(minutes) * 60), 1)
                }
                return 0
            }
        }
        return credits.reduce(0, +) / Double(credits.count) < 0.8
    }
}

// MARK: Text

enum CoachTodayFormat {
    static func isolate(_ text: String, _ isolated: Bool) -> String {
        isolated ? CoachMetricFormat.isolate(text) : text
    }

    /// "5" for 5.0 and 5.04, "5.2" for 5.2.
    static func km(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    static func workoutName(_ type: String) -> String {
        switch type.lowercased() {
        case "easy": "Easy"
        case "tempo": "Tempo"
        case "race-pace": "Race pace"
        case "intervals": "Intervals"
        case "hill": "Hills"
        case "long": "Long run"
        case "recovery": "Recovery"
        case "fartlek": "Fartlek"
        default: type.capitalized
        }
    }

    /// "Tempo 6 km", "Easy 40 min" or just "Tempo".
    static func workoutLabel(_ workout: CoachWorkoutSummary, isolated: Bool) -> String {
        let name = workoutName(workout.type)
        if workout.plannedDistance > 0 { return name + " " + isolate("\(km(workout.plannedDistance)) km", isolated) }
        if let minutes = workout.plannedDurationMinutes, minutes > 0 { return name + " " + isolate("\(minutes) min", isolated) }
        return name
    }

    /// "Not done yet", "Done 5.2 km", "Partial 4 of 6 km", "Missed". Minutes stand in when only a duration was planned.
    static func status(_ item: CoachDayWorkout, isolated: Bool) -> String {
        switch item.state {
        case .planned: return "Not done yet"
        case .missed: return "Missed"
        case .extra: return "Extra run"
        case .done, .partial:
            guard let run = item.run else { return item.state == .done ? "Done" : "Partial" }
            let word = item.state == .done ? "Done" : "Partial"
            if item.workout.plannedDistance > 0 {
                let actual = km(run.distanceKm)
                return item.state == .done
                    ? "\(word) " + isolate("\(actual) km", isolated)
                    : "\(word) " + isolate("\(actual) of \(km(item.workout.plannedDistance)) km", isolated)
            }
            if let minutes = item.workout.plannedDurationMinutes, minutes > 0 {
                let actual = run.durationSeconds / 60
                return item.state == .done
                    ? "\(word) " + isolate("\(actual) min", isolated)
                    : "\(word) " + isolate("\(actual) of \(minutes) min", isolated)
            }
            return word
        }
    }

    static func todayLine(
        hasPlan: Bool, day: CoachDay, runsLoaded: Bool, secondary: CoachTodayReason?, isolated: Bool,
        spoken: Bool = false
    ) -> String {
        guard hasPlan else { return "Waiting for a plan" }
        var line: String
        if let item = day.workouts.first {
            let title = workoutLabel(item.workout, isolated: isolated)
            let status = runsLoaded ? status(item, isolated: isolated) : "Unknown"
            line = spoken ? "\(title), \(status.lowercased())" : "\(title) · \(status)"
        } else if runsLoaded, !day.extraRuns.isEmpty {
            let total = day.extraRuns.reduce(0) { $0 + $1.distanceKm }
            line = "Extra run " + isolate("\(km(total)) km", isolated)
            if spoken { line = line.lowercased() }
        } else {
            line = runsLoaded ? (spoken ? "rest" : "Rest") : (spoken ? "unknown" : "Unknown")
        }
        if let secondary { line += " · " + secondary.spoken }
        return line
    }

    /// "Sunday 22 November: Long run 10 km, done 10.4 km." Stepped through by the adjustable dots strip.
    static func daySentence(_ day: CoachDay, state: CoachTodayDayState, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "EEEE d MMMM"
        let date = formatter.string(from: day.date)
        if state == .unknown { return "\(date): unknown, runs didn't load." }
        if day.workouts.isEmpty && day.extraRuns.isEmpty { return "\(date): rest day." }
        var parts: [String] = []
        for item in day.workouts {
            let planned = item.workout.plannedDistance > 0 ? "\(km(item.workout.plannedDistance)) kilometres"
                : (item.workout.plannedDurationMinutes.map { "\($0) minutes" })
            let title = [workoutName(item.workout.type), planned].compactMap { $0 }.joined(separator: " ")
            var status: String
            switch item.state {
            case .planned: status = "not done yet"
            case .missed: status = "missed"
            case .extra: status = "extra run"
            case .done, .partial:
                let word = item.state == .done ? "done" : "partial"
                status = item.run.map { "\(word) \(km($0.distanceKm)) kilometres" } ?? word
            }
            parts.append("\(title), \(status)")
        }
        for run in day.extraRuns { parts.append("extra run \(km(run.distanceKm)) kilometres") }
        return "\(date): " + parts.joined(separator: "; ") + "."
    }
}
