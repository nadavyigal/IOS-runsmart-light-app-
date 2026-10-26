import Foundation
import CoreLocation
#if canImport(HealthKit)
import HealthKit
import WorkoutKit
#endif

struct HealthKitDailySnapshot: Codable, Hashable {
    var date: Date
    var steps: Int?
    var restingHeartRateBPM: Int?
    var hrvMilliseconds: Double?
    var hrvSource: HRVSource
    var sleepSeconds: TimeInterval?
    var activeEnergyKilocalories: Double?

    init(
        date: Date,
        steps: Int?,
        restingHeartRateBPM: Int?,
        hrvMilliseconds: Double?,
        hrvSource: HRVSource = .unknown,
        sleepSeconds: TimeInterval?,
        activeEnergyKilocalories: Double?
    ) {
        self.date = date
        self.steps = steps
        self.restingHeartRateBPM = restingHeartRateBPM
        self.hrvMilliseconds = hrvMilliseconds
        self.hrvSource = hrvSource
        self.sleepSeconds = sleepSeconds
        self.activeEnergyKilocalories = activeEnergyKilocalories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        steps = try container.decodeIfPresent(Int.self, forKey: .steps)
        restingHeartRateBPM = try container.decodeIfPresent(Int.self, forKey: .restingHeartRateBPM)
        hrvMilliseconds = try container.decodeIfPresent(Double.self, forKey: .hrvMilliseconds)
        hrvSource = try container.decodeIfPresent(HRVSource.self, forKey: .hrvSource) ?? .unknown
        sleepSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .sleepSeconds)
        activeEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories)
    }
}

struct HealthKitImportResult {
    var status: ConnectedDeviceStatus
    var runs: [RecordedRun]
    var wellness: HealthKitDailySnapshot?
    var skippedDuplicates: Int
    var refreshedRuns: [RecordedRun] = []
    var completionRetries: [RecordedRun] = []
    var uploadRetries: [RecordedRun] = []
}

/// Separates changed data from completion retry eligibility. An unchanged Health read is not a refresh.
struct HealthKitImportBatch {
    var imported: [RecordedRun] = []
    var refreshed: [RecordedRun] = []
    var retries: [RecordedRun] = []
    var uploadRetries: [RecordedRun] = []
    var skipped = 0

    static func apply(_ runs: [RecordedRun], existing: [RecordedRun], isHidden: (RecordedRun) -> Bool,
                      save: (RecordedRun) -> Void) -> Self {
        var batch = Self()
        for run in runs {
            guard !isHidden(run) else { batch.skipped += 1; continue }
            if let stored = existing.first(where: { $0.source == .healthKit && $0.providerActivityID == run.providerActivityID }) {
                var merged = HealthKitImportMerge.merge(run, stored: stored)
                if merged != stored {
                    merged.healthUploadPending = true
                    save(merged)
                    batch.refreshed.append(merged)
                } else if merged.healthUploadPending == true {
                    batch.uploadRetries.append(merged)
                }
                // Retry exact completion even when the run data has not changed.
                if merged.plannedWorkoutID != nil, merged.healthPlanLookupFailed != true { batch.retries.append(merged) }
                batch.skipped += 1
            } else {
                var pending = run
                pending.healthUploadPending = true
                save(pending)
                batch.imported.append(pending)
            }
        }
        return batch
    }
}

