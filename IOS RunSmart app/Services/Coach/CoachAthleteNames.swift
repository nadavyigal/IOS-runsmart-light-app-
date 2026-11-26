import Foundation

/// How the coach sees each athlete's name (roster, Coach Today, athlete detail).
///
/// `coach_list_athletes` sends the athlete's own name, or "Athlete" when they never set one.
/// Two unnamed athletes would then be two identical rows, so:
/// - A named athlete shows their name. The name is read fresh on every roster load, so a
///   name the athlete saves shows on the coach's next refresh.
/// - An unnamed athlete shows "Athlete · joined Nov 26", from the day they linked to this
///   coach. The coach already has that date; nothing private is added.
/// - If two rows would still read the same (same name, or unnamed on the same day), the
///   later ones get " · 2", " · 3" in the order they linked.
nonisolated enum CoachAthleteNames {
    /// The server's fallback for an athlete with no name (`public.athlete_display_name`).
    static let serverFallback = "Athlete"
    static let unnamedPrefix = "Athlete · joined "

    static func isUnnamed(_ serverName: String) -> Bool {
        guard let name = RunnerName.resolved(serverName) else { return true }
        return name == serverFallback
    }

    static func isUnnamedLabel(_ label: String) -> Bool {
        label.hasPrefix(unnamedPrefix)
    }

    static func joinedLabel(_ linkedAt: Date, locale: Locale, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.locale = locale
        style.timeZone = timeZone
        return unnamedPrefix + linkedAt.formatted(style)
    }

    /// The roster with each display name replaced by the label the coach sees.
    static func labeled(
        _ athletes: [CoachAthleteSummary],
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [CoachAthleteSummary] {
        let base: [UUID: String] = Dictionary(uniqueKeysWithValues: athletes.map { athlete in
            let label = isUnnamed(athlete.displayName)
                ? joinedLabel(athlete.linkedAt, locale: locale, timeZone: timeZone)
                : RunnerName.resolved(athlete.displayName) ?? serverFallback
            return (athlete.athleteID, label)
        })
        // Number repeats in link order; the athlete id breaks a tie so the order never flips.
        let ordered = athletes.sorted {
            $0.linkedAt != $1.linkedAt ? $0.linkedAt < $1.linkedAt
                : $0.athleteID.uuidString < $1.athleteID.uuidString
        }
        var seen: [String: Int] = [:]
        var final: [UUID: String] = [:]
        for athlete in ordered {
            let label = base[athlete.athleteID] ?? serverFallback
            let key = label.lowercased()
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            final[athlete.athleteID] = count == 1 ? label : "\(label) · \(count)"
        }
        return athletes.map { athlete in
            CoachAthleteSummary(
                athleteID: athlete.athleteID,
                displayName: final[athlete.athleteID] ?? athlete.displayName,
                linkedAt: athlete.linkedAt,
                hasActivePlan: athlete.hasActivePlan
            )
        }
    }
}

/// "{Athlete} needs the latest RunSmart", with the name isolated for Hebrew names.
nonisolated enum CoachAthleteUpdateCopy {
    static func needsUpdate(_ athlete: String) -> String {
        BidiText.fill("Effort, notes and flags aren't available. {Athlete} needs the latest RunSmart.", ["Athlete": athlete])
    }
}
