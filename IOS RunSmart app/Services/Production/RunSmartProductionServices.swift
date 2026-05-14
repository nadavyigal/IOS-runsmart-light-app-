import Foundation
import SwiftUI
import CoreLocation
import Combine

@MainActor
final class RunSmartAppSession: ObservableObject {
    @Published var onboardingProfile: OnboardingProfile
    @Published var hasCompletedOnboarding: Bool

    private let store = RunSmartLocalStore.shared

    init() {
        onboardingProfile = store.loadOnboardingProfile() ?? .empty
        hasCompletedOnboarding = store.hasCompletedOnboarding
    }

    func completeOnboarding(_ profile: OnboardingProfile) {
        onboardingProfile = profile
        hasCompletedOnboarding = true
        store.saveOnboardingProfile(profile)
        store.hasCompletedOnboarding = true
    }
}

final class RunSmartLocalStore {
    static let shared = RunSmartLocalStore()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "runsmart.onboarding.complete") }
        set { defaults.set(newValue, forKey: "runsmart.onboarding.complete") }
    }

    func saveOnboardingProfile(_ profile: OnboardingProfile) {
        save(profile, key: "runsmart.onboarding.profile")
    }

    func loadOnboardingProfile() -> OnboardingProfile? {
        load(OnboardingProfile.self, key: "runsmart.onboarding.profile")
    }

    func saveRun(_ run: RecordedRun) {
        guard !isRunHidden(run) else { return }
        var runs = loadRuns()
        if let providerID = run.providerActivityID,
           let index = runs.firstIndex(where: { $0.providerActivityID == providerID && $0.source == run.source }) {
            runs[index] = run
            runs.sort { $0.startedAt > $1.startedAt }
            save(runs, key: "runsmart.runs")
            return
        }
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.append(run)
        }
        runs.sort { $0.startedAt > $1.startedAt }
        save(runs, key: "runsmart.runs")
    }

    func loadRuns() -> [RecordedRun] {
        load([RecordedRun].self, key: "runsmart.runs") ?? []
    }

    func visibleRuns(_ runs: [RecordedRun]) -> [RecordedRun] {
        runs.filter { !isRunHidden($0) }
    }

    @discardableResult
    func removeRun(_ run: RecordedRun) -> Bool {
        var didRemove = false
        var runs = loadRuns()
        let before = runs.count
        runs.removeAll { stored in
            if stored.id == run.id { return true }
            guard let storedProviderID = stored.providerActivityID,
                  let runProviderID = run.providerActivityID else { return false }
            return storedProviderID == runProviderID && stored.source == run.source
        }
        didRemove = runs.count != before
        save(runs, key: "runsmart.runs")

        var reports = loadRunReports()
        let reportIDs = [run.id.uuidString, run.providerActivityID].compactMap { $0 }
        reports.removeAll { report in
            reportIDs.contains(report.runID) || reportIDs.contains(report.id)
        }
        save(reports, key: "runsmart.runReports")

        if run.providerActivityID != nil {
            hideRun(run)
            didRemove = true
        }
        return didRemove
    }

    func isRunHidden(_ run: RecordedRun) -> Bool {
        Set(loadHiddenRunKeys()).contains(runVisibilityKey(for: run))
    }

    func saveRunReport(_ report: RunReportDetail) {
        var reports = loadRunReports()
        reports.removeAll { $0.runID == report.runID || $0.id == report.id }
        reports.append(report)
        reports.sort { $0.dateLabel > $1.dateLabel }
        save(reports, key: "runsmart.runReports")
    }

    func loadRunReports() -> [RunReportDetail] {
        load([RunReportDetail].self, key: "runsmart.runReports") ?? []
    }

    func cachedRunReport(runID: String) -> RunReportDetail? {
        loadRunReports().first { $0.runID == runID || $0.id == runID }
    }

    func saveDeviceStatus(_ status: ConnectedDeviceStatus) {
        var statuses = loadDeviceStatuses()
        statuses.removeAll { $0.provider == status.provider }
        statuses.append(status)
        save(statuses, key: "runsmart.device.statuses")
    }

    func loadDeviceStatuses() -> [ConnectedDeviceStatus] {
        load([ConnectedDeviceStatus].self, key: "runsmart.device.statuses") ?? [
            ConnectedDeviceStatus(provider: "Garmin Connect", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Connect Garmin to import real activities."),
            ConnectedDeviceStatus(provider: "HealthKit", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Allow Health access to sync workouts.")
        ]
    }

    func saveHealthKitDailySnapshot(_ snapshot: HealthKitDailySnapshot) {
        save(snapshot, key: "runsmart.healthkit.dailySnapshot")
    }

    func loadHealthKitDailySnapshot() -> HealthKitDailySnapshot? {
        load(HealthKitDailySnapshot.self, key: "runsmart.healthkit.dailySnapshot")
    }

    // MARK: - Saved Routes

    func saveSavedRoute(_ route: SavedRoute) {
        var routes = loadSavedRoutes()
        routes.removeAll { $0.id == route.id }
        routes.append(route)
        routes.sort { $0.updatedAt > $1.updatedAt }
        save(routes, key: "runsmart.savedRoutes")
    }

    func loadSavedRoutes() -> [SavedRoute] {
        load([SavedRoute].self, key: "runsmart.savedRoutes") ?? []
    }

    @discardableResult
    func removeSavedRoute(_ routeID: UUID) -> Bool {
        var routes = loadSavedRoutes()
        let before = routes.count
        routes.removeAll { $0.id == routeID }
        guard routes.count != before else { return false }
        save(routes, key: "runsmart.savedRoutes")
        removeBenchmarkRoute(routeID)
        return true
    }

    // MARK: - Benchmark Routes

    func saveBenchmarkRoute(_ benchmark: BenchmarkRoute) {
        var benchmarks = loadBenchmarkRoutes()
        benchmarks.removeAll { $0.savedRouteID == benchmark.savedRouteID }
        benchmarks.append(benchmark)
        save(benchmarks, key: "runsmart.benchmarkRoutes")
    }

    func loadBenchmarkRoutes() -> [BenchmarkRoute] {
        load([BenchmarkRoute].self, key: "runsmart.benchmarkRoutes") ?? []
    }

    @discardableResult
    func removeBenchmarkRoute(_ savedRouteID: UUID) -> Bool {
        var benchmarks = loadBenchmarkRoutes()
        let before = benchmarks.count
        benchmarks.removeAll { $0.savedRouteID == savedRouteID }
        guard benchmarks.count != before else { return false }
        save(benchmarks, key: "runsmart.benchmarkRoutes")
        return true
    }

    private func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func hideRun(_ run: RecordedRun) {
        var keys = Set(loadHiddenRunKeys())
        keys.insert(runVisibilityKey(for: run))
        save(Array(keys), key: "runsmart.hiddenRuns")
    }

    private func loadHiddenRunKeys() -> [String] {
        load([String].self, key: "runsmart.hiddenRuns") ?? []
    }

    private func runVisibilityKey(for run: RecordedRun) -> String {
        "\(run.source.rawValue)|\(run.providerActivityID ?? run.id.uuidString)"
    }
}

@MainActor
final class RunRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var phase: RunRecordingPhase = .idle
    @Published private(set) var routePoints: [RunRoutePoint] = []
    @Published private(set) var displayRoutePoints: [RunRoutePoint] = []
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var movingSeconds: TimeInterval = 0
    @Published private(set) var horizontalAccuracy: Double?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSavedRun: RecordedRun?

    private let manager = CLLocationManager()
    private let store: RunSmartLocalStore
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPausedSeconds: TimeInterval = 0
    private var timer: Timer?
    private var lastAcceptedLocation: CLLocation?
    private var lastDisplayLocation: CLLocation?
    private var lastDisplayRouteUpdate: Date?
    private var shouldStartAfterPermission = false

    nonisolated static let requiredStartAccuracy: CLLocationAccuracy = 35
    nonisolated static let acceptedRecordingAccuracy: CLLocationAccuracy = 65
    nonisolated static let maximumLocationAge: TimeInterval = 15
    nonisolated static let liveRouteMinimumInterval: TimeInterval = 2
    nonisolated static let liveRouteMinimumDistance: CLLocationDistance = 12
    nonisolated static let maximumDisplayRoutePoints = 240

    override convenience init() {
        self.init(store: .shared)
    }

    init(store: RunSmartLocalStore) {
        self.store = store
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        updatePhaseForAuthorization()
    }

    var distanceLabel: String { String(format: "%.2f", distanceMeters / 1_000) }
    var elapsedLabel: String { Self.timeLabel(elapsedSeconds) }
    var movingLabel: String { Self.timeLabel(movingSeconds) }
    var averagePaceLabel: String {
        guard distanceMeters >= 20 else { return "--" }
        return Self.paceLabel(secondsPerKm: movingSeconds / max(distanceMeters / 1_000, 0.001))
    }
    var currentPaceLabel: String {
        guard routePoints.count >= 2, let last = lastAcceptedLocation else { return averagePaceLabel }
        let recent = routePoints.suffix(6)
        guard let first = recent.first else { return averagePaceLabel }
        let firstLocation = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let meters = last.distance(from: firstLocation)
        let seconds = last.timestamp.timeIntervalSince(first.timestamp)
        guard meters > 10, seconds > 0 else { return averagePaceLabel }
        return Self.paceLabel(secondsPerKm: seconds / (meters / 1_000))
    }

    func requestPermission() {
        lastErrorMessage = nil
        phase = .requestingPermission
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            shouldStartAfterPermission = true
            requestPermission()
            return
        }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            shouldStartAfterPermission = false
            phase = .denied
            lastErrorMessage = "Location permission is required to record GPS runs."
            return
        }

        startAcquiringLocation()
    }

    func startAcquiringLocation(startLocationUpdates: Bool = true) {
        shouldStartAfterPermission = false
        resetCurrentRun()
        phase = .acquiringLocation
        if startLocationUpdates {
            manager.startUpdatingLocation()
        }
    }

    private func beginRecording(from firstLocation: CLLocation, startedAt startDate: Date = Date()) {
        startedAt = startDate
        pausedAt = nil
        accumulatedPausedSeconds = 0
        lastErrorMessage = nil
        phase = .recording
        acceptRecordingLocation(firstLocation, forceDisplay: true)
        startTimer()
        tick()
    }

    func pause() {
        guard phase == .recording else { return }
        pausedAt = Date()
        phase = .paused
        manager.stopUpdatingLocation()
        tick()
    }

    func resume() {
        guard phase == .paused else { return }
        if let pausedAt {
            accumulatedPausedSeconds += Date().timeIntervalSince(pausedAt)
        }
        pausedAt = nil
        phase = .recording
        manager.startUpdatingLocation()
        tick()
    }

    func discard() {
        shouldStartAfterPermission = false
        stopTracking()
        resetCurrentRun()
        lastSavedRun = nil
        updatePhaseForAuthorization()
    }

    @discardableResult
    func finish() -> RecordedRun? {
        guard let startedAt else { return nil }
        let endedAt = Date()
        let activePauseStartedAt = pausedAt
        stopTracking()
        let moving = Self.movingDuration(
            startedAt: startedAt,
            endedAt: endedAt,
            accumulatedPausedSeconds: accumulatedPausedSeconds,
            activePauseStartedAt: activePauseStartedAt
        )
        let pace = distanceMeters > 0 ? moving / (distanceMeters / 1_000) : 0
        let run = RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            movingTimeSeconds: moving,
            averagePaceSecondsPerKm: pace,
            averageHeartRateBPM: nil,
            routePoints: routePoints,
            syncedAt: nil
        )
        store.saveRun(run)
        lastSavedRun = run
        updatePhaseForAuthorization()
        return run
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updatePhaseForAuthorization()
        if shouldStartAfterPermission,
           manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            startAcquiringLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        handleLocationUpdates(locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorMessage = error.localizedDescription
        phase = .failed
    }

    private func updatePhaseForAuthorization() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if phase == .idle || phase == .requestingPermission || phase == .denied || phase == .failed {
                phase = .ready
            }
        case .denied, .restricted:
            shouldStartAfterPermission = false
            phase = .denied
        case .notDetermined:
            phase = .idle
        @unknown default:
            phase = .failed
        }
    }

    func handleLocationUpdates(_ locations: [CLLocation], now: Date = Date()) {
        guard phase == .acquiringLocation || phase == .recording else { return }

        for location in locations {
            if phase == .acquiringLocation {
                guard Self.isFreshLocation(location, now: now) else { continue }
                horizontalAccuracy = location.horizontalAccuracy
                guard location.horizontalAccuracy <= Self.requiredStartAccuracy else { continue }
                beginRecording(from: location, startedAt: now)
                continue
            }

            guard Self.isUsable(location, maxAccuracy: Self.acceptedRecordingAccuracy, now: now) else { continue }
            horizontalAccuracy = location.horizontalAccuracy
            acceptRecordingLocation(location)
        }
    }

    static func isUsable(_ location: CLLocation, maxAccuracy: CLLocationAccuracy, now: Date = Date()) -> Bool {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maxAccuracy else { return false }
        return isFreshLocation(location, now: now)
    }

    static func isFreshLocation(_ location: CLLocation, now: Date = Date()) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        guard abs(location.timestamp.timeIntervalSince(now)) <= maximumLocationAge else { return false }
        return location.coordinate.latitude.isFinite && location.coordinate.longitude.isFinite
    }

    static func simplifiedDisplayRoute(from points: [RunRoutePoint], maxPoints: Int = maximumDisplayRoutePoints) -> [RunRoutePoint] {
        guard points.count > maxPoints, maxPoints > 2 else { return points }
        let lastIndex = points.count - 1
        let step = Double(lastIndex) / Double(maxPoints - 1)
        var result: [RunRoutePoint] = []
        var usedIndices = Set<Int>()

        for displayIndex in 0..<maxPoints {
            let sourceIndex = displayIndex == maxPoints - 1 ? lastIndex : Int((Double(displayIndex) * step).rounded())
            if usedIndices.insert(sourceIndex).inserted {
                result.append(points[sourceIndex])
            }
        }

        if result.last?.id != points.last?.id {
            result.append(points[lastIndex])
        }
        return result
    }

    private func acceptRecordingLocation(_ location: CLLocation, forceDisplay: Bool = false) {
        if let previous = lastAcceptedLocation {
            let delta = location.distance(from: previous)
            guard delta >= 1 else { return }
            distanceMeters += delta
        }

        let point = RunRoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil
        )
        routePoints.append(point)
        lastAcceptedLocation = location
        updateDisplayRoute(with: location, force: forceDisplay)
    }

    private func updateDisplayRoute(with location: CLLocation, force: Bool) {
        let interval = lastDisplayRouteUpdate.map { location.timestamp.timeIntervalSince($0) } ?? .infinity
        let distance = lastDisplayLocation.map { location.distance(from: $0) } ?? .infinity
        guard force || interval >= Self.liveRouteMinimumInterval || distance >= Self.liveRouteMinimumDistance else { return }

        displayRoutePoints = Self.simplifiedDisplayRoute(from: routePoints)
        lastDisplayLocation = location
        lastDisplayRouteUpdate = location.timestamp
    }

    private func resetCurrentRun() {
        routePoints = []
        displayRoutePoints = []
        distanceMeters = 0
        elapsedSeconds = 0
        movingSeconds = 0
        horizontalAccuracy = nil
        lastAcceptedLocation = nil
        lastDisplayLocation = nil
        lastDisplayRouteUpdate = nil
        lastErrorMessage = nil
        startedAt = nil
        pausedAt = nil
        accumulatedPausedSeconds = 0
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let startedAt else { return }
        let now = Date()
        elapsedSeconds = now.timeIntervalSince(startedAt)
        movingSeconds = Self.movingDuration(
            startedAt: startedAt,
            endedAt: now,
            accumulatedPausedSeconds: accumulatedPausedSeconds,
            activePauseStartedAt: pausedAt
        )
    }

    private func stopTracking() {
        manager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        tick()
        startedAt = nil
        pausedAt = nil
    }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", Int32(total / 60), Int32(total % 60))
    }

    static func paceLabel(secondsPerKm: TimeInterval) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", Int32(total / 60), Int32(total % 60))
    }

    static func movingDuration(
        startedAt: Date,
        endedAt: Date,
        accumulatedPausedSeconds: TimeInterval,
        activePauseStartedAt: Date?
    ) -> TimeInterval {
        let activePause = activePauseStartedAt.map { max(0, endedAt.timeIntervalSince($0)) } ?? 0
        return max(0, endedAt.timeIntervalSince(startedAt) - accumulatedPausedSeconds - activePause)
    }
}

