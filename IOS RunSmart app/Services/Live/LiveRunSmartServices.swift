import Foundation
import CoreLocation

struct LiveTodayService: TodayProviding {
    let apiClient: any RunSmartAPIClient

    func todayRecommendation() async -> TodayRecommendation {
        let dto = RunSmartDTO.TodayPayload(
            readinessScore: 80,
            readinessLabel: "High",
            workoutTitle: "Tempo Builder",
            plannedDistanceLabel: "8.0 km",
            targetPaceLabel: "5'20\" /km",
            elevationLabel: "120 m",
            coachMessage: "Live endpoint not wired yet. This payload shape is the planned contract."
        )
        return RunSmartDTOMapper.todayRecommendation(from: dto)
    }
}

struct LivePlanService: PlanProviding {
    let apiClient: any RunSmartAPIClient

    func weeklyPlan() async -> [WorkoutSummary] {
        let dto = RunSmartDTO.PlanPayload(
            weekStartISO8601: "2026-04-27",
            weekEndISO8601: "2026-05-03",
            workouts: [
                .init(workoutID: "wk_1", weekday: "MON", dateLabel: "28", kind: "easy_run", title: "Easy Run", distanceLabel: "5 km", detailLabel: "Done", isToday: false, isComplete: true),
                .init(workoutID: "wk_2", weekday: "TUE", dateLabel: "29", kind: "intervals", title: "Intervals", distanceLabel: "8 x 400m", detailLabel: "Done", isToday: false, isComplete: true),
                .init(workoutID: "wk_3", weekday: "WED", dateLabel: "30", kind: "tempo_run", title: "Tempo Run", distanceLabel: "8.0 km", detailLabel: "Today", isToday: true, isComplete: false)
            ]
        )
        _ = dto.weekStartISO8601
        _ = dto.weekEndISO8601
        return dto.workouts.map(RunSmartDTOMapper.workoutSummary(from:))
    }

    func activeTrainingPlan() async -> TrainingPlanSnapshot? { nil }
    func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary] { [] }
    func nextWorkouts(limit: Int) async -> [WorkoutSummary] { [] }
    func saveSuggestedWorkout(_ suggestion: StructuredNextWorkout, from report: RunReportDetail) async -> Bool {
        await ProductionRunSmartServices().saveSuggestedWorkout(suggestion, from: report)
    }
}

struct LiveCoachChatService: CoachChatting {
    let apiClient: any RunSmartAPIClient

    func recentMessages() async -> [CoachMessage] {
        let dto = RunSmartDTO.CoachConversationPayload(
            threadID: "thread_demo",
            messages: [
                .init(messageID: "msg_1", text: "How are your legs feeling today?", timeLabel: "7:30 AM", role: "assistant"),
                .init(messageID: "msg_2", text: "Pretty good, just slight fatigue.", timeLabel: "7:31 AM", role: "user")
            ]
        )
        _ = dto.threadID
        return dto.messages.map(RunSmartDTOMapper.coachMessage(from:))
    }

    func send(message: String) async -> CoachMessage {
        let request = RunSmartDTO.SendCoachMessageRequest(threadID: nil, text: message)
        let dto = RunSmartDTO.CoachChatMessage(
            messageID: "msg_local_echo",
            text: request.text,
            timeLabel: "Just now",
            role: "user"
        )
        return RunSmartDTOMapper.coachMessage(from: dto)
    }
}

struct LiveProfileService: ProfileProviding {
    let apiClient: any RunSmartAPIClient

    func runnerProfile() async -> RunnerProfile {
        let dto = RunSmartDTO.UserProfile(
            userID: "user_demo",
            displayName: "Alex Morgan",
            email: nil,
            goal: "10K focused",
            level: "Peak Performer",
            streakLabel: "11-week streak",
            stats: .init(totalRuns: 128, totalDistanceKm: 842, totalTimeLabel: "83h 21m")
        )
        _ = dto.userID
        _ = dto.email
        return RunSmartDTOMapper.runnerProfile(from: dto)
    }

    func achievements() async -> [Achievement] {
        []
    }
}

struct LiveRunLoggingService: RunLogging {
    let apiClient: any RunSmartAPIClient

    func currentRunMetrics() async -> [MetricTile] {
        let dto = RunSmartDTO.CurrentRunMetricsPayload(
            distanceKm: "5.24",
            pacePerKm: "5:08",
            elapsedTime: "26:54",
            heartRateBPM: "154"
        )
        return RunSmartDTOMapper.metricTiles(from: dto)
    }

