import Foundation

enum RouteSuggestionRanker {

    static let distanceTolerance: Double = 0.25

    // Elevation thresholds in metres
    private static let flatCeiling = 50
    private static let rollingCeiling = 150

    private static func kindPriority(_ kind: RouteKind) -> Int {
        switch kind {
        case .benchmark: return 0
        case .saved:     return 1
        case .past:      return 2
        case .generated: return 3
        }
    }

    // Score 0 (perfect match) → higher for mismatch; lower is better.
    private static func elevationScore(_ elevationGainMeters: Int, preference: String) -> Int {
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

    static func rank(_ suggestions: [RouteSuggestion], targetDistanceKm: Double?) -> [RouteSuggestion] {
        rank(suggestions, targetDistanceKm: targetDistanceKm, elevationPreference: "Rolling")
    }

    static func rank(
        _ suggestions: [RouteSuggestion],
        targetDistanceKm: Double?,
        elevationPreference: String
    ) -> [RouteSuggestion] {
        suggestions.sorted { a, b in
            let pa = kindPriority(a.kind)
            let pb = kindPriority(b.kind)
            if pa != pb { return pa < pb }
            let ea = elevationScore(a.elevationGainMeters, preference: elevationPreference)
            let eb = elevationScore(b.elevationGainMeters, preference: elevationPreference)
            if ea != eb { return ea < eb }
            guard let target = targetDistanceKm else { return false }
            return abs(a.distanceKm - target) < abs(b.distanceKm - target)
        }
    }

    static func filter(_ suggestions: [RouteSuggestion], targetDistanceKm: Double?) -> [RouteSuggestion] {
        guard let target = targetDistanceKm else { return suggestions }
        return suggestions.filter { abs($0.distanceKm - target) / target <= distanceTolerance }
    }

    static func reason(
        kind: RouteKind,
        distanceKm: Double,
        targetDistanceKm: Double?,
        isFavorite: Bool,
        daysSinceLastRun: Int?,
        elevationPreference: String = "Rolling"
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
            switch elevationPreference {
            case "Flat":   return "Flat · good for pace"
            case "Hilly":  return "Hilly · elevation challenge"
            default:       return "Low elevation · good for pace"
            }
        }
    }
}