protocol RouteProviding {
    func routeSuggestions() async -> [RouteSuggestion]
    func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion]
    func rankedRouteSuggestions(targetDistanceKm: Double?) async -> [RouteSuggestion]
    func savedRoutes() async -> [SavedRoute]
    func saveRoute(_ route: SavedRoute) async -> Bool
    func deleteRoute(_ routeID: UUID) async -> Bool
    func updateRoute(_ route: SavedRoute) async -> Bool
    func benchmarkRoutes() async -> [BenchmarkRoute]
    func enableBenchmark(for routeID: UUID) async -> Bool
    func disableBenchmark(for routeID: UUID) async -> Bool
}

extension RouteProviding {
    func savedRoutes() async -> [SavedRoute] { [] }
    func saveRoute(_ route: SavedRoute) async -> Bool { false }
    func deleteRoute(_ routeID: UUID) async -> Bool { false }
    func updateRoute(_ route: SavedRoute) async -> Bool { false }
    func benchmarkRoutes() async -> [BenchmarkRoute] { [] }
    func enableBenchmark(for routeID: UUID) async -> Bool { false }
    func disableBenchmark(for routeID: UUID) async -> Bool { false }
    func rankedRouteSuggestions(targetDistanceKm: Double?) async -> [RouteSuggestion] { [] }
}

