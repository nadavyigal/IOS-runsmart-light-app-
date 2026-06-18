import Foundation

enum BenchmarkComparisonPresentation {
    static func durationLabel(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func paceLabel(_ secondsPerKm: Double) -> String {
        RunRecorder.paceLabel(secondsPerKm: secondsPerKm)
    }

    static func confidenceLabel(_ confidence: RouteMatchConfidence) -> String {
        switch confidence {
        case .matched: "Matched"
        case .possibleMatch: "Possible"
        case .noMatch: "No match"
        }
    }

    static func trendLabel(_ trend: BenchmarkRouteTrend) -> String {
        switch trend {
        case .improving: "Improving"
        case .steady: "Steady"
        case .slowing: "Slower"
        case .notEnoughData: "Building history"
        }
    }

    static func deltaLabel(current: TimeInterval, baseline: TimeInterval) -> String {
        let delta = current - baseline
        if abs(delta) < 0.5 { return "Even" }
        let prefix = delta < 0 ? "-" : "+"
        return "\(prefix)\(durationLabel(abs(delta)))"
    }

    static func insights(for comparison: BenchmarkRouteComparison) -> [String] {
        var insights: [String] = []
        let current = comparison.currentPerformance

        if let previous = comparison.previousPerformance {
            let delta = previous.durationSeconds - current.durationSeconds
            if abs(delta) < 1 {
                insights.append("You matched your previous time on this route.")
            } else if delta > 0 {
                insights.append("You were \(durationLabel(delta)) faster than your previous run on this route.")
            } else {
                insights.append("You were \(durationLabel(abs(delta))) slower than your previous run on this route.")
            }
        } else {
            insights.append("This is your first tracked benchmark effort on this route.")
        }

        if comparison.personalBest.runID == current.runID {
            insights.append("This is your personal best on \(comparison.routeName).")
        } else {
            let pbDelta = current.durationSeconds - comparison.personalBest.durationSeconds
            if pbDelta > 0 {
                insights.append("You are \(durationLabel(pbDelta)) off your route PB.")
            }
        }

        if comparison.monthlyAverage.hasEnoughData {
            let paceDelta = comparison.monthlyAverage.averagePaceSecondsPerKm - current.paceSecondsPerKm
            if abs(paceDelta) < 1 {
                insights.append("Your pace matched this month's route average.")
            } else if paceDelta > 0 {
                insights.append("You ran faster than this month's average pace.")
            } else {
                insights.append("You ran slower than this month's average pace.")
            }
        } else if !comparison.hasEnoughHistory {
            insights.append("Run this benchmark again to unlock route trends.")
        }

        return Array(insights.prefix(3))
    }
}