/// Runs import side effects only for changed data; retry-only syncs can update the plan independently.
enum HealthKitImportProcessor {
    static func process(_ result: HealthKitImportResult,
                        upload: ([RecordedRun]) async -> Int,
                        complete: (RecordedRun) async -> Bool,
                        processNewest: (RecordedRun) async -> Void,
                        refreshRuns: () async -> Void,
                        notifyPlan: () async -> Void) async -> Int? {
        let changed = result.runs + result.refreshedRuns
        let newRuns = ActivityConsolidationService.consolidatedRuns(result.runs).sorted { $0.startedAt < $1.startedAt }
        var synced: Int?
        var completed = false
        let uploads = changed + result.uploadRetries
        if !uploads.isEmpty { synced = await upload(uploads) }
        if !changed.isEmpty {
            for run in newRuns.dropLast() {
                if await complete(run) { completed = true }
            }
            if let newest = newRuns.last { await processNewest(newest) }
            await refreshRuns()
        }
        for run in result.completionRetries {
            if await complete(run) { completed = true }
        }
        if !changed.isEmpty || completed { await notifyPlan() }
        return synced
    }
}

struct HealthKitWorkoutSnapshot {
    var uuid: UUID
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    var distanceMeters: Double?
    var averageHeartRateBPM: Int?
    var routePoints: [RunRoutePoint]
    var plannedWorkoutID: UUID? = nil
    var planLookupFailed: Bool = false
}

enum HealthKitRecordedRunMapper {
    static func recordedRun(from snapshot: HealthKitWorkoutSnapshot, syncedAt: Date = Date()) -> RecordedRun {
        let distance = max(0, snapshot.distanceMeters ?? 0)
        let movingTime = max(0, snapshot.duration)
        return RecordedRun(
            plannedWorkoutID: snapshot.plannedWorkoutID,
            healthPlanLookupFailed: snapshot.planLookupFailed,
            id: stableUUID(for: snapshot.uuid.uuidString),
            providerActivityID: snapshot.uuid.uuidString,
            source: .healthKit,
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
            distanceMeters: distance,
            movingTimeSeconds: movingTime,
            averagePaceSecondsPerKm: distance > 0 ? movingTime / (distance / 1_000) : 0,
            averageHeartRateBPM: snapshot.averageHeartRateBPM,
            routePoints: snapshot.routePoints,
            syncedAt: syncedAt
        )
    }

    static func stableUUID(for providerID: String) -> UUID {
        var hash = FNV1a64.offset
        for byte in providerID.utf8 {
            hash ^= UInt64(byte)
            hash &*= FNV1a64.prime
        }

        let high = hash
        var low = FNV1a64.offset
        for byte in String(providerID.reversed()).utf8 {
            low ^= UInt64(byte)
            low &*= FNV1a64.prime
        }

        let bytes: [UInt8] = [
            UInt8((high >> 56) & 0xff),
            UInt8((high >> 48) & 0xff),
            UInt8((high >> 40) & 0xff),
            UInt8((high >> 32) & 0xff),
            UInt8((high >> 24) & 0xff),
            UInt8((high >> 16) & 0xff),
            UInt8((high >> 8) & 0xff),
            UInt8(high & 0xff),
            UInt8((low >> 56) & 0xff),
            UInt8((low >> 48) & 0xff),
            UInt8((low >> 40) & 0xff),
            UInt8((low >> 32) & 0xff),
            UInt8((low >> 24) & 0xff),
            UInt8((low >> 16) & 0xff),
            UInt8((low >> 8) & 0xff),
            UInt8(low & 0xff)
        ]
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private enum FNV1a64 {
        static let offset: UInt64 = 0xcbf29ce484222325
        static let prime: UInt64 = 0x100000001b3
    }
}

enum HealthKitImportMerge {
    /// A slow upload must not clear a newer pending payload. Local notes/route matches are not
    /// part of the backend run insert; these provider-owned values are.
    static func uploadConfirms(_ uploaded: RecordedRun, stored: RecordedRun) -> Bool {
        persistedDate(uploaded.startedAt) == persistedDate(stored.startedAt) && uploaded.distanceMeters == stored.distanceMeters &&
        uploaded.movingTimeSeconds == stored.movingTimeSeconds &&
        uploaded.averagePaceSecondsPerKm == stored.averagePaceSecondsPerKm &&
        uploaded.averageHeartRateBPM == stored.averageHeartRateBPM
    }