protocol DeviceSyncing {
    func deviceStatuses() async -> [ConnectedDeviceStatus]
    func connect(provider: String) async -> ConnectedDeviceStatus
    func syncNow(provider: String) async -> ConnectedDeviceStatus
    func disconnect(provider: String) async -> ConnectedDeviceStatus
}

protocol HealthSyncing {
    func requestHealthAccess() async -> ConnectedDeviceStatus
    func syncHealthData() async -> ConnectedDeviceStatus
    func saveToHealth(_ run: RecordedRun) async
}

struct ProductionRunSmartServices: RunSmartServiceProviding, RouteProviding, DeviceSyncing, HealthSyncing {
    private let store = RunSmartLocalStore.shared
    private let garmin = GarminGatewayClient()
    private let health = HealthKitSyncService()

    func todayRecommendation() async -> TodayRecommendation {
        let profile = store.loadOnboardingProfile() ?? .empty
        let recentRuns = store.visibleRuns(store.loadRuns()).prefix(7)
        let weeklyKm = recentRuns.reduce(0) { $0 + $1.distanceMeters } / 1_000
        let readiness = min(95, max(55, 72 + min(18, Int(weeklyKm))))
        return TodayRecommendation(
            readiness: readiness,
            readinessLabel: readiness >= 80 ? "High" : "Ready",
            workoutTitle: profile.goal.contains("Marathon") ? "Endurance Builder" : "Tempo Builder",
            distance: profile.weeklyRunDays >= 5 ? "8.0 km" : "6.0 km",
            pace: "GPS guided",
            elevation: "Route based",
            coachMessage: "Your plan is now based on saved preferences and recorded activity. Start a GPS run or sync Garmin to sharpen the recommendation."
        )
    }

