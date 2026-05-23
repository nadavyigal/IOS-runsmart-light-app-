import Foundation

enum RouteSuggestionRanker {

    nonisolated static let distanceTolerance: Double = 0.25

    // Elevation thresholds in metres
    nonisolated private static let flatCeiling = 50
    nonisolated private static let rollingCeiling = 150

    nonisolated private static func kindPriority(_ kind: RouteKind) -> Int {
        switch kind {
        case .benchmark: return 0
        case .saved:     return 1
        case .past:      return 2
        case .generated: return 3
        }
    }

    // Score 0 (perfect match) → higher for mismatch; lower is better.
    nonisolated private static func elevationScore(_ elevationGainMeters: Int, preference: String) -> Int {
        switch preference {
        case "Flat":
            return elevationGainMeters <= flatCeiling ? 0 : (elevationGainMeters <= rollingCeiling ? 1 : 2)
        case "Hilly":
            return elevationGainMeters > rollingCeiling ? 0 : (elevationGainMeters > flatCeiling ? 1 : 2)
        default: // "Rolling"
            let inRange = elevationGainMeters > flatCeiling && elevationGainMeters <= rollingCeiling
            return inRange ? 0 : 1
        }
    }

    nonisolated private static func surfaceScore(_ suggestion: RouteSuggestion, preference: String) -> Int {
        switch preference {
        case "Road":
            if suggestion.elevationGainMeters <= rollingCeiling { return 0 }
            return suggestion.kind == .generated ? 1 : 2
        case "Trail":
            if suggestion.elevationGainMeters > flatCeiling { return 0 }
            return suggestion.kind == .past || suggestion.kind == .benchmark ? 1 : 2
        default:
            return 0
        }
    }

    nonisolated static func rank(_ suggestions: [RouteSuggestion], targetDistanceKm: Double?) -> [RouteSuggestion] {
        rank(suggestions, targetDistanceKm: targetDistanceKm, elevationPreference: "Rolling")
    }

    nonisolated static func rank(
        _ suggestions: [RouteSuggestion],
        targetDistanceKm: Double?,
        elevationPreference: String
    ) -> [RouteSuggestion] {
        rank(
            suggestions,
            targetDistanceKm: targetDistanceKm,
            elevationPreference: elevationPreference,
            surfacePreference: "Mixed"
        )
    }

    nonisolated static func rank(
        _ suggestions: [RouteSuggestion],
        targetDistanceKm: Double?,
        elevationPreference: String,
        surfacePreference: String
    ) -> [RouteSuggestion] {
        suggestions.sorted { a, b in
            let pa = kindPriority(a.kind)
            let pb = kindPriority(b.kind)
            if pa != pb { return pa < pb }
            let ea = elevationScore(a.elevationGainMeters, preference: elevationPreference)
            let eb = elevationScore(b.elevationGainMeters, preference: elevationPreference)
            if ea != eb { return ea < eb }
            let sa = surfaceScore(a, preference: surfacePreference)
            let sb = surfaceScore(b, preference: surfacePreference)
            if sa != sb { return sa < sb }
            guard let target = targetDistanceKm else { return false }
            return abs(a.distanceKm - target) < abs(b.distanceKm - target)
        }
    }

    nonisolated static func recommendation(
        from suggestions: [RouteSuggestion],
        workout: WorkoutSummary?,
        fallbackDistanceLabel: String? = nil
    ) -> RouteRecommendation {
        let targetDistance = workout.flatMap { distanceKm(from: $0.distance) } ?? fallbackDistanceLabel.flatMap(distanceKm)
        guard !suggestions.isEmpty else {
            return .unavailable(.noRoutes)
        }

        let ranked = suggestions
            .map { suggestion in
                (suggestion, fitScore(for: suggestion, targetDistanceKm: targetDistance, workoutKind: workout?.kind))
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return kindPriority(lhs.0.kind) < kindPriority(rhs.0.kind)
            }

        guard let best = ranked.first else {
            return .unavailable(.noRoutes)
        }

        let warning = warning(for: best.0, targetDistanceKm: targetDistance)
        let reason = recommendationReason(
            for: best.0,
            targetDistanceKm: targetDistance,
            workoutKind: workout?.kind,
            warning: warning
        )

        return RouteRecommendation(
            route: best.0,
            reason: reason,
            fitScore: best.1,
            warning: warning,
            unavailableReason: nil
        )
    }

