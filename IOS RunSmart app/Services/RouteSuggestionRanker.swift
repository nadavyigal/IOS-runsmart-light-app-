import Foundation

enum RouteSuggestionRanker {

    static let distanceTolerance: Double = 0.25

    private static func kindPriority(_ kind: RouteKind) -> Int {
        switch kind {
        case .benchmark: return 0
        case .saved:     return 1
        case .past:      return 2
        case .generated: return 3
        }
    }

    static func rank(_ suggestions: [RouteSuggestion], targetDistanceKm: Double?) -> [RouteSuggestion] {
        suggestions.sorted { a, b in
            let pa = kindPriority(a.kind)
            let pb = kindPriority(b.kind)
            if pa != pb { return pa < pb }
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
        daysSinceLastRun: Int?
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
            return "Low elevation · good for pace"
        }
    }
}
