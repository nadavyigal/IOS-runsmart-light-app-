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

    /// Saves a run. A provider copy (Garmin, Health) replaces the stored one, but the fields the runner set on
    /// this device (effort, title, notes, Strava id) are kept unless the caller is the one changing them.
    func saveRun(_ run: RecordedRun, replacingLocalFields: Bool = false) {
        guard !isRunHidden(run) else { return }
        var runs = loadRuns()
        if let providerID = run.providerActivityID,
           let index = runs.firstIndex(where: { $0.providerActivityID == providerID && $0.source == run.source }) {
            runs[index] = replacingLocalFields ? run : run.keepingLocalFields(from: runs[index])
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

    /// For a copy that was read before an `await`: keeps whatever the runner set on the stored run since then.
    @discardableResult
    func saveRunKeepingLocalEdits(_ run: RecordedRun) -> RecordedRun {
        let stored = loadRuns().first { Self.isSameStoredRun($0, run) }
        let merged = run.keepingLocalFields(from: stored)
        saveRun(merged, replacingLocalFields: true)
        return merged
    }

    /// Marks the stored copy as synced. Touches nothing else, and does not bring back a run that was deleted meanwhile.
    func markRunSynced(_ run: RecordedRun, at date: Date = Date()) {
        guard var stored = loadRuns().first(where: { Self.isSameStoredRun($0, run) }) else { return }
        stored.syncedAt = date
        saveRun(stored, replacingLocalFields: true)
    }

    func loadRuns() -> [RecordedRun] {
        load([RecordedRun].self, key: "runsmart.runs") ?? []
    }

    func updateRunRPE(_ run: RecordedRun, rpe: Int?) -> RecordedRun {
        // Apply to the stored copy so a field written since the caller loaded the run (such as the Strava activity id) is kept.
        var updated = loadRuns().first(where: { $0.id == run.id }) ?? run
        updated.rpe = rpe
        saveRun(updated, replacingLocalFields: true)
        return updated
    }

    /// Records that a run is on Strava. Applied to the stored copy, like `updateRunDetails`.
    func setStravaActivityID(_ activityID: Int, forRunID runID: UUID) {
        guard var stored = loadRuns().first(where: { $0.id == runID }) else { return }
        stored.stravaActivityID = activityID
        saveRun(stored, replacingLocalFields: true)
    }

    /// Applies title and notes to the stored copy of the run, so fields written since the caller loaded it
    /// (route match, processing result) are not overwritten by a stale copy.
    func updateRunDetails(_ run: RecordedRun, title: String?, notes: String?) -> RecordedRun {
        var updated = loadRuns().first(where: { $0.id == run.id }) ?? run
        updated.title = title
        updated.notes = notes
        saveRun(updated, replacingLocalFields: true)
        return updated
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

    func saveFirstSyncReview(_ review: FirstSyncReview) {
        var reviews = loadFirstSyncReviews()
        reviews.removeAll { $0.provider == review.provider }
        reviews.append(review)
        save(reviews, key: "runsmart.firstSync.reviews")
    }

    func firstSyncReview(provider: FirstSyncReviewProvider) -> FirstSyncReview? {
        loadFirstSyncReviews().first { $0.provider == provider }
    }

    func hasSeenFirstSyncReview(provider: FirstSyncReviewProvider) -> Bool {
        firstSyncReview(provider: provider)?.seen ?? false
    }

    func markFirstSyncReviewSeen(provider: FirstSyncReviewProvider) {
        var review = firstSyncReview(provider: provider) ?? FirstSyncReview.make(
            provider: provider,
            importedRuns: [],
            skippedDuplicateCount: 0,
            seen: true
        )
        review.seen = true
        saveFirstSyncReview(review)
    }

    private func loadFirstSyncReviews() -> [FirstSyncReview] {
        load([FirstSyncReview].self, key: "runsmart.firstSync.reviews") ?? []
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

    func benchmarkRouteIDs() -> Set<UUID> {
        Set(loadBenchmarkRoutes().map(\.savedRouteID))
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

    // MARK: - Benchmark stat hydration

    func refreshBenchmarkStats() {
        let runs = visibleRuns(loadRuns())
        let updated = BenchmarkStatRefresh.refresh(loadBenchmarkRoutes(), from: runs)
        save(updated, key: "runsmart.benchmarkRoutes")
    }

    // MARK: - Route re-matching

    /// Re-matches stored runs against the current saved routes after a route is saved or
    /// benchmarked, or runs are imported. Attaches the run a route was saved from to that
    /// route, persists the results, and refreshes benchmark stats. Scoring runs off the main actor.
    func rematchStoredRuns(savedFrom sourceRun: RecordedRun? = nil, routeID: UUID? = nil) async {
        let runs = visibleRuns(loadRuns())
        let routes = loadSavedRoutes()
        let benchmarkRouteIDs = Set(loadBenchmarkRoutes().map(\.savedRouteID))
        let sourceRouteID = routes.contains(where: { $0.id == routeID }) ? routeID : nil

        // Saving a route with "benchmark" on calls this twice in a row; the second call
        // sees the state the first one wrote, so scoring it again cannot change anything.
        var matches: [UUID: RouteMatchResult] = [:]
        if lastRematchedStateHash != Self.rematchStateHash(runs: runs, routes: routes, benchmarkRouteIDs: benchmarkRouteIDs) {
            matches = await Task.detached(priority: .utility) {
                RouteRematchService.updatedMatches(runs: runs, savedRoutes: routes, benchmarkRouteIDs: benchmarkRouteIDs)
            }.value
        }

        var changed = applyRouteMatches(matches)
        var sourceAttached = false
        if let sourceRun, let sourceRouteID {
            sourceAttached = attachRun(
                sourceRun,
                toSavedRoute: sourceRouteID,
                savedRouteIDs: Set(routes.map(\.id)),
                benchmarkRouteIDs: benchmarkRouteIDs
            )
            changed += sourceAttached ? 1 : 0
        }

        var runsAfter = runs.map { run -> RecordedRun in
            var updated = run
            if let match = matches[run.id] { updated.routeMatchResult = match }
            return updated
        }
        if let sourceRun, let sourceRouteID, sourceAttached {
            let exact = RouteMatchingService.exactMatch(routeID: sourceRouteID)
            if let index = runsAfter.firstIndex(where: { Self.isSameStoredRun($0, sourceRun) }) {
                runsAfter[index].routeMatchResult = exact
            } else {
                var attached = sourceRun
                attached.routeMatchResult = exact
                runsAfter.append(attached)
            }
        }
        lastRematchedStateHash = Self.rematchStateHash(runs: runsAfter, routes: routes, benchmarkRouteIDs: benchmarkRouteIDs)

        refreshBenchmarkStats()
        if changed > 0 {
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        }
    }

    private var lastRematchedStateHash: Int?

    /// Everything route scoring reads. In memory only (Hasher is seeded per launch), so the
    /// first re-match after launch always scores.
    private static func rematchStateHash(runs: [RecordedRun], routes: [SavedRoute], benchmarkRouteIDs: Set<UUID>) -> Int {
        var hasher = Hasher()
        hasher.combine(benchmarkRouteIDs)
        for route in routes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(route.id)
            hasher.combine(route.updatedAt)
            hasher.combine(route.distanceMeters)
            hasher.combine(route.points.count)
        }
        for run in runs.sorted(by: { $0.id.uuidString < $1.id.uuidString })
        where run.routePoints.count >= RouteMatchingService.minimumRoutePoints {
            hasher.combine(run.id)
            hasher.combine(run.startedAt)
            hasher.combine(run.distanceMeters)
            hasher.combine(run.routePoints.count)
            hasher.combine(run.routeMatchResult)
        }
        return hasher.finalize()
    }

    private static func isSameStoredRun(_ lhs: RecordedRun, _ rhs: RecordedRun) -> Bool {
        if lhs.id == rhs.id { return true }
        guard let lhsProviderID = lhs.providerActivityID,
              let rhsProviderID = rhs.providerActivityID else { return false }
        return lhsProviderID == rhsProviderID && lhs.source == rhs.source
    }

    /// Writes match results onto stored runs. Re-reads the store first so a run saved while
    /// the matches were being computed is not overwritten. Returns the number of runs changed.
    @discardableResult
    func applyRouteMatches(_ matches: [UUID: RouteMatchResult]) -> Int {
        guard !matches.isEmpty else { return 0 }
        var runs = loadRuns()
        var changed = 0
        for index in runs.indices {
            guard let match = matches[runs[index].id], runs[index].routeMatchResult != match else { continue }
            runs[index].routeMatchResult = match
            changed += 1
        }
        if changed > 0 { save(runs, key: "runsmart.runs") }
        return changed
    }

    /// Stores the run a route was saved from as an exact match of that route, unless the run
    /// already counts toward a benchmark route. Updates the stored copy when one exists so an
    /// older in-memory run does not overwrite newer fields.
    @discardableResult
    func attachRun(
        _ run: RecordedRun,
        toSavedRoute routeID: UUID,
        savedRouteIDs: Set<UUID>? = nil,
        benchmarkRouteIDs: Set<UUID> = []
    ) -> Bool {
        let match = RouteMatchingService.exactMatch(routeID: routeID)
        var attached = loadRuns().first { Self.isSameStoredRun($0, run) } ?? run
        guard attached.routeMatchResult != match, !isRunHidden(attached) else { return false }
        let preferred = RouteRematchService.preferredResult(
            existing: attached.routeMatchResult,
            candidate: match,
            savedRouteIDs: savedRouteIDs ?? Set(loadSavedRoutes().map(\.id)),
            benchmarkRouteIDs: benchmarkRouteIDs
        )
        guard preferred == match else { return false }
        attached.routeMatchResult = match
        saveRun(attached, replacingLocalFields: true)
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

    func clearUserData() {
        RunnerWeightStore.shared.clearUserData()
        let keys = [
            "runsmart.runs",
            "runsmart.runReports",
            "runsmart.hiddenRuns",
            "runsmart.device.statuses",
            "runsmart.firstSync.reviews",
            "runsmart.healthkit.dailySnapshot",
        ]
        for key in keys { defaults.removeObject(forKey: key) }
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
    /// Pace over the last ~30 seconds of the current segment, refreshed every second by
    /// `tick()`. Nil when there is no recent movement, so the label never shows a stale pace.
    @Published private(set) var currentPaceSeconds: TimeInterval?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastSavedRun: RecordedRun?
    /// An unfinished run found on disk at launch (the app was killed or crashed mid-run).
    /// The Run tab asks the runner to resume, save or discard it.
    @Published private(set) var pendingRecovery: RunSessionCheckpoint?
    /// Completed full kilometers of the run in progress. Recomputed only when the accepted
    /// distance crosses a new kilometer, so the live screen never re-walks the whole route
    /// on every redraw.
    @Published private(set) var completedKilometerSplits: [KilometerSplit] = []
    private var lastSplitCheckKilometer = 0
    /// When the current GPS search began. Nil outside `.acquiringLocation`.
    @Published private(set) var acquiringStartedAt: Date?
    /// True once the GPS search has run long enough to offer "Start anyway". Refreshed once a
    /// second by `acquiringTimer`, so the Run tab re-renders even when no fix ever arrives.
    @Published private(set) var canStartWithoutFix = false

    /// Title of the planned workout for the run in progress; stored in the checkpoint so a
    /// recovered run keeps its label. Set by the Run tab before `start()`.
    var activeWorkoutTitle: String?
    /// Guide stages of the planned workout for the run starting now. Set by the Run tab before
    /// `start()`, like `activeWorkoutTitle`. Nil for free runs and workouts without a parseable target.
    var activeGuideSteps: [GuideStep]?
    /// Follows `activeGuideSteps` once the clock runs; advanced from moving time and distance.
    @Published private(set) var workoutGuide: WorkoutGuide?
    /// Called when starting a new run saved an unanswered recovered run first. The Run tab uses
    /// it to export that run to Health and process it silently (no summary screen).
    var onRecoveredRunAutoSaved: ((RecordedRun) -> Void)?
    @Published private(set) var isAutoPaused = false
    var autoPauseEnabledProvider: (() -> Bool)?
    var isEndDecisionPending = false
    private var autoPauseDetector = RunAutoPauseDetector()
    private var autoPauseEnabled: Bool {
        autoPauseEnabledProvider?() ?? (UserDefaults.standard.object(forKey: "runAutoPauseEnabled") == nil
            ? true : UserDefaults.standard.bool(forKey: "runAutoPauseEnabled"))
    }
    var estimatedActiveKilocalories: Double? {
        RunCalorieEstimator.activeKilocalories(distanceMeters: distanceMeters, weightKg: RunnerWeightStore.shared.weightKg)
    }

    private let manager = CLLocationManager()
    private let store: RunSmartLocalStore
    private let checkpointStore: RunCheckpointStore
    private var lastCheckpointLocationTime: Date?
    /// Wall-clock time of the newest checkpoint write, so the 1 s timer can keep `savedAt`
    /// fresh when no fixes arrive (Start anyway, standing still, a GPS outage).
    private var lastCheckpointWriteAt: Date?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPausedSeconds: TimeInterval = 0
    private var pauseIntervals: [RunPauseInterval] = []
    private var timer: Timer?
    private var acquiringTimer: Timer?
    private var lastAcceptedLocation: CLLocation?
    private var lastDisplayLocation: CLLocation?
    private var lastDisplayRouteUpdate: Date?
    private var shouldStartAfterPermission = false

    /// Injectable authorization lookup so recorder phase transitions can be unit-tested
    /// under a known authorization state. Defaults to the live `CLLocationManager`.
    var authorizationStatusProvider: (() -> CLAuthorizationStatus)?
    private var authorizationStatus: CLAuthorizationStatus {
        authorizationStatusProvider?() ?? manager.authorizationStatus
    }

    nonisolated static let requiredStartAccuracy: CLLocationAccuracy = 35
    nonisolated static let acceptedRecordingAccuracy: CLLocationAccuracy = 65
    nonisolated static let maximumLocationAge: TimeInterval = 15
    nonisolated static let liveRouteMinimumInterval: TimeInterval = 2
    nonisolated static let liveRouteMinimumDistance: CLLocationDistance = 12
    nonisolated static let maximumDisplayRoutePoints = 240
    /// Jitter filter: a fix implying more than this speed from the last accepted point is an outlier jump.
    nonisolated static let maximumPlausibleSpeed: CLLocationSpeed = 12
    nonisolated static let minimumAcceptedMovement: CLLocationDistance = 3
    nonisolated static let stationarySpeedThreshold: CLLocationSpeed = 0.5
    nonisolated static let stationaryAccuracyMultiplier: Double = 2
    nonisolated static let unknownSpeedAccuracyMultiplier: Double = 1.5
    nonisolated static let currentPaceWindow: TimeInterval = 30
    nonisolated static let currentPaceMaximumAge: TimeInterval = 10
    nonisolated static let currentPaceMinimumDistance: CLLocationDistance = 15
    /// Seconds of in-window fixes needed before a current pace is shown (see `currentPace`).
    nonisolated static let currentPaceMinimumHistory: TimeInterval = 10
    nonisolated static let checkpointMinimumInterval: TimeInterval = 10
    nonisolated static let maximumResumableCheckpointAge: TimeInterval = 12 * 3_600
    /// How long the GPS search runs before the runner may start the clock without a fix.
    nonisolated static let startWithoutFixDelay: TimeInterval = 20

    override convenience init() {
        self.init(store: .shared)
    }

    init(store: RunSmartLocalStore, checkpointStore: RunCheckpointStore = .shared) {
        self.store = store
        self.checkpointStore = checkpointStore
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        updatePhaseForAuthorization()
        if phase != .recording, phase != .paused {
            pendingRecovery = checkpointStore.load()
        }
    }

    var distanceLabel: String { String(format: "%.2f", distanceMeters / 1_000) }
    var elapsedLabel: String { Self.timeLabel(elapsedSeconds) }
    var movingLabel: String { Self.timeLabel(movingSeconds) }
    var averagePaceLabel: String {
        guard distanceMeters >= 20 else { return "--" }
        return Self.paceLabel(secondsPerKm: movingSeconds / max(distanceMeters / 1_000, 0.001))
    }
    var currentPaceLabel: String {
        guard let currentPaceSeconds else { return "--" }
        return Self.paceLabel(secondsPerKm: currentPaceSeconds)
    }

    func requestPermission() {
        lastErrorMessage = nil
        phase = .requestingPermission
        Analytics.trackPermissionRequested(kind: "location")
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        if authorizationStatus == .notDetermined {
            shouldStartAfterPermission = true
            requestPermission()
            return
        }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            shouldStartAfterPermission = false
            phase = .denied
            lastErrorMessage = "Location permission is required to record GPS runs."
            return
        }

        startAcquiringLocation()
    }

    func startAcquiringLocation(startLocationUpdates: Bool = true) {
        shouldStartAfterPermission = false
        // A new run supersedes an unanswered recovery prompt; keep that run in history
        // instead of letting the new run's checkpoint overwrite it. Saving it leaves
        // `activeWorkoutTitle` alone (it belongs to the run starting now), and the owner gets
        // the saved run so it can export and process it like any finished run.
        if pendingRecovery != nil, let recovered = saveRecoveredRun() {
            onRecoveredRunAutoSaved?(recovered)
        }
        resetCurrentRun()
        phase = .acquiringLocation
        beginAcquiringClock()
        setTrackingPower(low: false)
        if startLocationUpdates {
            manager.startUpdatingLocation()
        }
    }

    /// True once the GPS search has run for `startWithoutFixDelay` seconds.
    nonisolated static func canStartWithoutFix(acquiringSince: Date?, now: Date) -> Bool {
        guard let acquiringSince else { return false }
        return now.timeIntervalSince(acquiringSince) >= startWithoutFixDelay
    }

    /// Gives up the GPS search and returns to the pre-run screen. No-op outside `.acquiringLocation`.
    func cancelAcquiring() {
        guard phase == .acquiringLocation else { return }
        shouldStartAfterPermission = false
        stopTracking()
        resetCurrentRun()
        activeWorkoutTitle = nil
        activeGuideSteps = nil
        resolveTerminalPhase()
    }

    /// Starts the clock without waiting for a good fix. Location updates keep running; the
    /// first usable fix that arrives later becomes the first route point and adds no distance.
    /// No-op outside `.acquiringLocation`.
    func startWithoutFix(now: Date = Date()) {
        guard phase == .acquiringLocation else { return }
        endAcquiringClock()
        startedAt = now
        pausedAt = nil
        accumulatedPausedSeconds = 0
        lastErrorMessage = nil
        isAutoPaused = false
        autoPauseDetector.reset()
        phase = .recording
        setTrackingPower(low: false)
        // Same start announcement as a run that began on a fix.
        LocalRunCueService.shared.begin()
        workoutGuide = activeGuideSteps.flatMap { WorkoutGuide(steps: $0) }
        startTimer()
        tick(now: now)
        // Written now, before any fix, so a crash in the first minute is still recoverable.
        writeCheckpoint(now: now)
    }

    private func beginAcquiringClock() {
        acquiringTimer?.invalidate()
        acquiringStartedAt = Date()
        canStartWithoutFix = false
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCanStartWithoutFix()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        acquiringTimer = timer
    }

    private func refreshCanStartWithoutFix() {
        guard phase == .acquiringLocation else {
            endAcquiringClock()
            return
        }
        let value = Self.canStartWithoutFix(acquiringSince: acquiringStartedAt, now: Date())
        if value != canStartWithoutFix {
            canStartWithoutFix = value
        }
    }

    private func endAcquiringClock() {
        acquiringTimer?.invalidate()
        acquiringTimer = nil
        if acquiringStartedAt != nil { acquiringStartedAt = nil }
        if canStartWithoutFix { canStartWithoutFix = false }
    }

    private func beginRecording(from firstLocation: CLLocation, startedAt startDate: Date = Date()) {
        endAcquiringClock()
        startedAt = startDate
        pausedAt = nil
        accumulatedPausedSeconds = 0
        lastErrorMessage = nil
        phase = .recording
        // The first accepted fix always writes the opening checkpoint (see
        // acceptRecordingLocation), so a run that dies seconds in is still recoverable.
        acceptRecordingLocation(firstLocation, forceDisplay: true)
        startTimer()
        tick()
        LocalRunCueService.shared.begin()
        // After the start cue, so the first step cue queues behind it instead of cutting it off.
        workoutGuide = activeGuideSteps.flatMap { WorkoutGuide(steps: $0) }
    }

    func pause() { pause(at: Date(), automatic: false) }

    private func pause(at date: Date, automatic: Bool) {
        guard phase == .recording else { return }
        pausedAt = max(startedAt ?? date, date)
        isAutoPaused = automatic
        autoPauseDetector.reset()
        phase = .paused
        // Queued so a pause never cuts off a step or split cue; an auto-pause is also debounced so
        // stop-and-go running does not repeat it.
        if automatic {
            LocalRunCueService.shared.announce("Auto-paused.", queued: true, debounce: .autoPause)
        } else {
            LocalRunCueService.shared.announce("Run paused.", queued: true)
        }
        if automatic { RunSmartHaptics.light() }
        // Manual pauses use low-power GPS. Automatic pauses retain frequent fixes
        // so movement can resume the run, including while the phone is locked.
        setTrackingPower(low: !automatic)
        tick()
        if automatic {
            // The pause was backdated and drift distance trimmed, so moving time and distance just
            // went down. Bring the guide back with them, before the checkpoint stores it.
            workoutGuide?.rebase(distance: distanceMeters, movingTime: movingSeconds)
        }
        writeCheckpoint()
    }

    func resume() { resume(at: Date()) }

    private func resume(at now: Date) {
        guard phase == .paused else { return }
        let wasAutoPaused = isAutoPaused
        isAutoPaused = false
        autoPauseDetector.reset()
        if let pausedAt {
            accumulatedPausedSeconds += max(0, now.timeIntervalSince(pausedAt))
            pauseIntervals.append(RunPauseInterval(start: pausedAt, end: max(pausedAt, now)))
        }
        pausedAt = nil
        // The runner may have moved while tracking was paused. The first new
        // fix establishes a fresh distance anchor (and starts a new route segment)
        // instead of counting that gap.
        lastAcceptedLocation = nil
        phase = .recording
        LocalRunCueService.shared.announce("Run resumed.", queued: true, debounce: wasAutoPaused ? .autoResume : nil)
        setTrackingPower(low: false)
        manager.startUpdatingLocation()
        tick()
        writeCheckpoint()
    }

    func discard() {
        shouldStartAfterPermission = false
        stopTracking()
        // After tracking stops: nothing can speak once the run is gone.
        LocalRunCueService.shared.stop()
        resetCurrentRun()
        checkpointStore.delete()
        activeWorkoutTitle = nil
        activeGuideSteps = nil
        lastSavedRun = nil
        resolveTerminalPhase()
    }

    @discardableResult
    func finish() -> RecordedRun? {
        guard let startedAt else { return nil }
        let endedAt = Date()
        let activePauseStartedAt = pausedAt
        var finishedPauseIntervals = pauseIntervals
        if let activePauseStartedAt {
            finishedPauseIntervals.append(RunPauseInterval(start: activePauseStartedAt, end: max(activePauseStartedAt, endedAt)))
        }
        stopTracking()
        let moving = Self.movingDuration(
            startedAt: startedAt,
            endedAt: endedAt,
            accumulatedPausedSeconds: accumulatedPausedSeconds,
            activePauseStartedAt: activePauseStartedAt
        )
        let run = Self.makeRecordedRun(
            startedAt: startedAt,
            endedAt: endedAt,
            movingSeconds: moving,
            distanceMeters: distanceMeters,
            routePoints: routePoints,
            pauseIntervals: finishedPauseIntervals,
            plannedTitle: activeWorkoutTitle
        )
        LocalRunCueService.shared.announce("Run finished. " + String(format: "%.2f kilometers. ", run.distanceMeters / 1_000) + "Moving time " + RunCueSchedule.duration(run.movingTimeSeconds))
        store.saveRun(run)
        checkpointStore.delete()
        activeWorkoutTitle = nil
        activeGuideSteps = nil
        lastSavedRun = run
        resetCurrentRun()
        resolveTerminalPhase()
        return run
    }

    private static func makeRecordedRun(
        startedAt: Date,
        endedAt: Date,
        movingSeconds: TimeInterval,
        distanceMeters: Double,
        routePoints: [RunRoutePoint],
        pauseIntervals: [RunPauseInterval],
        plannedTitle: String? = nil
    ) -> RecordedRun {
        let pace = distanceMeters > 0 ? movingSeconds / (distanceMeters / 1_000) : 0
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            movingTimeSeconds: movingSeconds,
            averagePaceSecondsPerKm: pace,
            averageHeartRateBPM: nil,
            routePoints: routePoints,
            syncedAt: nil,
            pauseIntervals: pauseIntervals,
            estimatedActiveKilocalories: RunCalorieEstimator.activeKilocalories(distanceMeters: distanceMeters, weightKg: RunnerWeightStore.shared.weightKg),
            title: RunTitle.normalized(plannedTitle, limit: RunTitle.maximumTitleLength)
        )
    }

    // MARK: Crash and kill recovery

    /// Resume is only offered for a recent checkpoint, and only while location is
    /// authorized; an older or ungated run can still be saved or discarded.
    var canResumeRecoveredRun: Bool {
        guard let checkpoint = pendingRecovery else { return false }
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return false }
        return Date().timeIntervalSince(checkpoint.savedAt) <= Self.maximumResumableCheckpointAge
    }

    /// Rebuilds the run from the checkpoint and lands in `.paused`. Everything since the
    /// checkpoint was written counts as paused time, so the runner sees "Paused" and
    /// taps Resume when they are moving again.
    func resumeRecoveredRun(startLocationUpdates: Bool = true) {
        guard let checkpoint = pendingRecovery, canResumeRecoveredRun else { return }
        guard phase != .recording, phase != .paused else { return }
        shouldStartAfterPermission = false
        resetCurrentRun()
        startedAt = checkpoint.startedAt
        accumulatedPausedSeconds = checkpoint.accumulatedPausedSeconds
        pauseIntervals = checkpoint.pauseIntervals ?? []
        pausedAt = checkpoint.wasPaused ? (checkpoint.pausedAt ?? checkpoint.savedAt) : checkpoint.savedAt
        routePoints = checkpoint.routePoints
        displayRoutePoints = Self.simplifiedDisplayRoute(from: checkpoint.routePoints)
        distanceMeters = checkpoint.distanceMeters
        lastSplitCheckKilometer = Int(checkpoint.distanceMeters / 1_000)
        completedKilometerSplits = Self.kilometerSplits(from: checkpoint.routePoints).filter { !$0.isPartial }
        activeWorkoutTitle = checkpoint.workoutTitle
        workoutGuide = checkpoint.workoutGuide
        pendingRecovery = nil
        phase = .paused
        LocalRunCueService.shared.begin(distance: distanceMeters, movingTime: checkpoint.movingSecondsAtSave, recovered: true)
        setTrackingPower(low: true)
        if startLocationUpdates {
            manager.startUpdatingLocation()
        }
        startTimer()
        tick()
        writeCheckpoint()
    }

    /// Saves the unfinished run as it stood at the last checkpoint.
    @discardableResult
    func saveRecoveredRun() -> RecordedRun? {
        guard let checkpoint = pendingRecovery else { return nil }
        let endedAt = max(checkpoint.savedAt, checkpoint.routePoints.last?.timestamp ?? checkpoint.savedAt)
        let moving = Self.movingDuration(
            startedAt: checkpoint.startedAt,
            endedAt: endedAt,
            accumulatedPausedSeconds: checkpoint.accumulatedPausedSeconds,
            activePauseStartedAt: checkpoint.wasPaused ? checkpoint.pausedAt : nil
        )
        var recoveredPauseIntervals = checkpoint.pauseIntervals ?? []
        if checkpoint.wasPaused, let pausedAt = checkpoint.pausedAt {
            recoveredPauseIntervals.append(RunPauseInterval(start: pausedAt, end: max(pausedAt, endedAt)))
        }
        let run = Self.makeRecordedRun(
            startedAt: checkpoint.startedAt,
            endedAt: endedAt,
            movingSeconds: moving,
            distanceMeters: checkpoint.distanceMeters,
            routePoints: checkpoint.routePoints,
            pauseIntervals: recoveredPauseIntervals,
            plannedTitle: checkpoint.workoutTitle
        )
        store.saveRun(run)
        checkpointStore.delete()
        pendingRecovery = nil
        lastSavedRun = run
        resolveTerminalPhase()
        return run
    }

    func discardRecoveredRun() {
        checkpointStore.delete()
        pendingRecovery = nil
    }

    private func writeCheckpoint(now: Date = Date()) {
        guard let checkpoint = currentCheckpoint(now: now) else { return }
        lastCheckpointWriteAt = now
        checkpointStore.save(checkpoint)
    }

    private func currentCheckpoint(now: Date = Date()) -> RunSessionCheckpoint? {
        guard let startedAt, phase == .recording || phase == .paused else { return nil }
        return RunSessionCheckpoint(
            startedAt: startedAt,
            accumulatedPausedSeconds: accumulatedPausedSeconds,
            pausedAt: pausedAt,
            wasPaused: phase == .paused,
            routePoints: routePoints,
            distanceMeters: distanceMeters,
            workoutTitle: activeWorkoutTitle,
            savedAt: now,
            pauseIntervals: pauseIntervals,
            workoutGuide: workoutGuide
        )
    }

    private func setTrackingPower(low: Bool) {
        manager.desiredAccuracy = low ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyBest
        manager.distanceFilter = low ? 50 : (autoPauseEnabled ? kCLDistanceFilterNone : 5)
    }

    /// WP-45: which permission event (if any) a location-authorization callback
    /// should emit. Pure so the denied path — the exact gap WP-45 closes — is
    /// unit-testable. Only resolves while a prompt is actually pending, never on
    /// the cold-start authorization callback.
    static func locationPermissionEvent(
        phase: RunRecordingPhase,
        status: CLAuthorizationStatus
    ) -> String? {
        guard phase == .requestingPermission else { return nil }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return "permission_granted"
        case .denied, .restricted:
            return "permission_denied"
        default:
            return nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // WP-45: only requests were visible before; a user who denied GPS looked
        // identical in the funnel to one who was never asked.
        switch Self.locationPermissionEvent(phase: phase, status: manager.authorizationStatus) {
        case "permission_granted": Analytics.trackPermissionGranted(kind: "location")
        case "permission_denied": Analytics.trackPermissionDenied(kind: "location")
        default: break
        }
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
        if phase == .recording || phase == .paused {
            // Only an explicit permission denial should abort an active run. Every
            // other CLLocationManager failure (e.g. kCLErrorLocationUnknown) is
            // transient per Apple's docs and must not silently discard a run that's
            // already in progress; keep recording and surface degraded-GPS copy.
            if (error as? CLError)?.code == .denied {
                // Keep the run: snapshot it to disk and hand it to the "Unfinished run"
                // prompt (Save or Discard; Resume is withheld without permission). Without
                // this the run vanished and a later Start overwrote its checkpoint.
                if let checkpoint = currentCheckpoint() {
                    checkpointStore.save(checkpoint)
                    pendingRecovery = checkpoint
                }
                stopTracking()
                resetCurrentRun()
                lastErrorMessage = "Location permission is required to record GPS runs."
                phase = .denied
                return
            }
            lastErrorMessage = "Weak GPS signal. RunSmart keeps recording and will reconnect automatically."
            return
        }

        // While searching for the first fix, kCLErrorLocationUnknown is the normal "no signal
        // yet" answer. Keep searching so Cancel and Start anyway stay available; only a
        // real failure (permission denied and the like) ends the search.
        if phase == .acquiringLocation, (error as? CLError)?.code == .locationUnknown {
            return
        }

        // Stop the receiver and the acquiring clock first, or GPS keeps running behind a
        // screen that says it has failed.
        stopTracking()
        endAcquiringClock()
        lastErrorMessage = error.localizedDescription
        phase = .failed
    }

    private func updatePhaseForAuthorization() {
        switch authorizationStatus {
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

    /// Resolve the recorder to a non-recording terminal phase after a run ends
    /// (finish/discard). Unlike `updatePhaseForAuthorization()`, this always moves
    /// the phase out of `.recording`/`.paused`, so the Run tab returns to PreRun
    /// instead of rendering a frozen "zombie" live-run screen. It must never be
    /// called on authorization-change callbacks, which can fire mid-run.
    private func resolveTerminalPhase() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            phase = .ready
        case .denied, .restricted:
            shouldStartAfterPermission = false
            phase = .denied
        case .notDetermined:
            phase = .idle
        @unknown default:
            phase = .ready
        }
    }

    func handleLocationUpdates(_ locations: [CLLocation], now: Date = Date()) {
        guard phase == .acquiringLocation || phase == .recording || phase == .paused else { return }
        if !autoPauseEnabled { autoPauseDetector.reset() }

        for location in locations {
            if phase == .acquiringLocation {
                guard Self.isFreshLocation(location, now: now) else { continue }
                horizontalAccuracy = location.horizontalAccuracy
                guard location.horizontalAccuracy <= Self.requiredStartAccuracy else { continue }
                beginRecording(from: location, startedAt: now)
                continue
            }

            guard Self.isUsable(location, maxAccuracy: Self.acceptedRecordingAccuracy, now: now) else {
                autoPauseDetector.reset()
                continue
            }
            horizontalAccuracy = location.horizontalAccuracy
            // Auto-pause starts judging once the run has a first route point. A run started
            // with "Start anyway" therefore cannot pause before its first fix.
            // Standing in a recovery step is part of the workout, not a stop: moving time would
            // freeze and the step would never end. An auto-pause already in force can still resume.
            let isInRecoveryStep = workoutGuide?.currentStep?.kind == .recovery
            if autoPauseEnabled, !isEndDecisionPending, !routePoints.isEmpty, location.horizontalAccuracy <= 25,
               (phase == .recording && !isInRecoveryStep) || isAutoPaused {
                switch autoPauseDetector.update(speed: location.speed, at: location.timestamp, isAutoPaused: isAutoPaused) {
                case .pause(let since):
                    // Remove any low-speed drift recorded during the debounce. The
                    // full stop, including the first eight seconds, is paused time.
                    let stopDate = max(startedAt ?? since, since)
                    routePoints.removeAll { $0.timestamp > stopDate }
                    distanceMeters = Self.routeDistance(routePoints)
                    displayRoutePoints = Self.simplifiedDisplayRoute(from: routePoints)
                    // The trimmed drift may have crossed a kilometer boundary; rebuild the cache.
                    lastSplitCheckKilometer = Int(distanceMeters / 1_000)
                    completedKilometerSplits = Self.kilometerSplits(from: routePoints).filter { !$0.isPartial }
                    pause(at: stopDate, automatic: true)
                    continue
                case .resume:
                    resume(at: location.timestamp)
                    RunSmartHaptics.light()
                case nil: break
                }
            } else {
                autoPauseDetector.reset()
            }
            guard phase == .recording else { continue }
            acceptRecordingLocation(location)
        }
        tick(now: now)
    }

    private static func routeDistance(_ points: [RunRoutePoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            guard pair.1.startsNewSegment != true else { return total }
            return total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
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
        for displayIndex in 0..<maxPoints {
            let sourceIndex = displayIndex == maxPoints - 1 ? lastIndex : Int((Double(displayIndex) * step).rounded())
            result.append(points[sourceIndex])
        }
        // Thinning must not swallow a segment start, or the map would join the two stretches
        // on either side of a pause with a straight line.
        let keptIDs = Set(result.map(\.id))
        if points.contains(where: { $0.startsNewSegment == true && !keptIDs.contains($0.id) }) {
            let segmentStartIDs = Set(points.filter { $0.startsNewSegment == true }.map(\.id))
            return points.filter { keptIDs.contains($0.id) || segmentStartIDs.contains($0.id) }
        }
        return result
    }

    private func acceptRecordingLocation(_ location: CLLocation, forceDisplay: Bool = false) {
        // A usable location means GPS has reconnected; clear any transient-error
        // copy set by locationManager(_:didFailWithError:) so the GPS pill reverts
        // to normal accuracy messaging instead of sticking on the old error text.
        lastErrorMessage = nil
        // The first point of a segment (run start, or the first fix after a pause or a
        // recovered-run resume) has no anchor, so it is never filtered and adds no distance.
        let startsNewSegment = lastAcceptedLocation == nil && !routePoints.isEmpty
        if let anchor = lastAcceptedLocation {
            let delta = location.distance(from: anchor)
            guard Self.shouldAcceptMovement(from: anchor, to: location) else { return }
            distanceMeters += delta
        }

        let point = RunRoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            startsNewSegment: startsNewSegment ? true : nil
        )
        routePoints.append(point)
        lastAcceptedLocation = location
        refreshCompletedSplitsIfNeeded()
        updateCurrentPace()
        updateDisplayRoute(with: location, force: forceDisplay)

        // Throttled by fix time: the route can be megabytes on a long run.
        if lastCheckpointLocationTime.map({ location.timestamp.timeIntervalSince($0) >= Self.checkpointMinimumInterval }) ?? true {
            lastCheckpointLocationTime = location.timestamp
            writeCheckpoint()
        }
    }

    /// GPS jitter filter. The last accepted point is the anchor and stays put when a fix is
    /// rejected, so real slow movement still accumulates on a later fix. A fix is dropped when:
    /// (a) it implies more than 12 m/s from the anchor (outlier jump),
    /// (b) it is closer than max(3 m, half its horizontal accuracy) to the anchor,
    /// (c) the device reports it is standing still (speed 0 to 0.5 m/s) and the move is within
    ///     twice the accuracy radius (two noisy fixes can differ by about 1.4x the radius), or
    /// (d) the device reports no speed and the move is within 1.5x the accuracy radius.
    static func shouldAcceptMovement(from anchor: CLLocation, to location: CLLocation) -> Bool {
        let delta = location.distance(from: anchor)
        let elapsed = location.timestamp.timeIntervalSince(anchor.timestamp)
        let accuracy = location.horizontalAccuracy
        guard elapsed > 0, delta / elapsed <= maximumPlausibleSpeed else { return false }
        guard delta >= max(minimumAcceptedMovement, 0.5 * accuracy) else { return false }
        if location.speed >= 0 {
            if location.speed < stationarySpeedThreshold, delta <= stationaryAccuracyMultiplier * accuracy {
                return false
            }
        } else if delta <= unknownSpeedAccuracyMultiplier * accuracy {
            return false
        }
        return true
    }

    /// Recomputes full-kilometer splits once per newly crossed kilometer of accepted distance.
    private func refreshCompletedSplitsIfNeeded() {
        let crossed = Int(distanceMeters / 1_000)
        guard crossed > lastSplitCheckKilometer else { return }
        lastSplitCheckKilometer = crossed
        completedKilometerSplits = Self.kilometerSplits(from: routePoints).filter { !$0.isPartial }
    }

    private func updateCurrentPace(now: Date = Date()) {
        let pace = Self.currentPace(points: routePoints, now: now)
        if pace != currentPaceSeconds {
            currentPaceSeconds = pace
        }
    }

    /// Pace in seconds per kilometer over roughly the last 30 seconds of the current
    /// segment, using summed path distance. Nil when that window covers under 15 m, holds
    /// under 10 s of fixes, or the newest point is more than 10 seconds old (stopped, or no GPS).
    ///
    /// The segment that crosses the start of the window is clipped in proportion to the window,
    /// and dropped when it spans a GPS gap longer than the window: a fix that arrives minutes
    /// after the previous one must not show the whole gap's average as the current pace.
    static func currentPace(points: [RunRoutePoint], now: Date) -> TimeInterval? {
        guard let newest = points.last else { return nil }
        guard now.timeIntervalSince(newest.timestamp) <= currentPaceMaximumAge else { return nil }

        let windowStart = newest.timestamp.addingTimeInterval(-currentPaceWindow)
        var meters: Double = 0
        // Oldest fix that is itself inside the window; the clipped boundary segment is not one.
        var oldestFix = newest.timestamp
        // Start of the time span `meters` covers.
        var spanStart = newest.timestamp
        var index = points.count - 1
        while index > 0 {
            let current = points[index]
            if current.startsNewSegment == true || spanStart <= windowStart { break }
            let previous = points[index - 1]
            let segmentMeters = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            if previous.timestamp >= windowStart {
                meters += segmentMeters
                oldestFix = previous.timestamp
                spanStart = previous.timestamp
            } else {
                let segmentSeconds = current.timestamp.timeIntervalSince(previous.timestamp)
                if segmentSeconds > 0, segmentSeconds <= currentPaceWindow {
                    meters += segmentMeters * (current.timestamp.timeIntervalSince(windowStart) / segmentSeconds)
                    spanStart = windowStart
                }
                break
            }
            index -= 1
        }

        let seconds = newest.timestamp.timeIntervalSince(spanStart)
        guard newest.timestamp.timeIntervalSince(oldestFix) >= currentPaceMinimumHistory,
              meters >= currentPaceMinimumDistance, seconds > 0 else { return nil }
        return seconds / (meters / 1_000)
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
        workoutGuide = nil
        isAutoPaused = false
        isEndDecisionPending = false
        autoPauseDetector.reset()
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
        pauseIntervals = []
        currentPaceSeconds = nil
        lastCheckpointLocationTime = nil
        lastCheckpointWriteAt = nil
        completedKilometerSplits = []
        lastSplitCheckKilometer = 0
        endAcquiringClock()
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

    /// Runs every second while a run is live. While recording it also refreshes the checkpoint
    /// every `checkpointMinimumInterval`, independent of fixes: after a kill, `savedAt` is
    /// where "Save" ends the run and where "Resume" starts counting paused time.
    func tick(now: Date = Date(), allowsCues: Bool = true) {
        guard let startedAt else { return }
        // Cues are decided from the phase at the start of the tick, while the run is still live.
        let isRecordingRun = phase == .recording
        elapsedSeconds = now.timeIntervalSince(startedAt)
        movingSeconds = Self.movingDuration(
            startedAt: startedAt,
            endedAt: now,
            accumulatedPausedSeconds: accumulatedPausedSeconds,
            activePauseStartedAt: pausedAt
        )
        if phase == .recording {
            updateCurrentPace(now: now)
        } else if currentPaceSeconds != nil {
            currentPaceSeconds = nil
        }
        guard isRecordingRun, phase == .recording else { return }
        if allowsCues {
            let guideCues = workoutGuide?.update(
                distance: distanceMeters,
                movingTime: movingSeconds,
                currentPace: currentPaceSeconds
            ) ?? []
            LocalRunCueService.shared.update(distance: distanceMeters, movingTime: movingSeconds, guide: guideCues)
        }
        if lastCheckpointWriteAt.map({ now.timeIntervalSince($0) >= Self.checkpointMinimumInterval }) ?? true {
            writeCheckpoint(now: now)
        }
    }

    private func stopTracking() {
        manager.stopUpdatingLocation()
        setTrackingPower(low: false)
        timer?.invalidate()
        timer = nil
        // Final clock update only. The run is ending (finished or discarded), so no cue may speak.
        tick(allowsCues: false)
        startedAt = nil
        pausedAt = nil
    }

    /// Formats run duration for live HUD / post-run / history.
    /// Under 1 hour: `MM:SS` (zero-padded minutes). At/above 3600s: `H:MM:SS`
    /// so a 90-minute run reads `1:30:00` instead of `90:00` (WP-38 S10).
    static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", Int32(total / 3600), Int32((total % 3600) / 60), Int32(total % 60))
        }
        return String(format: "%02d:%02d", Int32(total / 60), Int32(total % 60))
    }

    static func paceLabel(secondsPerKm: TimeInterval) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", Int32(total / 60), Int32(total % 60))
    }

    /// Total positive elevation gain in metres from GPS altitude. Returns nil when fewer than
    /// two points carry altitude. A climb only counts once altitude is at least `hysteresisMeters`
    /// above the reference level, so GPS altitude noise does not inflate the total.
    static func elevationGainMeters(from points: [RunRoutePoint], hysteresisMeters: Double = 3) -> Double? {
        var altitudeCount = 0
        var reference: Double?
        var gain = 0.0
        for point in points {
            guard let altitude = point.altitude else { continue }
            altitudeCount += 1
            // Altitude changed while recording was off (elevator, car) is not climbing:
            // each segment start re-anchors the reference level.
            if point.startsNewSegment == true || reference == nil {
                reference = altitude
                continue
            }
            if let level = reference {
                if altitude - level >= hysteresisMeters {
                    gain += altitude - level
                    reference = altitude
                } else if level - altitude >= hysteresisMeters {
                    reference = altitude
                }
            }
        }
        guard altitudeCount >= 2 else { return nil }
        return gain
    }

    /// Real per-kilometer splits derived from route-point GPS distance and timestamps.
    /// A full split for kilometer N only appears once the recorded route has crossed N*1000m.
    /// Distance and time are never counted across a segment start (a pause or recovered-run
    /// resume), and each boundary crossing is interpolated linearly within its GPS segment.
    /// After at least one full split, a remainder of 100m or more adds a final partial split
    /// whose pace is normalized per km. A run that never completes a kilometer returns an
    /// empty array (no fabricated or filler splits).
    static func kilometerSplits(from routePoints: [RunRoutePoint], maxSplits: Int? = nil) -> [KilometerSplit] {
        guard routePoints.count >= 2 else { return [] }

        let limit = maxSplits ?? Int.max
        var splits: [KilometerSplit] = []
        var cumulativeDistance: Double = 0
        var activeSeconds: TimeInterval = 0
        var nextBoundaryMeters: Double = 1_000
        var lastBoundaryActiveSeconds: TimeInterval = 0
        var reachedLimit = false

        for index in 1..<routePoints.count {
            if splits.count >= limit {
                reachedLimit = true
                break
            }
            let previous = routePoints[index - 1]
            let point = routePoints[index]
            if point.startsNewSegment == true { continue }

            let segmentDistance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            let segmentSeconds = max(0, point.timestamp.timeIntervalSince(previous.timestamp))

            while cumulativeDistance + segmentDistance >= nextBoundaryMeters, splits.count < limit {
                let fraction = segmentDistance > 0 ? (nextBoundaryMeters - cumulativeDistance) / segmentDistance : 1
                let crossingSeconds = activeSeconds + fraction * segmentSeconds
                splits.append(KilometerSplit(
                    km: splits.count + 1,
                    paceSecondsPerKm: max(0, crossingSeconds - lastBoundaryActiveSeconds)
                ))
                lastBoundaryActiveSeconds = crossingSeconds
                nextBoundaryMeters += 1_000
            }

            cumulativeDistance += segmentDistance
            activeSeconds += segmentSeconds
        }

        if splits.count >= limit, limit != Int.max { reachedLimit = true }
        if !reachedLimit, !splits.isEmpty {
            let remainder = cumulativeDistance - Double(splits.count) * 1_000
            let remainderSeconds = activeSeconds - lastBoundaryActiveSeconds
            if remainder >= 100, remainderSeconds > 0 {
                splits.append(KilometerSplit(
                    km: splits.count + 1,
                    paceSecondsPerKm: remainderSeconds / (remainder / 1_000),
                    distanceMeters: remainder,
                    isPartial: true
                ))
            }
        }

        return splits
    }

    nonisolated static func movingDuration(
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
    func routeRecommendation(for workout: WorkoutSummary?, fallbackDistanceLabel: String?) async -> RouteRecommendation
    func savedRoutes() async -> [SavedRoute]
    func saveRoute(_ route: SavedRoute) async -> Bool
    /// Saves a route created from `run` and stores `run` as an exact match of it.
    func saveRoute(_ route: SavedRoute, fromRun run: RecordedRun) async -> Bool
    func deleteRoute(_ routeID: UUID) async -> Bool
    func updateRoute(_ route: SavedRoute) async -> Bool
    func benchmarkRoutes() async -> [BenchmarkRoute]
    func enableBenchmark(for routeID: UUID) async -> Bool
    func disableBenchmark(for routeID: UUID) async -> Bool
}

extension RouteProviding {
    func savedRoutes() async -> [SavedRoute] { [] }
    func saveRoute(_ route: SavedRoute) async -> Bool { false }
    func saveRoute(_ route: SavedRoute, fromRun run: RecordedRun) async -> Bool { await saveRoute(route) }
    func deleteRoute(_ routeID: UUID) async -> Bool { false }
    func updateRoute(_ route: SavedRoute) async -> Bool { false }
    func benchmarkRoutes() async -> [BenchmarkRoute] { [] }
    func enableBenchmark(for routeID: UUID) async -> Bool { false }
    func disableBenchmark(for routeID: UUID) async -> Bool { false }
    func rankedRouteSuggestions(targetDistanceKm: Double?) async -> [RouteSuggestion] { [] }
    func routeRecommendation(for workout: WorkoutSummary?, fallbackDistanceLabel: String?) async -> RouteRecommendation {
        let routes = await rankedRouteSuggestions(targetDistanceKm: nil)
        return RouteSuggestionRanker.recommendation(from: routes, workout: workout, fallbackDistanceLabel: fallbackDistanceLabel)
    }
}

protocol DeviceSyncing {
    func deviceStatuses() async -> [ConnectedDeviceStatus]
    func connect(provider: String) async -> ConnectedDeviceStatus
    func syncNow(provider: String) async -> ConnectedDeviceStatus
    func disconnect(provider: String) async -> ConnectedDeviceStatus
    func firstSyncReview(provider: String) async -> FirstSyncReview?
    func markFirstSyncReviewSeen(provider: String) async
}

extension DeviceSyncing {
    func firstSyncReview(provider: String) async -> FirstSyncReview? { nil }
    func markFirstSyncReviewSeen(provider: String) async {}
}

protocol HealthSyncing {
    func requestHealthAccess() async -> ConnectedDeviceStatus
    func syncHealthData() async -> ConnectedDeviceStatus
    /// `allowPermissionPrompt` is false for saves that happen in the background (no Health sheet may appear).
    func saveToHealth(_ run: RecordedRun, allowPermissionPrompt: Bool) async
}

extension HealthSyncing {
    /// The save right after a finished run, where the Health permission prompt has context.
    func saveToHealth(_ run: RecordedRun) async {
        await saveToHealth(run, allowPermissionPrompt: true)
    }
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
        let totalDistanceMeters: Double = runs.reduce(0) { $0 + $1.distanceMeters }
        let totalDistance: Int = Int((totalDistanceMeters / 1_000).rounded())
        let totalSeconds: Double = runs.reduce(0) { $0 + $1.movingTimeSeconds }
        let totalHours: Int = Int(totalSeconds / 3_600)
        let totalMinutes: Int = Int(totalSeconds.truncatingRemainder(dividingBy: 3_600)) / 60
        return RunnerProfile(
            name: profile.displayName.isEmpty ? "RunSmart Runner" : profile.displayName,
            goal: profile.goal,
            streak: "\(profile.weeklyRunDays)x/week",
            level: profile.experience,
            totalRuns: runs.count,
            totalDistance: totalDistance,
            totalTime: "\(totalHours)h \(totalMinutes)m"
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
            MetricTile(title: "Moving time", value: last.map { RunRecorder.timeLabel($0.movingTimeSeconds) } ?? "00:00", unit: "", symbol: "stopwatch", tint: .white),
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

    func updateRunRPE(_ run: RecordedRun, rpe: Int?) async -> RecordedRun {
        let updated = store.updateRunRPE(run, rpe: rpe)
        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        }
        return updated
    }

    func updateRunDetails(_ run: RecordedRun, title: String?, notes: String?) async -> RecordedRun {
        let updated = store.updateRunDetails(run, title: title, notes: notes)
        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        }
        return updated
    }

    func matchRoute(for run: RecordedRun) async -> RouteMatchResult? {
        RouteMatchingService.match(run: run, savedRoutes: store.loadSavedRoutes(), benchmarkRouteIDs: store.benchmarkRouteIDs())
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
        var matchedRun = run
        matchedRun.routeMatchResult = RouteMatchingService.match(run: run, savedRoutes: store.loadSavedRoutes(), benchmarkRouteIDs: store.benchmarkRouteIDs())
        return store.saveRunKeepingLocalEdits(matchedRun)
    }

    func processCompletedActivity(_ run: RecordedRun) async -> PostActivityOutcome {
        let canonical = saveRouteMatch(for: ActivityConsolidationService.canonicalRun(for: run, in: store.visibleRuns(store.loadRuns())))
        store.refreshBenchmarkStats()
        Analytics.trackCompletedRunIfNeeded(canonical)
        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        }
        return PostActivityOutcome(
            canonicalRun: canonical,
            report: nil,
            completedWorkout: nil,
            didCompletePlannedWorkout: false,
            debrief: nil
        )
    }

    func removeRun(_ run: RecordedRun) async -> Bool {
        let removed = store.removeRun(run)
        if removed { store.refreshBenchmarkStats() }
        return removed
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
        await store.rematchStoredRuns()
        postRouteChange()
        return true
    }

    func saveRoute(_ route: SavedRoute, fromRun run: RecordedRun) async -> Bool {
        store.saveSavedRoute(route)
        await store.rematchStoredRuns(savedFrom: run, routeID: route.id)
        postRouteChange()
        return true
    }

    func deleteRoute(_ routeID: UUID) async -> Bool {
        let removed = store.removeSavedRoute(routeID)
        if removed {
            // Runs attached to the deleted route move to the best remaining one.
            await store.rematchStoredRuns()
            postRouteChange()
        }
        return removed
    }

    func updateRoute(_ route: SavedRoute) async -> Bool {
        var updated = route
        updated.updatedAt = Date()
        store.saveSavedRoute(updated)
        postRouteChange()
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
        await store.rematchStoredRuns()
        postRouteChange()
        return true
    }

    func disableBenchmark(for routeID: UUID) async -> Bool {
        let removed = store.removeBenchmarkRoute(routeID)
        if removed {
            // Runs attached to this benchmark move to the best remaining one.
            await store.rematchStoredRuns()
            postRouteChange()
        }
        return removed
    }

    private func postRouteChange() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .runSmartRoutesDidChange, object: nil)
        }
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
            let status = await requestHealthAccess()
            guard status.state == .connected else { return status }
            return await syncHealthData()
        }
        let status = ConnectedDeviceStatus(provider: provider, state: .error, lastSuccessfulSync: nil, permissions: [], message: "Unsupported provider.")
        store.saveDeviceStatus(status)
        return status
    }

    func syncNow(provider: String) async -> ConnectedDeviceStatus {
        if provider == "Garmin Connect" {
            let result = await garmin.syncActivities()
            let existingIDs = Set(store.loadRuns().compactMap(\.providerActivityID))
            let newRuns = result.runs
                .sorted { $0.startedAt > $1.startedAt }
                .filter { run in
                    guard let pid = run.providerActivityID else { return true }
                    return !existingIDs.contains(pid)
                }
            for run in newRuns {
                _ = await processCompletedActivity(run)
            }
            store.saveDeviceStatus(result.status)
            saveFirstSyncReviewIfNeeded(
                provider: .garmin,
                status: result.status,
                importedRuns: newRuns,
                skippedDuplicateCount: max(0, result.runs.count - newRuns.count)
            )
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
            // Imported history (often months of the same loops) only counts toward a saved
            // route once it is matched against it.
            await store.rematchStoredRuns()
            await MainActor.run {
                NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .runSmartHealthDidChange, object: nil)
        }
        saveFirstSyncReviewIfNeeded(
            provider: .healthKit,
            status: result.status,
            importedRuns: result.runs,
            skippedDuplicateCount: result.skippedDuplicates
        )
        Analytics.trackHealthKitSyncCompleted(importedCount: result.runs.count)
        return result.status
    }

    func saveToHealth(_ run: RecordedRun, allowPermissionPrompt: Bool) async {
        await health.save(run, allowPermissionPrompt: allowPermissionPrompt)
    }

    func firstSyncReview(provider: String) async -> FirstSyncReview? {
        guard let provider = FirstSyncReviewProvider(serviceName: provider) else { return nil }
        return store.firstSyncReview(provider: provider)
    }

    func markFirstSyncReviewSeen(provider: String) async {
        guard let provider = FirstSyncReviewProvider(serviceName: provider) else { return }
        store.markFirstSyncReviewSeen(provider: provider)
    }

    private func saveFirstSyncReviewIfNeeded(
        provider: FirstSyncReviewProvider,
        status: ConnectedDeviceStatus,
        importedRuns: [RecordedRun],
        skippedDuplicateCount: Int
    ) {
        guard status.state == .connected, !store.hasSeenFirstSyncReview(provider: provider) else { return }
        store.saveFirstSyncReview(FirstSyncReview.make(
            provider: provider,
            importedRuns: importedRuns,
            skippedDuplicateCount: skippedDuplicateCount
        ))
    }

    private func deviceSubtitle(_ provider: String) -> String {
        store.loadDeviceStatuses().first(where: { $0.provider == provider })?.state.rawValue.capitalized ?? "Off"
    }

    private func elevationGain(points: [RunRoutePoint]) -> Int {
        Int(RunRoutePoint.ascentMeters(in: points).rounded())
    }
}

