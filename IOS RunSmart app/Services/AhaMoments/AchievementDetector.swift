import Foundation

enum AchievementContext: Equatable {
    case firstRun(distanceKm: Double)
    case personalBest(distanceKm: Double, previousBestKm: Double)
    case showedUp
}

enum AchievementDetector {

    private static let shortRunThresholdKm = 0.3

    static func detect(currentRun: RecordedRun, priorRuns: [RecordedRun]) -> AchievementContext? {
        let currentKm = currentRun.distanceMeters / 1_000
        guard currentKm > 0 else { return nil }

        let prior = priorRuns.filter { $0.id != currentRun.id }
        if prior.isEmpty {
            if currentKm < shortRunThresholdKm {
                return .showedUp
            }
            return .firstRun(distanceKm: currentKm)
        }

        let previousBestKm = prior.map { $0.distanceMeters / 1_000 }.max() ?? 0
        if currentKm > previousBestKm {
            if currentKm < shortRunThresholdKm {
                return .showedUp
            }
            return .personalBest(distanceKm: currentKm, previousBestKm: previousBestKm)
        }

        return nil
    }
}