    static func merge(_ incoming: RecordedRun, stored: RecordedRun) -> RecordedRun {
        var result = incoming.keepingLocalFields(from: stored)
        // RunSmartLocalStore's ISO8601 encoding stores whole seconds. Raw Health timestamps
        // can include fractions; compare at the persisted precision to avoid false refreshes.
        result.startedAt = persistedDate(result.startedAt)
        result.endedAt = persistedDate(result.endedAt)
        result.routePoints = result.routePoints.map { point in
            var normalized = point
            normalized.timestamp = persistedDate(point.timestamp)
            return normalized
        }
        if result.routePoints.count < stored.routePoints.count { result.routePoints = stored.routePoints }
        result.averageHeartRateBPM = incoming.averageHeartRateBPM ?? stored.averageHeartRateBPM
        result.syncedAt = stored.syncedAt
        result.consolidatedActivityID = stored.consolidatedActivityID
        // These fields are derived locally, absent in a raw Health snapshot. Preserve the route
        // match only while its geometry and distance inputs remain unchanged.
        if result.routePoints == stored.routePoints, result.distanceMeters == stored.distanceMeters {
            result.routeMatchResult = stored.routeMatchResult
        }
        return result
    }

    private static func persistedDate(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
    }
}

/// Whether to write a workout to Health, given what the duplicate check found.
enum HealthKitSavePolicy {
    /// Write only when Health is known not to hold this run. A failed query (nil) writes nothing:
    /// a duplicate workout in Health is worse than a run that is missing there.
    static func shouldWrite(alreadySaved: Bool?) -> Bool {
        alreadySaved == false
    }
}

/// Identity metadata is required for safe duplicate detection and reimport. A builder whose
/// collection or metadata step fails is discarded before optional samples or finish can run.
enum HealthKitWorkoutPreparation {
    static func run(
        beginCollection: () async throws -> Void,
        addMetadata: () async throws -> Void,
        discard: () -> Void
    ) async throws {
        do {
            try await beginCollection()
            try await addMetadata()
        } catch {
            discard()
            throw error
        }
    }
}

/// Lets one Health save per run id run at a time. A second save for the same run waits for the first,
/// then its duplicate check sees the first one's workout.
actor HealthKitSaveGate {
    static let shared = HealthKitSaveGate()

    private var running: Set<UUID> = []
    private var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ id: UUID) async {
        if running.contains(id) {
            await withCheckedContinuation { continuation in
                waiters[id, default: []].append(continuation)
            }
            // The previous holder handed its place over in `release`; `running` still contains the id.
        } else {
            running.insert(id)
        }
    }

    func release(_ id: UUID) {
        if var queue = waiters[id], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[id] = queue.isEmpty ? nil : queue
            next.resume()
        } else {
            running.remove(id)
        }
    }
}

struct HealthKitSyncService {
    static let providerName = "HealthKit"

    // Attribution policy: data read from HealthKit is attributed to "Apple Health" — its proximate
    // source — regardless of the originating device. "Garmin" attribution is reserved for data
    // obtained through the Garmin Connect API, so we never imply a Garmin API relationship for data
    // a user happened to sync into Apple Health. (Decision 2026-06-22; see Garmin brand guidelines.)

    func requestAccess() async -> ConnectedDeviceStatus {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return unavailableStatus(message: "Health data is not available on this device.")
        }

