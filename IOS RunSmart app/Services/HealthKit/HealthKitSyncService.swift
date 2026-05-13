import Foundation
import CoreLocation
#if canImport(HealthKit)
import HealthKit
#endif

struct HealthKitDailySnapshot: Codable, Hashable {
    var date: Date
    var steps: Int?
    var restingHeartRateBPM: Int?
    var hrvMilliseconds: Double?
    var sleepSeconds: TimeInterval?
    var activeEnergyKilocalories: Double?
}

struct HealthKitImportResult {
    var status: ConnectedDeviceStatus
    var runs: [RecordedRun]
    var wellness: HealthKitDailySnapshot?
    var skippedDuplicates: Int
}

struct HealthKitWorkoutSnapshot {
    var uuid: UUID
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    var distanceMeters: Double?
    var averageHeartRateBPM: Int?
    var routePoints: [RunRoutePoint]
}

enum HealthKitRecordedRunMapper {
    static func recordedRun(from snapshot: HealthKitWorkoutSnapshot, syncedAt: Date = Date()) -> RecordedRun {
        let distance = max(0, snapshot.distanceMeters ?? 0)
        let movingTime = max(0, snapshot.duration)
        return RecordedRun(
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

struct HealthKitSyncService {
    static let providerName = "HealthKit"

    func requestAccess() async -> ConnectedDeviceStatus {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return unavailableStatus(message: "Health data is not available on this device.")
        }

        let store = HKHealthStore()
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            return ConnectedDeviceStatus(
                provider: Self.providerName,
                state: .connected,
                lastSuccessfulSync: nil,
                permissions: permissionLabels,
                message: "Health access granted. Sync to import recent running data."
            )
        } catch {
            return ConnectedDeviceStatus(provider: Self.providerName, state: .error, lastSuccessfulSync: nil, permissions: [], message: error.localizedDescription)
        }
#else
        return unavailableStatus(message: "HealthKit is unavailable in this build.")
#endif
    }

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
        let existingKeys = Set(localStore.loadRuns().compactMap { run -> String? in
            guard run.source == .healthKit, let providerID = run.providerActivityID else { return nil }
            return providerID
        })

        let runs = await readRecentRunningWorkouts(store: store, lookbackDays: lookbackDays, limit: limit)
        var imported: [RecordedRun] = []
        var skipped = 0
        for run in runs {
            guard !localStore.isRunHidden(run) else {
                skipped += 1
                continue
            }
            if let providerID = run.providerActivityID, existingKeys.contains(providerID) {
                skipped += 1
                continue
            }
            localStore.saveRun(run)
            imported.append(run)
        }

        let wellness = await readDailySnapshot(store: store)
        if let wellness {
            localStore.saveHealthKitDailySnapshot(wellness)
        }

        let message = "Imported \(imported.count) Health workouts" + (skipped > 0 ? " and skipped \(skipped) already saved or hidden." : ".")
        let importStatus = ConnectedDeviceStatus(
            provider: Self.providerName,
            state: .connected,
            lastSuccessfulSync: Date(),
            permissions: permissionLabels,
            message: message
        )
        return HealthKitImportResult(status: importStatus, runs: imported, wellness: wellness, skippedDuplicates: skipped)
#else
        let status = unavailableStatus(message: "HealthKit is unavailable in this build.")
        return HealthKitImportResult(status: status, runs: [], wellness: nil, skippedDuplicates: 0)
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
            metadata: [
                "RunSmartSource": run.source.rawValue,
                "RunSmartRunID": run.id.uuidString
            ]
        )
        try? await store.save(workout)
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
        [workoutType]
    }

    var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [workoutType]
        types.insert(HKSeriesType.workoutRoute())
        optionalQuantity(.heartRate).map { types.insert($0) }
        optionalQuantity(.restingHeartRate).map { types.insert($0) }
        optionalQuantity(.heartRateVariabilitySDNN).map { types.insert($0) }
        optionalQuantity(.stepCount).map { types.insert($0) }
        optionalQuantity(.distanceWalkingRunning).map { types.insert($0) }
        optionalQuantity(.activeEnergyBurned).map { types.insert($0) }
        optionalCategory(.sleepAnalysis).map { types.insert($0) }
        return types
    }

    var permissionLabels: [String] {
        ["Workouts", "Routes", "Heart Rate", "Resting HR", "HRV", "Steps", "Sleep", "Active Energy"]
    }

    func optionalQuantity(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: identifier)
    }

    func optionalCategory(_ identifier: HKCategoryTypeIdentifier) -> HKCategoryType? {
        HKObjectType.categoryType(forIdentifier: identifier)
    }

    func readRecentRunningWorkouts(store: HKHealthStore, lookbackDays: Int, limit: Int) async -> [RecordedRun] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let runPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runPredicate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let workouts = await samples(
            store: store,
            sampleType: workoutType,
            predicate: predicate,
            limit: limit,
            sortDescriptors: [sort]
        ) as? [HKWorkout] ?? []

        var runs: [RecordedRun] = []
        for workout in workouts {
            let heartRate = await averageHeartRateBPM(for: workout, store: store)
            let routePoints = await routePoints(for: workout, store: store)
            let snapshot = HealthKitWorkoutSnapshot(
                uuid: workout.uuid,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                duration: workout.duration,
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
                averageHeartRateBPM: heartRate,
                routePoints: routePoints
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
        let routes = await samples(store: store, sampleType: HKSeriesType.workoutRoute(), predicate: predicate, limit: 5, sortDescriptors: nil) as? [HKWorkoutRoute] ?? []
        var points: [RunRoutePoint] = []
        for route in routes {
            points.append(contentsOf: await locations(for: route, store: store).map { location in
                RunRoutePoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timestamp: location.timestamp,
                    horizontalAccuracy: location.horizontalAccuracy,
                    altitude: location.altitude
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

        let snapshot = await HealthKitDailySnapshot(
            date: end,
            steps: steps.map { Int($0.rounded()) },
            restingHeartRateBPM: restingHR.map { Int($0.rounded()) },
            hrvMilliseconds: hrv,
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
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }
}
#endif
