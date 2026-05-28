import Foundation

enum StriverPersonaGate {
    static func isStriver(
        runner: RunnerProfile,
        onboarding: OnboardingProfile?,
        devices: [ConnectedDeviceStatus],
        runs: [RecordedRun]
    ) -> Bool {
        guard hasWearableSignal(onboarding: onboarding, devices: devices, runs: runs) else { return false }
        guard isIntermediateOrHigher(level: runner.level, onboardingExperience: onboarding?.experience) else { return false }

        let weeklyRunDays = onboarding?.weeklyRunDays ?? 0
        let averageWeeklyKm = onboarding?.averageWeeklyDistanceKm ?? 0
        let runCount = runs.count + runner.totalRuns

        return weeklyRunDays >= 3 || averageWeeklyKm >= 15 || runCount >= 20
    }

    private static func hasWearableSignal(
        onboarding: OnboardingProfile?,
        devices: [ConnectedDeviceStatus],
        runs: [RecordedRun]
    ) -> Bool {
        if onboarding?.trainingDataSource == .garmin { return true }
        if devices.contains(where: { $0.provider.localizedCaseInsensitiveContains("garmin") && $0.state == .connected }) {
            return true
        }
        return runs.contains(where: { $0.source == .garmin })
    }

    private static func isIntermediateOrHigher(level: String, onboardingExperience: String?) -> Bool {
        let combined = "\(level) \(onboardingExperience ?? "")".lowercased()
        let beginnerTokens = ["beginner", "rookie", "building base", "getting started", "new runner", "first 5k"]
        return beginnerTokens.allSatisfy { !combined.contains($0) }
    }
}