        let store = HKHealthStore()
        let shouldTrackPrompt: Bool
        do {
            shouldTrackPrompt = try await authorizationRequestStatus(for: store) == .shouldRequest
        } catch {
            // The authorization request still runs when the preflight lookup
            // fails. Keep the attempt observable rather than silently dropping
            // the only signal for a prompt that may still appear.
            shouldTrackPrompt = true
        }
        if shouldTrackPrompt {
            Analytics.trackPermissionRequested(kind: "healthkit")
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            let authorization = store.authorizationStatus(for: workoutType)
            if shouldTrackPrompt {
                Analytics.trackPermissionOutcome(
                    kind: "healthkit",
                    outcome: Self.permissionOutcome(for: authorization)
                )
            }
            // Sharing status says nothing about read access. Read-only usage is supported.
            return ConnectedDeviceStatus(
                provider: Self.providerName,
                state: .connected,
                lastSuccessfulSync: nil,
                permissions: [],
                message: "Health permission request finished. Sync to check for available running data. Read access is controlled in Health."
            )
        } catch {
            if shouldTrackPrompt {
                Analytics.trackPermissionOutcome(kind: "healthkit", outcome: .failed)
            }
            return ConnectedDeviceStatus(provider: Self.providerName, state: .error, lastSuccessfulSync: nil, permissions: [], message: error.localizedDescription)
        }
#else
        return unavailableStatus(message: "HealthKit is unavailable in this build.")
#endif
    }

#if canImport(HealthKit)
    static func permissionOutcome(for status: HKAuthorizationStatus) -> PermissionPromptOutcome {
        switch status {
        case .sharingAuthorized: .granted
        case .sharingDenied: .denied
        case .notDetermined: .dismissed
        @unknown default: .failed
        }
    }
#endif

    func importHealthData(localStore: RunSmartLocalStore, lookbackDays: Int = 180, limit: Int = 100) async -> HealthKitImportResult {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            let status = unavailableStatus(message: "Health data is not available on this device.")
            return HealthKitImportResult(status: status, runs: [], wellness: nil, skippedDuplicates: 0)
        }

        let status = await requestAccess()
        guard status.state == .connected else {
            return HealthKitImportResult(status: status, runs: [], wellness: nil, skippedDuplicates: 0)
        }

        let store = HKHealthStore()
        let existing = localStore.loadRuns()
        let localRunIDs = Set(existing.map(\.id))
        guard let runs = await readRecentRunningWorkouts(store: store, lookbackDays: lookbackDays, limit: limit, localRunIDs: localRunIDs) else {
            let failed = ConnectedDeviceStatus(provider: Self.providerName, state: .error, lastSuccessfulSync: nil,
                                               permissions: [], message: "Apple Health could not be read. Please try syncing again.")
            return HealthKitImportResult(status: failed, runs: [], wellness: nil, skippedDuplicates: 0)
        }
        let batch = HealthKitImportBatch.apply(runs, existing: existing,
                                              isHidden: localStore.isRunHidden, save: { localStore.stageHealthImport($0) })
        let imported = batch.imported
        let refreshed = batch.refreshed

        let wellness = await readDailySnapshot(store: store)
        if let wellness {
            localStore.saveHealthKitDailySnapshot(wellness)
        }

        let message = runs.isEmpty && wellness == nil
            ? "No readable Health workouts or daily data found. Check running data and read permissions in Health, then sync again."
            : "Imported \(imported.count) Health workouts. Refreshed \(refreshed.count) existing workouts."
        let importStatus = ConnectedDeviceStatus(
            provider: Self.providerName,
            state: .connected,
            lastSuccessfulSync: runs.isEmpty && wellness == nil ? nil : Date(),
            permissions: [],
            message: message
        )
        return HealthKitImportResult(status: importStatus, runs: imported, wellness: wellness, skippedDuplicates: batch.skipped, refreshedRuns: refreshed, completionRetries: batch.retries, uploadRetries: batch.uploadRetries)
#else
        let status = unavailableStatus(message: "HealthKit is unavailable in this build.")
        return HealthKitImportResult(status: status, runs: [], wellness: nil, skippedDuplicates: 0)