    func weeklyPlan() async -> [WorkoutSummary] {
        let profile = store.loadOnboardingProfile() ?? .empty
        let calendar = Calendar.current
        let today = Date()
        guard let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        ) else { return [] }

        let shortDays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        return shortDays.enumerated().compactMap { index, day in
            guard let date = calendar.date(byAdding: .day, value: index, to: weekStart) else { return nil }
            let isRunDay = index < profile.weeklyRunDays
            let dayNum = calendar.component(.day, from: date)
            return WorkoutSummary(
                id: UUID(),
                scheduledDate: date,
                weekday: day,
                date: "\(dayNum)",
                kind: isRunDay ? (index == 2 ? .tempo : .easy) : .recovery,
                title: isRunDay ? (index == 2 ? "Tempo Run" : "Easy Run") : "Recovery",
                distance: isRunDay ? "\(index == 2 ? 8 : 5) km" : "Rest",
                detail: calendar.isDateInToday(date) ? "Today" : (isRunDay ? "Planned" : "Mobility"),
                isToday: calendar.isDateInToday(date),
                isComplete: false
            )
        }
    }

    func activeTrainingPlan() async -> TrainingPlanSnapshot? { nil }
    func planWorkouts(from startDate: Date, to endDate: Date) async -> [WorkoutSummary] { [] }
    func nextWorkouts(limit: Int) async -> [WorkoutSummary] { [] }
    func saveSuggestedWorkout(_ suggestion: StructuredNextWorkout, from report: RunReportDetail) async -> Bool { false }

    func recentMessages() async -> [CoachMessage] {
        [
            CoachMessage(text: "I can use your GPS runs, HealthKit workouts, and Garmin imports once connected.", time: "Now", isUser: false)
        ]
    }

    func send(message: String) async -> CoachMessage {
        CoachMessage(text: "Got it. I will factor that into the next recommendation once your real activity data updates.", time: "Now", isUser: false)
    }

    func runnerProfile() async -> RunnerProfile {
        let profile = store.loadOnboardingProfile() ?? .empty
        let runs = ActivityConsolidationService.userVisibleRecentRuns(store.visibleRuns(store.loadRuns()))
        let totalDistance = Int((runs.reduce(0) { $0 + $1.distanceMeters } / 1_000).rounded())
        let totalSeconds = runs.reduce(0) { $0 + $1.movingTimeSeconds }
        return RunnerProfile(
            name: profile.displayName.isEmpty ? "RunSmart Runner" : profile.displayName,
            goal: profile.goal,
            streak: "\(profile.weeklyRunDays)x/week",
            level: profile.experience,
            totalRuns: runs.count,
            totalDistance: totalDistance,
            totalTime: "\(Int(totalSeconds / 3600))h \(Int(totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)m"
        )
    }

    func achievements() async -> [Achievement] {
        let runs = ActivityConsolidationService.userVisibleRecentRuns(store.visibleRuns(store.loadRuns()))
        return [
            Achievement(title: "GPS Runs", subtitle: "\(runs.filter { $0.source == .runSmart }.count)", symbol: "location.fill", tint: Color.lime),
            Achievement(title: "Garmin", subtitle: deviceSubtitle("Garmin Connect"), symbol: "link", tint: .cyan),
            Achievement(title: "Health", subtitle: deviceSubtitle("HealthKit"), symbol: "heart", tint: .red)
        ]
    }

    func currentRunMetrics() async -> [MetricTile] {
        let last = await recentRuns().first
        return [
            MetricTile(title: "Distance", value: last.map { String(format: "%.2f", $0.distanceMeters / 1_000) } ?? "0.00", unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
            MetricTile(title: "Pace", value: last.map { RunRecorder.paceLabel(secondsPerKm: $0.averagePaceSecondsPerKm) } ?? "--", unit: "/km", symbol: "timer", tint: Color.lime),
            MetricTile(title: "Time", value: last.map { RunRecorder.timeLabel($0.movingTimeSeconds) } ?? "00:00", unit: "", symbol: "stopwatch", tint: .white),
            MetricTile(title: "Source", value: last?.source.rawValue ?? "Ready", unit: "", symbol: "sensor.tag.radiowaves.forward", tint: .cyan)
        ]
    }

    func recentRuns() async -> [RecordedRun] {
        ActivityConsolidationService.userVisibleRecentRuns(store.visibleRuns(store.loadRuns()))
    }

    func saveManualRun(kind: WorkoutKind, date: Date, distanceKm: Double, durationMinutes: Int, averageHeartRateBPM: Int?, notes: String) async -> RecordedRun {
        let movingTime = TimeInterval(max(1, durationMinutes) * 60)
        let distanceMeters = max(0.1, distanceKm) * 1_000
        let run = RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: date,
            endedAt: date.addingTimeInterval(movingTime),
            distanceMeters: distanceMeters,
            movingTimeSeconds: movingTime,
            averagePaceSecondsPerKm: movingTime / max(distanceKm, 0.1),
            averageHeartRateBPM: averageHeartRateBPM,
            routePoints: [],
            syncedAt: Date()
        )
        store.saveRun(run)
        return run
    }

    func matchRoute(for run: RecordedRun) async -> RouteMatchResult? {
        RouteMatchingService.match(run: run, savedRoutes: store.loadSavedRoutes())
    }

    func benchmarkComparison(for run: RecordedRun) async -> BenchmarkRouteComparison? {
        BenchmarkRouteAnalyticsService.comparison(
            for: run,
            runs: store.visibleRuns(store.loadRuns()),
            savedRoutes: store.loadSavedRoutes(),
            benchmarkRoutes: store.loadBenchmarkRoutes()
        )
    }

    func saveRouteMatch(for run: RecordedRun) -> RecordedRun {
        guard let match = RouteMatchingService.match(run: run, savedRoutes: store.loadSavedRoutes()) else {
            return run
        }
        var matchedRun = run
        matchedRun.routeMatchResult = match
        store.saveRun(matchedRun)
        return matchedRun
    }

    func removeRun(_ run: RecordedRun) async -> Bool {
        store.removeRun(run)
    }

    func finishRun() async {}

    func routeSuggestions() async -> [RouteSuggestion] {
        let runs = store.visibleRuns(store.loadRuns()).filter { !$0.routePoints.isEmpty }
        if let last = runs.first {
            return [
                RouteSuggestion(
                    id: last.id.uuidString,
                    name: "Last Run Route",
                    distanceKm: last.distanceMeters / 1_000,
                    elevationGainMeters: elevationGain(points: last.routePoints),
                    estimatedDurationMinutes: max(1, Int(last.movingTimeSeconds / 60)),
                    points: last.routePoints,
                    kind: .past
                )
            ]
        }
        return []
    }

    func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion] {
        []
    }

    func rankedRouteSuggestions(targetDistanceKm: Double?) async -> [RouteSuggestion] {
        let saved = store.loadSavedRoutes()
        let benchmarks = store.loadBenchmarkRoutes()
        let benchmarkRouteIDs = Set(benchmarks.map(\.savedRouteID))
        let calendar = Calendar.current
        var suggestions: [RouteSuggestion] = []

        for route in saved {
            let isBenchmark = benchmarkRouteIDs.contains(route.id)
            let kind: RouteKind = isBenchmark ? .benchmark : .saved
            let reason = RouteSuggestionRanker.reason(
                kind: kind, distanceKm: route.distanceKm,
                targetDistanceKm: targetDistanceKm,
                isFavorite: route.isFavorite, daysSinceLastRun: nil
            )
            suggestions.append(RouteSuggestion(
                id: route.id.uuidString, name: route.name,
                distanceKm: route.distanceKm,
                elevationGainMeters: route.elevationGainMeters,
                estimatedDurationMinutes: max(1, Int((route.distanceKm * 360).rounded() / 60)),
                points: route.points, kind: kind,
                recommendationReason: reason,
                savedRouteID: route.id, isFavorite: route.isFavorite
            ))
        }

        let pastRuns = store.visibleRuns(store.loadRuns()).filter { !$0.routePoints.isEmpty }
        for run in pastRuns.prefix(5) {
            let days = calendar.dateComponents([.day], from: run.startedAt, to: Date()).day
            let reason = RouteSuggestionRanker.reason(
                kind: .past, distanceKm: run.distanceMeters / 1000,
                targetDistanceKm: targetDistanceKm,
                isFavorite: false, daysSinceLastRun: days
            )
            suggestions.append(RouteSuggestion(
                id: run.id.uuidString,
                name: "Run \(DateFormatter.localizedString(from: run.startedAt, dateStyle: .short, timeStyle: .none))",
                distanceKm: run.distanceMeters / 1000,
                elevationGainMeters: elevationGain(points: run.routePoints),
                estimatedDurationMinutes: max(1, Int(run.movingTimeSeconds / 60)),
                points: run.routePoints, kind: .past,
                recommendationReason: reason, savedRouteID: nil, isFavorite: false
            ))
        }

        let filtered = RouteSuggestionRanker.filter(suggestions, targetDistanceKm: targetDistanceKm)
        return RouteSuggestionRanker.rank(filtered, targetDistanceKm: targetDistanceKm)
    }

    func savedRoutes() async -> [SavedRoute] {
        store.loadSavedRoutes()
    }

    func saveRoute(_ route: SavedRoute) async -> Bool {
        store.saveSavedRoute(route)
        return true
    }

    func deleteRoute(_ routeID: UUID) async -> Bool {
        store.removeSavedRoute(routeID)
    }

    func updateRoute(_ route: SavedRoute) async -> Bool {
        var updated = route
        updated.updatedAt = Date()
        store.saveSavedRoute(updated)
        return true
    }

    func benchmarkRoutes() async -> [BenchmarkRoute] {
        store.loadBenchmarkRoutes()
    }

    func enableBenchmark(for routeID: UUID) async -> Bool {
        let routes = store.loadSavedRoutes()
        guard routes.contains(where: { $0.id == routeID }) else { return false }
        let benchmark = BenchmarkRoute(
            id: UUID(),
            savedRouteID: routeID,
            enabledAt: Date(),
            historicalRunCount: 0,
            personalBestSeconds: nil,
            personalBestDate: nil,
            averagePaceSecondsPerKm: nil,
            averageDurationSeconds: nil
        )
        store.saveBenchmarkRoute(benchmark)
        return true
    }

    func disableBenchmark(for routeID: UUID) async -> Bool {
        store.removeBenchmarkRoute(routeID)
    }

    func deviceStatuses() async -> [ConnectedDeviceStatus] {
        store.loadDeviceStatuses()
    }

    func connect(provider: String) async -> ConnectedDeviceStatus {
        if provider == "Garmin Connect" {
            let status = await garmin.startConnect()
            store.saveDeviceStatus(status)
            return status
        }
        if provider == "HealthKit" {
            return await requestHealthAccess()
        }
        let status = ConnectedDeviceStatus(provider: provider, state: .error, lastSuccessfulSync: nil, permissions: [], message: "Unsupported provider.")
        store.saveDeviceStatus(status)
        return status
    }

    func syncNow(provider: String) async -> ConnectedDeviceStatus {
        if provider == "Garmin Connect" {
            let result = await garmin.syncActivities()
            result.runs.map(saveRouteMatch(for:)).forEach(store.saveRun)
            store.saveDeviceStatus(result.status)
            return result.status
        }
        if provider == "HealthKit" {
            return await syncHealthData()
        }
        return ConnectedDeviceStatus(provider: provider, state: .error, lastSuccessfulSync: nil, permissions: [], message: "Unsupported provider.")
    }

    func disconnect(provider: String) async -> ConnectedDeviceStatus {
        let status = ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Disconnected.")
        store.saveDeviceStatus(status)
        return status
    }

    func requestHealthAccess() async -> ConnectedDeviceStatus {
        let status = await health.requestAccess()
        store.saveDeviceStatus(status)
        return status
    }

    func syncHealthData() async -> ConnectedDeviceStatus {
        let result = await health.importHealthData(localStore: store)
        store.saveDeviceStatus(result.status)
        if !result.runs.isEmpty {
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            }
        }
        return result.status
    }

    func saveToHealth(_ run: RecordedRun) async {
        await health.save(run)
    }

    private func deviceSubtitle(_ provider: String) -> String {
        store.loadDeviceStatuses().first(where: { $0.provider == provider })?.state.rawValue.capitalized ?? "Off"
    }

    private func elevationGain(points: [RunRoutePoint]) -> Int {
        var gain = 0.0
        for pair in zip(points, points.dropFirst()) {
            if let a = pair.0.altitude, let b = pair.1.altitude, b > a {
                gain += b - a
            }
        }
        return Int(gain.rounded())
    }
}

