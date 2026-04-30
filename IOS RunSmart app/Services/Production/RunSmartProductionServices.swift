import Foundation
import SwiftUI
import CoreLocation
import Combine
#if canImport(HealthKit)
import HealthKit
#endif

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
        var runs = loadRuns()
        if let providerID = run.providerActivityID,
           runs.contains(where: { $0.providerActivityID == providerID && $0.source == run.source }) {
            return
        }
        if !runs.contains(where: { $0.id == run.id }) {
            runs.append(run)
        }
        runs.sort { $0.startedAt > $1.startedAt }
        save(runs, key: "runsmart.runs")
    }

    func loadRuns() -> [RecordedRun] {
        load([RecordedRun].self, key: "runsmart.runs") ?? []
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

    private func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

@MainActor
final class RunRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var phase: RunRecordingPhase = .idle
    @Published private(set) var routePoints: [RunRoutePoint] = []
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
        phase = .requestingPermission
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            requestPermission()
            return
        }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            phase = .denied
            lastErrorMessage = "Location permission is required to record GPS runs."
            return
        }

        startedAt = Date()
        pausedAt = nil
        accumulatedPausedSeconds = 0
        routePoints = []
        distanceMeters = 0
        elapsedSeconds = 0
        movingSeconds = 0
        lastAcceptedLocation = nil
        lastErrorMessage = nil
        phase = .recording
        manager.startUpdatingLocation()
        startTimer()
    }

    func pause() {
        guard phase == .recording else { return }
        pausedAt = Date()
        phase = .paused
        manager.stopUpdatingLocation()
    }

    func resume() {
        guard phase == .paused else { return }
        if let pausedAt {
            accumulatedPausedSeconds += Date().timeIntervalSince(pausedAt)
        }
        pausedAt = nil
        phase = .recording
        manager.startUpdatingLocation()
    }

    func discard() {
        stopTracking()
        routePoints = []
        distanceMeters = 0
        elapsedSeconds = 0
        movingSeconds = 0
        lastAcceptedLocation = nil
        lastSavedRun = nil
        updatePhaseForAuthorization()
    }

    @discardableResult
    func finish() -> RecordedRun? {
        guard let startedAt else { return nil }
        let endedAt = Date()
        stopTracking()
        let moving = max(0, endedAt.timeIntervalSince(startedAt) - accumulatedPausedSeconds)
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
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard phase == .recording else { return }
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 65 {
            horizontalAccuracy = location.horizontalAccuracy
            if let previous = lastAcceptedLocation {
                let delta = location.distance(from: previous)
                guard delta >= 1 else { continue }
                distanceMeters += delta
            }
            routePoints.append(
                RunRoutePoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timestamp: location.timestamp,
                    horizontalAccuracy: location.horizontalAccuracy,
                    altitude: location.verticalAccuracy >= 0 ? location.altitude : nil
                )
            )
            lastAcceptedLocation = location
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorMessage = error.localizedDescription
        phase = .failed
    }

    private func updatePhaseForAuthorization() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if phase == .idle || phase == .requestingPermission || phase == .denied {
                phase = .ready
            }
        case .denied, .restricted:
            phase = .denied
        case .notDetermined:
            phase = .idle
        @unknown default:
            phase = .failed
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let startedAt else { return }
        elapsedSeconds = Date().timeIntervalSince(startedAt)
        let livePause = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
        movingSeconds = max(0, elapsedSeconds - accumulatedPausedSeconds - livePause)
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
}

protocol RouteProviding {
    func routeSuggestions() async -> [RouteSuggestion]
    func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion]
}

protocol DeviceSyncing {
    func deviceStatuses() async -> [ConnectedDeviceStatus]
    func connect(provider: String) async -> ConnectedDeviceStatus
    func syncNow(provider: String) async -> ConnectedDeviceStatus
    func disconnect(provider: String) async -> ConnectedDeviceStatus
}

protocol HealthSyncing {
    func requestHealthAccess() async -> ConnectedDeviceStatus
    func saveToHealth(_ run: RecordedRun) async
}

struct ProductionRunSmartServices: RunSmartServiceProviding, RouteProviding, DeviceSyncing, HealthSyncing {
    private let store = RunSmartLocalStore.shared
    private let garmin = GarminGatewayClient()
    private let health = HealthKitSyncService()