#endif
    }

    /// `allowPermissionPrompt` is true only for the save right after the runner finishes a run, where the
    /// prompt has context. A background save (a recovered run saved while a new run starts) writes with
    /// the permissions it already has and never shows the Health sheet.
    func save(_ run: RecordedRun, allowPermissionPrompt: Bool = true) async {
#if canImport(HealthKit)
        // Only RunSmart's own recordings go back to Health; imported runs came from there.
        guard run.source == .runSmart, HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        // No workout write access means the runner never connected Health: stay silent, as before.
        guard store.authorizationStatus(for: workoutType) == .sharingAuthorized else { return }

        // One save per run at a time: the second caller waits, then finds the first one's workout.
        await HealthKitSaveGate.shared.acquire(run.id)
        defer { Task { await HealthKitSaveGate.shared.release(run.id) } }

        // Runners who allowed the old set (workouts only) are asked for route, distance and
        // energy here, right after a run, never at launch. Anything they decline is left out.
        if allowPermissionPrompt, (try? await authorizationRequestStatus(for: store)) == .shouldRequest {
            _ = try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
        }

        guard HealthKitSavePolicy.shouldWrite(alreadySaved: await isAlreadySaved(run, store: store)) else { return }
        await writeWorkout(for: run, store: store)
#endif
    }

    /// Body mass is requested separately, in context from the calorie settings.
    /// A nil result covers unavailable/denied/no-data without inferring read consent.
    func readBodyMassKg(requestPermission: Bool) async -> Double? {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let store = HKHealthStore()
        if requestPermission {
            do {
                try await store.requestAuthorization(toShare: [], read: [type])
            } catch {
                return nil
            }
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: Date(), options: .strictEndDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
            }
            store.execute(query)
        }
#else
        return nil
#endif
    }

    private func unavailableStatus(message: String) -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: Self.providerName, state: .error, lastSuccessfulSync: nil, permissions: [], message: message)
    }
}

#if canImport(HealthKit)
private extension HealthKitSyncService {
    var workoutType: HKWorkoutType { HKObjectType.workoutType() }