    func recentRuns() async -> [RecordedRun] {
        []
    }

    func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun {
        await ProductionRunSmartServices().saveManualRun(
            kind: kind,
            date: date,
            distanceKm: distanceKm,
            durationMinutes: durationMinutes,
            averageHeartRateBPM: averageHeartRateBPM,
            notes: notes
        )
    }

    func removeRun(_ run: RecordedRun) async -> Bool {
        await ProductionRunSmartServices().removeRun(run)
    }

    func finishRun() async {
        let now = ISO8601DateFormatter().string(from: Date())
        let runLog = RunSmartDTO.RunLogRequest(
            startedAtISO8601: now,
            endedAtISO8601: now,
            distanceMeters: 5_240,
            movingTimeSeconds: 1_614,
            averagePaceSecondsPerKm: 308,
            averageHeartRateBPM: 154,
            routePoints: []
        )
        _ = runLog
    }
}

struct LiveRunSmartServices: RunSmartServiceProviding {
    private let todayService: LiveTodayService
    private let planService: LivePlanService
    private let coachService: LiveCoachChatService
    private let profileService: LiveProfileService
    private let runLoggingService: LiveRunLoggingService

    init(apiClient: any RunSmartAPIClient) {
        todayService = LiveTodayService(apiClient: apiClient)
        planService = LivePlanService(apiClient: apiClient)
        coachService = LiveCoachChatService(apiClient: apiClient)
        profileService = LiveProfileService(apiClient: apiClient)
        runLoggingService = LiveRunLoggingService(apiClient: apiClient)
    }

    func todayRecommendation() async -> TodayRecommendation {
        await todayService.todayRecommendation()
    }

    func weeklyPlan() async -> [WorkoutSummary] {
        await planService.weeklyPlan()
    }

    func activeTrainingPlan() async -> TrainingPlanSnapshot? {
        await planService.activeTrainingPlan()
    }

    func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary] {
        await planService.planWorkouts(from: startDate, to: endDate)
    }

    func nextWorkouts(limit: Int) async -> [WorkoutSummary] {
        await planService.nextWorkouts(limit: limit)
    }

    func saveSuggestedWorkout(_ suggestion: StructuredNextWorkout, from report: RunReportDetail) async -> Bool {
        await planService.saveSuggestedWorkout(suggestion, from: report)
    }

    func recentMessages() async -> [CoachMessage] {
        await coachService.recentMessages()
    }

    func send(message: String) async -> CoachMessage {
        await coachService.send(message: message)
    }

    func runnerProfile() async -> RunnerProfile {
        await profileService.runnerProfile()
    }

    func achievements() async -> [Achievement] {
        await profileService.achievements()
    }

    func currentRunMetrics() async -> [MetricTile] {
        await runLoggingService.currentRunMetrics()
    }

    func recentRuns() async -> [RecordedRun] {
        await runLoggingService.recentRuns()
    }

    func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun {
        await runLoggingService.saveManualRun(
            kind: kind,
            date: date,
            distanceKm: distanceKm,
            durationMinutes: durationMinutes,
            averageHeartRateBPM: averageHeartRateBPM,
            notes: notes
        )
    }

    func removeRun(_ run: RecordedRun) async -> Bool {
        await runLoggingService.removeRun(run)
    }

    func finishRun() async {
        await runLoggingService.finishRun()
    }

    func routeSuggestions() async -> [RouteSuggestion] {
        []
    }

    func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion] {
        []
    }

    func deviceStatuses() async -> [ConnectedDeviceStatus] {
        await ProductionRunSmartServices().deviceStatuses()
    }

    func connect(provider: String) async -> ConnectedDeviceStatus {
        await ProductionRunSmartServices().connect(provider: provider)
    }

    func syncNow(provider: String) async -> ConnectedDeviceStatus {
        await ProductionRunSmartServices().syncNow(provider: provider)
    }

    func disconnect(provider: String) async -> ConnectedDeviceStatus {
        await ProductionRunSmartServices().disconnect(provider: provider)
    }

    func requestHealthAccess() async -> ConnectedDeviceStatus {
        await ProductionRunSmartServices().requestHealthAccess()
    }

    func syncHealthData() async -> ConnectedDeviceStatus {
        await ProductionRunSmartServices().syncHealthData()
    }

    func saveToHealth(_ run: RecordedRun) async {
        await ProductionRunSmartServices().saveToHealth(run)
    }
}
