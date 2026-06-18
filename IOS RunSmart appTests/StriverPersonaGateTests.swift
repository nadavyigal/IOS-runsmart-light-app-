import XCTest
@testable import IOS_RunSmart_app

final class StriverPersonaGateTests: XCTestCase {
    func testIsStriverWhenGarminConnectedAndIntermediateProfile() {
        let runner = RunnerProfile(name: "Alex", goal: "10K", streak: "5", level: "Intermediate", totalRuns: 12, totalDistance: 220, totalTime: "24h")
        let onboarding = OnboardingProfile(
            displayName: "Alex",
            goal: "10K",
            experience: "Intermediate",
            age: 31,
            averageWeeklyDistanceKm: 18,
            trainingDataSource: .garmin,
            trainingDataUpdatedAt: Date(),
            weeklyRunDays: 4,
            preferredDays: ["Tue", "Thu", "Sat", "Sun"],
            units: "Metric",
            coachingTone: "Motivating",
            notificationsEnabled: true,
            planAdjustmentConfirmationsEnabled: true
        )

        let isStriver = StriverPersonaGate.isStriver(
            runner: runner,
            onboarding: onboarding,
            devices: [ConnectedDeviceStatus(provider: "Garmin Connect", state: .connected, lastSuccessfulSync: Date(), permissions: [], message: nil)],
            runs: []
        )

        XCTAssertTrue(isStriver)
    }

    func testIsNotStriverWithoutWearableSignal() {
        let runner = RunnerProfile(name: "Sam", goal: "5K", streak: "2", level: "Intermediate", totalRuns: 30, totalDistance: 120, totalTime: "15h")

        let isStriver = StriverPersonaGate.isStriver(
            runner: runner,
            onboarding: nil,
            devices: [ConnectedDeviceStatus(provider: "HealthKit", state: .connected, lastSuccessfulSync: nil, permissions: [], message: nil)],
            runs: []
        )

        XCTAssertFalse(isStriver)
    }

    func testIsNotStriverForBeginnerExperienceEvenWithGarmin() {
        let runner = RunnerProfile(name: "Nina", goal: "First 5K", streak: "1", level: "Building base", totalRuns: 5, totalDistance: 20, totalTime: "3h")
        var onboarding = OnboardingProfile.empty
        onboarding.trainingDataSource = .garmin
        onboarding.weeklyRunDays = 4
        onboarding.averageWeeklyDistanceKm = 16

        let isStriver = StriverPersonaGate.isStriver(
            runner: runner,
            onboarding: onboarding,
            devices: [ConnectedDeviceStatus(provider: "Garmin Connect", state: .connected, lastSuccessfulSync: Date(), permissions: [], message: nil)],
            runs: [sampleGarminRun()]
        )

        XCTAssertFalse(isStriver)
    }

    private func sampleGarminRun() -> RecordedRun {
        let start = Date().addingTimeInterval(-3600)
        return RecordedRun(
            id: UUID(),
            providerActivityID: "garmin-1",
            source: .garmin,
            startedAt: start,
            endedAt: start.addingTimeInterval(1800),
            distanceMeters: 6_000,
            movingTimeSeconds: 1800,
            averagePaceSecondsPerKm: 300,
            averageHeartRateBPM: 150,
            routePoints: [],
            syncedAt: Date()
        )
    }
}