    var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [workoutType, HKSeriesType.workoutRoute()]
        if let energy = optionalQuantity(.activeEnergyBurned) { types.insert(energy) }
        if let distance = optionalQuantity(.distanceWalkingRunning) { types.insert(distance) }
        return types
    }

    func canWrite(_ type: HKObjectType, store: HKHealthStore) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }

    /// True when Health already holds a workout written for this RunSmart run, false when it does not,
    /// nil when the query failed (so nothing is known).
    func isAlreadySaved(_ run: RecordedRun, store: HKHealthStore) async -> Bool? {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HealthKitWorkoutPlan.runIDMetadataKey,
            allowedValues: [run.id.uuidString]
        )
        guard let found = await queriedSamples(store: store, sampleType: workoutType, predicate: predicate, limit: 1, sortDescriptors: nil) else {
            return nil
        }
        return !found.isEmpty
    }

    /// Writes the workout, then its route. Each step stands alone: a failed route, energy
    /// or distance write never loses the workout.
    func writeWorkout(for run: RecordedRun, store: HKHealthStore) async {
        let plan = HealthKitWorkoutPlan.make(for: run)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        do {
            try await HealthKitWorkoutPreparation.run(
                beginCollection: { try await builder.beginCollection(at: plan.start) },
                addMetadata: { try await builder.addMetadata(HealthKitWorkoutPlan.metadata(for: run)) },
                discard: { builder.discardWorkout() }
            )
        } catch {
            return
        }

        if !plan.pauseEvents.isEmpty {
            let events = plan.pauseEvents.map { event in
                HKWorkoutEvent(
                    type: event.kind == .pause ? .pause : .resume,
                    dateInterval: DateInterval(start: event.date, duration: 0),
                    metadata: nil
                )
            }
            try? await builder.addWorkoutEvents(events)
        }

        var samples: [HKSample] = []
        if let type = optionalQuantity(.distanceWalkingRunning), canWrite(type, store: store) {
            samples += plan.distanceSamples.map { sample in
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .meter(), doubleValue: sample.meters),
                    start: sample.start,
                    end: sample.end
                )
            }
        }
        if let energy = plan.energy,
           let type = optionalQuantity(.activeEnergyBurned),
           canWrite(type, store: store) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy.kilocalories),
                start: energy.start,
                end: energy.end,
                metadata: [HealthKitWorkoutPlan.energyEstimateMetadataKey: true]
            ))
        }
        if !samples.isEmpty {
            try? await builder.addSamples(samples)
        }

        do {
            try await builder.endCollection(at: plan.end)
        } catch {
            return
        }
        guard let workout = try? await builder.finishWorkout() else { return }

        await writeRoute(plan.routeSegments, for: workout, runID: run.id, store: store)
    }

    func writeRoute(_ segments: [[RunRoutePoint]], for workout: HKWorkout, runID: UUID, store: HKHealthStore) async {
        guard !segments.isEmpty, canWrite(HKSeriesType.workoutRoute(), store: store) else { return }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        do {
            for segment in segments {
                try await routeBuilder.insertRouteData(segment.map(HealthKitWorkoutPlan.location(for:)))
            }
            _ = try await routeBuilder.finishRoute(
                with: workout,
                metadata: [HealthKitWorkoutPlan.runIDMetadataKey: runID.uuidString]
            )
        } catch {
            routeBuilder.discard()
        }
    }

    var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [workoutType]
        types.insert(HKSeriesType.workoutRoute())
        insertIfAvailable(optionalQuantity(.heartRate), into: &types)
        insertIfAvailable(optionalQuantity(.restingHeartRate), into: &types)
        insertIfAvailable(optionalQuantity(.heartRateVariabilitySDNN), into: &types)
        insertIfAvailable(optionalQuantity(.stepCount), into: &types)
        insertIfAvailable(optionalQuantity(.distanceWalkingRunning), into: &types)
        insertIfAvailable(optionalQuantity(.activeEnergyBurned), into: &types)
        insertIfAvailable(optionalCategory(.sleepAnalysis), into: &types)
        return types
    }

    var permissionLabels: [String] {
        ["Workouts", "Routes", "Heart Rate", "Resting HR", "HRV", "Steps", "Sleep", "Active Energy"]
    }

    func authorizationRequestStatus(for store: HKHealthStore) async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func optionalQuantity(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: identifier)
    }

    func optionalCategory(_ identifier: HKCategoryTypeIdentifier) -> HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: identifier)
    }

    func insertIfAvailable(_ objectType: HKObjectType?, into types: inout Set<HKObjectType>) {
        guard let objectType else { return }
        types.insert(objectType)
    }

    func readRecentRunningWorkouts(store: HKHealthStore, lookbackDays: Int, limit: Int, localRunIDs: Set<UUID>) async -> [RecordedRun]? {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let runPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runPredicate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        guard let samples = await queriedSamples(
            store: store,
            sampleType: workoutType,
            predicate: predicate,
            limit: limit,
            sortDescriptors: [sort]
        ) else { return nil }
        let workouts = samples as? [HKWorkout] ?? []

        var runs: [RecordedRun] = []
        for workout in workouts {
            // RunSmart wrote this one itself and still has the run. After a reinstall the run is
            // not stored locally, so the Health copy is imported (it is where the GPS comes back from).
            if HealthKitWorkoutPlan.isStoredLocally(metadata: workout.metadata, localRunIDs: localRunIDs) { continue }
            let heartRate = await averageHeartRateBPM(for: workout, store: store)
            let routePoints = await routePoints(for: workout, store: store)
            var planID: UUID?
            var planLookupFailed = false
            do { planID = try await workout.workoutPlan?.id }
            catch { planLookupFailed = true }
            let snapshot = HealthKitWorkoutSnapshot(
                uuid: workout.uuid,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                duration: workout.duration,
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
                averageHeartRateBPM: heartRate,
                routePoints: routePoints,
                plannedWorkoutID: planID,
                planLookupFailed: planLookupFailed
            )
            runs.append(HealthKitRecordedRunMapper.recordedRun(from: snapshot))
        }
        return runs
    }

    func averageHeartRateBPM(for workout: HKWorkout, store: HKHealthStore) async -> Int? {
        guard let type = optionalQuantity(.heartRate) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                guard let value = stats?.averageQuantity()?.doubleValue(for: unit), value.isFinite else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Int(value.rounded()))
            }
            store.execute(query)
        }
    }

    func routePoints(for workout: HKWorkout, store: HKHealthStore) async -> [RunRoutePoint] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routes = await samples(store: store, sampleType: HKSeriesType.workoutRoute(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) as? [HKWorkoutRoute] ?? []
        var points: [RunRoutePoint] = []
        for route in routes {
            points.append(contentsOf: await locations(for: route, store: store).enumerated().map { index, location in
                RunRoutePoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timestamp: location.timestamp,
                    horizontalAccuracy: location.horizontalAccuracy,
                    altitude: location.altitude,
                    startsNewSegment: index == 0
                )
            })
        }
        return points.sorted { $0.timestamp < $1.timestamp }
    }

    func locations(for route: HKWorkoutRoute, store: HKHealthStore) async -> [CLLocation] {
        await withCheckedContinuation { continuation in
            var locations: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, _ in
                if let batch {
                    locations.append(contentsOf: batch)
                }
                if done {
                    continuation.resume(returning: locations)
                }
            }
            store.execute(query)
        }
    }

    func readDailySnapshot(store: HKHealthStore) async -> HealthKitDailySnapshot? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = Date()

        async let steps = quantitySum(.stepCount, unit: .count(), start: start, end: end, store: store)
        async let activeEnergy = quantitySum(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end, store: store)
        async let restingHR = quantityAverage(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end, store: store)
        async let hrv = quantityAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: end, store: store)
        async let sleep = sleepDuration(start: calendar.date(byAdding: .day, value: -1, to: start) ?? start, end: end, store: store)

        let hrvValue = await hrv

        let snapshot = await HealthKitDailySnapshot(
            date: end,
            steps: steps.map { Int($0.rounded()) },
            restingHeartRateBPM: restingHR.map { Int($0.rounded()) },
            hrvMilliseconds: hrvValue,
            // Any HRV read from HealthKit is attributed to Apple Health (see policy note above).
            hrvSource: hrvValue != nil ? .appleHealth : .unknown,
            sleepSeconds: sleep,
            activeEnergyKilocalories: activeEnergy
        )

        if snapshot.steps == nil,
           snapshot.restingHeartRateBPM == nil,
           snapshot.hrvMilliseconds == nil,
           snapshot.sleepSeconds == nil,
           snapshot.activeEnergyKilocalories == nil {
            return nil
        }
        return snapshot
    }

    func quantitySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date, store: HKHealthStore) async -> Double? {
        guard let type = optionalQuantity(identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    func quantityAverage(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date, store: HKHealthStore) async -> Double? {
        guard let type = optionalQuantity(identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    func sleepDuration(start: Date, end: Date, store: HKHealthStore) async -> TimeInterval? {
        guard let type = optionalCategory(.sleepAnalysis) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples = await samples(store: store, sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) as? [HKCategorySample] ?? []
        let asleepValues = Set([
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ])
        let total = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return total > 0 ? total : nil
    }

    func samples(
        store: HKHealthStore,
        sampleType: HKSampleType,
        predicate: NSPredicate?,
        limit: Int,
        sortDescriptors: [NSSortDescriptor]?
    ) async -> [HKSample] {
        await queriedSamples(store: store, sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) ?? []
    }

    /// Like `samples`, but nil when the query reports an error, so a failed read is not mistaken for "no samples".
    func queriedSamples(
        store: HKHealthStore,
        sampleType: HKSampleType,
        predicate: NSPredicate?,
        limit: Int,
        sortDescriptors: [NSSortDescriptor]?
    ) async -> [HKSample]? {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }
}
#endif