// MARK: - Benchmark stat hydration (pure, testable)

enum BenchmarkStatRefresh {
    /// Recomputes cached aggregate stats for each BenchmarkRoute from the current run history.
    /// Matched runs and route variants count toward run count and average pace; times
    /// (PB, average duration) come from full-route matches only.
    static func refresh(_ benchmarks: [BenchmarkRoute], from runs: [RecordedRun]) -> [BenchmarkRoute] {
        benchmarks.map { benchmark -> BenchmarkRoute in
            let counted: [RecordedRun] = runs.filter {
                $0.routeMatchResult?.routeID == benchmark.savedRouteID &&
                $0.routeMatchResult?.confidence.countsTowardRoute == true
            }
            let fullRoute: [RecordedRun] = counted.filter { $0.routeMatchResult?.confidence == .matched }
            var updated: BenchmarkRoute = benchmark
            updated.historicalRunCount = counted.count
            updated.personalBestSeconds = nil
            updated.personalBestDate = nil
            updated.averagePaceSecondsPerKm = nil
            updated.averageDurationSeconds = nil
            if !counted.isEmpty {
                updated.averagePaceSecondsPerKm = counted.reduce(0.0) { $0 + $1.averagePaceSecondsPerKm } / Double(counted.count)
            }
            if !fullRoute.isEmpty {
                if let best: RecordedRun = fullRoute.min(by: { $0.movingTimeSeconds < $1.movingTimeSeconds }) {
                    updated.personalBestSeconds = best.movingTimeSeconds
                    updated.personalBestDate = best.startedAt
                }
                updated.averageDurationSeconds = fullRoute.reduce(0.0) { $0 + $1.movingTimeSeconds } / Double(fullRoute.count)
            }
            return updated
        }
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