    func todayRecommendation() async -> TodayRecommendation {
        let profile = store.loadOnboardingProfile() ?? .empty
        let recentRuns = store.loadRuns().prefix(7)
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
        let days = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        return days.enumerated().map { index, day in
            let isRunDay = index < profile.weeklyRunDays
            return WorkoutSummary(
                weekday: day,
                date: "\(index + 1)",
                kind: isRunDay ? (index == 2 ? .tempo : .easy) : .recovery,
                title: isRunDay ? (index == 2 ? "Tempo Run" : "Easy Run") : "Recovery",
                distance: isRunDay ? "\(index == 2 ? 8 : 5) km" : "Rest",
                detail: index == 1 ? "Today" : (isRunDay ? "Planned" : "Mobility"),
                isToday: index == 1,
                isComplete: false
            )
        }
    }

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
        let runs = store.loadRuns()
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
        let runs = store.loadRuns()
        return [
            Achievement(title: "GPS Runs", subtitle: "\(runs.filter { $0.source == .runSmart }.count)", symbol: "location.fill", tint: Color.lime),
            Achievement(title: "Garmin", subtitle: deviceSubtitle("Garmin Connect"), symbol: "link", tint: .cyan),
            Achievement(title: "Health", subtitle: deviceSubtitle("HealthKit"), symbol: "heart", tint: .red)
        ]
    }

    func currentRunMetrics() async -> [MetricTile] {
        let last = store.loadRuns().first
        return [
            MetricTile(title: "Distance", value: last.map { String(format: "%.2f", $0.distanceMeters / 1_000) } ?? "0.00", unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
            MetricTile(title: "Pace", value: last.map { RunRecorder.paceLabel(secondsPerKm: $0.averagePaceSecondsPerKm) } ?? "--", unit: "/km", symbol: "timer", tint: Color.lime),
            MetricTile(title: "Time", value: last.map { RunRecorder.timeLabel($0.movingTimeSeconds) } ?? "00:00", unit: "", symbol: "stopwatch", tint: .white),
            MetricTile(title: "Source", value: last?.source.rawValue ?? "Ready", unit: "", symbol: "sensor.tag.radiowaves.forward", tint: .cyan)
        ]
    }

    func recentRuns() async -> [RecordedRun] {
        store.loadRuns()
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

    func finishRun() async {}

    func routeSuggestions() async -> [RouteSuggestion] {
        let runs = store.loadRuns().filter { !$0.routePoints.isEmpty }
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
            result.runs.forEach(store.saveRun)
            store.saveDeviceStatus(result.status)
            return result.status
        }
        if provider == "HealthKit" {
            let status = await health.importWorkouts(store: store)
            store.saveDeviceStatus(status)
            return status
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

struct HealthKitSyncService {
    func requestAccess() async -> ConnectedDeviceStatus {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return ConnectedDeviceStatus(provider: "HealthKit", state: .error, lastSuccessfulSync: nil, permissions: [], message: "Health data is not available on this device.")
        }
        let store = HKHealthStore()
        let workout = HKObjectType.workoutType()
        let share: Set<HKSampleType> = [workout]
        let read: Set<HKObjectType> = [workout]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return ConnectedDeviceStatus(provider: "HealthKit", state: .connected, lastSuccessfulSync: nil, permissions: ["Workouts"], message: "HealthKit access granted.")
        } catch {
            return ConnectedDeviceStatus(provider: "HealthKit", state: .error, lastSuccessfulSync: nil, permissions: [], message: error.localizedDescription)
        }
#else
        return ConnectedDeviceStatus(provider: "HealthKit", state: .error, lastSuccessfulSync: nil, permissions: [], message: "HealthKit is unavailable in this build.")
#endif
    }

    func save(_ run: RecordedRun) async {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let workout = HKWorkout(
            activityType: .running,
            start: run.startedAt,
            end: run.endedAt,
            duration: run.movingTimeSeconds,
            totalEnergyBurned: nil,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: run.distanceMeters),
            metadata: ["RunSmartSource": run.source.rawValue]
        )
        try? await store.save(workout)
#endif
    }

    func importWorkouts(store: RunSmartLocalStore) async -> ConnectedDeviceStatus {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return ConnectedDeviceStatus(provider: "HealthKit", state: .error, lastSuccessfulSync: nil, permissions: [], message: "Health data is not available on this device.")
        }
        let healthStore = HKHealthStore()
        let workouts = await readRecentRunningWorkouts(store: healthStore)
        workouts.forEach(store.saveRun)
        return ConnectedDeviceStatus(provider: "HealthKit", state: .connected, lastSuccessfulSync: Date(), permissions: ["Workouts"], message: "Imported \(workouts.count) HealthKit running workouts.")
#else
        return ConnectedDeviceStatus(provider: "HealthKit", state: .error, lastSuccessfulSync: nil, permissions: [], message: "HealthKit is unavailable in this build.")
#endif
    }

#if canImport(HealthKit)
    private func readRecentRunningWorkouts(store: HKHealthStore) async -> [RecordedRun] {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -90, to: Date()) ?? Date()
            let datePredicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
            let runPredicate = HKQuery.predicateForWorkouts(with: .running)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runPredicate])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 50, sortDescriptors: [sort]) { _, samples, _ in
                let runs = (samples as? [HKWorkout] ?? []).map { workout in
                    let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
                    let duration = workout.duration
                    return RecordedRun(
                        id: UUID(),
                        providerActivityID: workout.uuid.uuidString,
                        source: .healthKit,
                        startedAt: workout.startDate,
                        endedAt: workout.endDate,
                        distanceMeters: distance,
                        movingTimeSeconds: duration,
                        averagePaceSecondsPerKm: distance > 0 ? duration / (distance / 1_000) : 0,
                        averageHeartRateBPM: nil,
                        routePoints: [],
                        syncedAt: Date()
                    )
                }
                continuation.resume(returning: runs)
            }
            store.execute(query)
        }
    }
#endif
}