    nonisolated static func fitScore(
        for suggestion: RouteSuggestion,
        targetDistanceKm: Double?,
        workoutKind: WorkoutKind?
    ) -> Int {
        var score = 45
        switch suggestion.kind {
        case .benchmark:
            score += 22
        case .saved:
            score += suggestion.isFavorite ? 18 : 12
        case .generated:
            score += 8
        case .past:
            score += 4
        }

        if let targetDistanceKm, targetDistanceKm > 0 {
            let distanceRatio = abs(suggestion.distanceKm - targetDistanceKm) / targetDistanceKm
            switch distanceRatio {
            case ...0.05: score += 28
            case ...0.10: score += 22
            case ...0.20: score += 14
            case ...0.30: score += 6
            default: score -= min(24, Int((distanceRatio * 30).rounded()))
            }
        }

        if suggestion.points.isEmpty {
            score -= suggestion.kind == .generated ? 18 : 10
        }

        if let workoutKind {
            switch workoutKind {
            case .tempo, .intervals:
                if suggestion.elevationGainMeters <= flatCeiling { score += 8 }
            case .hills:
                if suggestion.elevationGainMeters > flatCeiling { score += 8 }
            case .long:
                if suggestion.kind == .benchmark || suggestion.kind == .saved { score += 6 }
            case .race, .parkrun:
                if suggestion.kind == .benchmark { score += 10 }
            case .recovery, .easy:
                if suggestion.elevationGainMeters <= rollingCeiling { score += 5 }
            case .strength:
                score -= 8
            }
        }

        return max(0, min(100, score))
    }

    nonisolated static func filter(_ suggestions: [RouteSuggestion], targetDistanceKm: Double?) -> [RouteSuggestion] {
        guard let target = targetDistanceKm else { return suggestions }
        return suggestions.filter { abs($0.distanceKm - target) / target <= distanceTolerance }
    }

    nonisolated static func reason(
        kind: RouteKind,
        distanceKm: Double,
        targetDistanceKm: Double?,
        isFavorite: Bool,
        daysSinceLastRun: Int?,
        elevationPreference: String = "Rolling",
        surfacePreference: String = "Mixed"
    ) -> String {
        switch kind {
        case .benchmark:
            if let target = targetDistanceKm, abs(distanceKm - target) / target <= 0.1 {
                return "Matches today's \(Int(target.rounded())) km"
            }
            return "Benchmark route"
        case .saved:
            return isFavorite ? "Saved · Favorite" : "Saved route"
        case .past:
            if let days = daysSinceLastRun {
                if days == 0 { return "Ran today · familiar route" }
                if days == 1 { return "Ran yesterday · familiar route" }
                return "Ran \(days) days ago · familiar route"
            }
            return "Recent route"
        case .generated:
            let elevation: String
            switch elevationPreference {
            case "Flat":   elevation = "Flat"
            case "Hilly":  elevation = "Hilly"
            default:       elevation = "Rolling"
            }
            return "\(surfacePreference) · \(elevation.lowercased()) fit"
        }
    }

    nonisolated static func distanceKm(from label: String) -> Double? {
        let lowercased = label.lowercased()
        let normalized = lowercased
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "kilometers", with: "km")
            .replacingOccurrences(of: "kilometres", with: "km")
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(km|k|mi|mile|miles)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let valueRange = Range(match.range(at: 1), in: normalized),
              let value = Double(normalized[valueRange]) else {
            return nil
        }

        if match.numberOfRanges > 2,
           let unitRange = Range(match.range(at: 2), in: normalized),
           normalized[unitRange].hasPrefix("mi") {
            return value * 1.60934
        }

        return value
    }

    nonisolated private static func recommendationReason(
        for suggestion: RouteSuggestion,
        targetDistanceKm: Double?,
        workoutKind: WorkoutKind?,
        warning: String?
    ) -> String {
        if let existing = suggestion.recommendationReason, !existing.isEmpty, warning == nil {
            return existing
        }

        let distanceText = targetDistanceKm.map { String(format: "%.1f km", $0) } ?? "today's workout"
        switch workoutKind {
        case .tempo, .intervals:
            return "Best fit for \(distanceText): manageable elevation for pace work."
        case .hills:
            return "Best fit for \(distanceText): enough elevation for today's hill intent."
        case .long:
            return "Best fit for \(distanceText): repeatable route for a longer effort."
        case .race, .parkrun:
            return "Best fit for \(distanceText): benchmark-style route for a measured effort."
        case .recovery:
            return "Best fit for \(distanceText): conservative route choice for recovery."
        case .easy:
            return "Best fit for \(distanceText): familiar route at an easy effort."
        case .strength:
            return "Route optional today; this is the closest saved option."
        case nil:
            return "Best available route from your library."
        }
    }

    nonisolated private static func warning(for suggestion: RouteSuggestion, targetDistanceKm: Double?) -> String? {
        if suggestion.points.isEmpty {
            return "No route map points are available, so RunSmart can compare distance but not turn-by-turn shape."
        }

        guard let targetDistanceKm, targetDistanceKm > 0 else { return nil }
        let ratio = abs(suggestion.distanceKm - targetDistanceKm) / targetDistanceKm
        if ratio > distanceTolerance {
            return "Distance is outside the usual route-fit range for today's workout."
        }
        return nil
    }
}