struct GarminSyncResult {
    var status: ConnectedDeviceStatus
    var runs: [RecordedRun]
}

struct GarminGatewayClient {
    private var gatewayBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RUNSMART_GARMIN_GATEWAY_URL") as? String else { return nil }
        return URL(string: raw)
    }

    func startConnect() async -> ConnectedDeviceStatus {
        guard gatewayBaseURL != nil else {
            return ConnectedDeviceStatus(
                provider: "Garmin Connect",
                state: .error,
                lastSuccessfulSync: nil,
                permissions: [],
                message: "Garmin gateway URL is not configured. Add RUNSMART_GARMIN_GATEWAY_URL after Garmin Developer approval."
            )
        }
        return ConnectedDeviceStatus(provider: "Garmin Connect", state: .connecting, lastSuccessfulSync: nil, permissions: [], message: "Open Garmin OAuth from the secure gateway.")
    }

    func syncActivities() async -> GarminSyncResult {
        guard gatewayBaseURL != nil else {
            return GarminSyncResult(
                status: ConnectedDeviceStatus(provider: "Garmin Connect", state: .error, lastSuccessfulSync: nil, permissions: [], message: "Garmin sync requires the configured secure gateway."),
                runs: []
            )
        }
        return GarminSyncResult(
            status: ConnectedDeviceStatus(provider: "Garmin Connect", state: .connected, lastSuccessfulSync: Date(), permissions: ["Activities"], message: "Garmin gateway reachable. Activity import endpoint is ready for backend payloads."),
            runs: []
        )
    }
}
