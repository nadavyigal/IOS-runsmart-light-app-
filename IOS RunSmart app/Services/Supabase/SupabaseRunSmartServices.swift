import Foundation
import SwiftUI
import Supabase
import MapKit

// MARK: - SupabaseRunSmartServices

final class SupabaseRunSmartServices: RunSmartServiceProviding {
    static let shared = SupabaseRunSmartServices()

    private let supabase = SupabaseManager.client
    private let planRepo = TrainingPlanRepository()
    private let healthSync = HealthKitSyncService()
    private let store = RunSmartLocalStore.shared

    private var currentUserID: UUID? { supabase.auth.currentUser?.id }

    // MARK: TodayProviding

    func todayRecommendation() async -> TodayRecommendation {
        guard let userID = currentUserID else {
            return TodayRecommendation.placeholder
        }

        async let profileTask = fetchProfile(userID: userID)
        async let metricsTask = latestGarminMetrics(userID: userID)
        async let streakTask = fetchStreak(userID: userID)

        let (dbProfile, metrics, streak) = await (profileTask, metricsTask, streakTask)
        guard dbProfile != nil else { return TodayRecommendation.placeholder }

        // plans/conversations link via auth UUID (plans.profile_id = auth.uid())
        let activePlan = await planRepo.activePlan(profileID: userID)
        let todayWorkout = activePlan?.todayWorkout

        let readiness: Int
        let readinessLabel: String

        if let bb = metrics?.bodyBattery {
            readiness = min(100, bb)
            readinessLabel = bb > 70 ? "Ready to train" : bb > 40 ? "Moderate energy" : "Low energy — easy day"
        } else {
            let weeklyKm = activePlan?.completedKmThisWeek ?? 0
            readiness = min(95, max(55, 72 + min(18, Int(weeklyKm))))
            readinessLabel = readiness > 80 ? "Ready to train" : "Moderate"
        }

        let coachMessage = await latestCoachMessage(profileID: userID)
            ?? "Ready for your next run. Let's make today count."

        let weeklyDone = String(format: "%.1f", Double(activePlan?.completedKmThisWeek ?? 0.0))
        let weeklyTotal = String(format: "%.1f", Double(activePlan?.totalKmThisWeek ?? 0.0))
        let streakDays = streak?.currentStreak ?? 0
        let sleepHours = metrics?.sleepDurationS.map {
            let totalSeconds = Int($0)
            return String(format: "%dh %02dm", Int32(totalSeconds / 3600), Int32((totalSeconds % 3600) / 60))
        } ?? "--"
        let hrvLabel = metrics?.hrv != nil ? (metrics!.hrv! > 50 ? "Stable" : "Lower") : "--"

        return TodayRecommendation(
            readiness: readiness,
            readinessLabel: readinessLabel,
            workoutTitle: todayWorkout?.workoutTitle ?? "Rest Day",
            distance: todayWorkout.map { String(format: "%.1f km", $0.distance) } ?? "--",
            pace: todayWorkout?.paceLabel ?? "--:--",
            elevation: "--",
            coachMessage: coachMessage,
            weeklyProgress: "\(weeklyDone) / \(weeklyTotal) km",
            streak: "\(streakDays) days",
            recovery: sleepHours,
            hrv: hrvLabel
        )
    }

    // MARK: PlanProviding

    func weeklyPlan() async -> [WorkoutSummary] {
        guard let userID = currentUserID else { return [] }
        guard let activePlan = await planRepo.activePlan(profileID: userID) else { return [] }
        return activePlan.currentWeekWorkouts.map { $0.toWorkoutSummary() }
    }

    // MARK: CoachChatting

    func recentMessages() async -> [CoachMessage] {
        guard let userID = currentUserID else { return [] }
        do {
            let conversations: [DBConversation] = try await supabase
                .from("conversations")
                .select()
                .eq("profile_id", value: userID.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let conv = conversations.first else { return [] }

            let messages: [DBMessage] = try await supabase
                .from("conversation_messages")
                .select()
                .eq("conversation_id", value: conv.id.uuidString)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value

            return messages.reversed().map { msg in
                CoachMessage(
                    text: msg.content,
                    time: formatRelativeTime(msg.createdAt),
                    isUser: msg.role == "user"
                )
            }
        } catch {
            if !(error is CancellationError) {
                print("[SupabaseServices] recentMessages error:", error)
            }
            return []
        }
    }

    func send(message: String) async -> CoachMessage {
        CoachMessage(text: message, time: "Just now", isUser: true)
    }

    // MARK: ProfileProviding

    func runnerProfile() async -> RunnerProfile {
        guard let userID = currentUserID,
              let profile = await fetchProfile(userID: userID) else {
            return RunnerProfile(name: "Runner", goal: "--", streak: "--", level: "--", totalRuns: 0, totalDistance: 0, totalTime: "--")
        }

        async let streakTask = fetchStreak(userID: userID)
        async let activitiesTask = GarminBridge.shared.recentActivities(authUserID: userID, limit: 200)
        let (streak, activities) = await (streakTask, activitiesTask)

        let localRuns = store.loadRuns()
        let totalRuns = activities.count + localRuns.count
        let totalMeters = activities.reduce(0.0) { $0 + ($1.distanceM ?? 0) } + localRuns.reduce(0.0) { $0 + $1.distanceMeters }
        let totalSeconds = activities.reduce(0.0) { $0 + ($1.durationS ?? 0) } + localRuns.reduce(0.0) { $0 + $1.movingTimeSeconds }
        let totalTime = formatTotalTime(seconds: totalSeconds)

        return RunnerProfile(
            name: profile.name ?? "Runner",
            goal: profile.goal.capitalized,
            streak: "\(streak?.currentStreak ?? 0) day streak",
            level: profile.experience.capitalized,
            totalRuns: totalRuns,
            totalDistance: Int(totalMeters / 1000),
            totalTime: totalTime
        )
    }

    private func formatTotalTime(seconds: Double) -> String {
        guard seconds > 0 else { return "--" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        return String(format: "%dh %02dm", hours, minutes)
    }

    func achievements() async -> [Achievement] {
        let runs = await recentRuns()
        guard !runs.isEmpty else { return [] }
        let totalKm = runs.reduce(0.0) { $0 + $1.distanceMeters } / 1_000
        let longestKm = (runs.map(\.distanceMeters).max() ?? 0) / 1_000
        return [
            Achievement(title: "Total Volume", subtitle: "\(Int(totalKm.rounded())) km", symbol: "chart.bar.fill", tint: Color.lime),
            Achievement(title: "Longest Run", subtitle: String(format: "%.1f km", longestKm), symbol: "flag.checkered", tint: .orange),
            Achievement(title: "Manual Logs", subtitle: "\(runs.filter { $0.source == .runSmart }.count)", symbol: "plus.circle.fill", tint: .cyan)
        ]
    }

    // MARK: RunLogging

    func currentRunMetrics() async -> [MetricTile] {
        guard let last = await recentRuns().first else { return [] }
        return [
            MetricTile(title: "Distance", value: String(format: "%.2f", last.distanceMeters / 1_000), unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
            MetricTile(title: "Pace", value: RunRecorder.paceLabel(secondsPerKm: last.averagePaceSecondsPerKm), unit: "/km", symbol: "timer", tint: Color.lime),
            MetricTile(title: "Time", value: RunRecorder.timeLabel(last.movingTimeSeconds), unit: "", symbol: "stopwatch", tint: .white),
            MetricTile(title: "Source", value: last.source.rawValue, unit: "", symbol: "sensor.tag.radiowaves.forward", tint: .cyan)
        ]
    }

    func recentRuns() async -> [RecordedRun] {
        var runs = store.loadRuns()
        if let userID = currentUserID {
            let garminRuns = await GarminBridge.shared
                .recentActivities(authUserID: userID, limit: 100)
                .compactMap { $0.toRecordedRun() }
            runs.append(contentsOf: garminRuns)
        }

        var seen = Set<String>()
        return runs
            .sorted { $0.startedAt > $1.startedAt }
            .filter { run in
                let key = run.providerActivityID ?? run.id.uuidString
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
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

    // MARK: RouteProviding

    func routeSuggestions() async -> [RouteSuggestion] {
        guard let userID = currentUserID else { return [] }
        let activities = await GarminBridge.shared.recentActivities(authUserID: userID, limit: 30)
        // Bucket by rounded distance (in km), keep one representative per bucket.
        let buckets = [3, 5, 8, 10, 15]
        var pickedByBucket: [Int: DBGarminActivity] = [:]
        for activity in activities {
            guard let m = activity.distanceM, m > 0 else { continue }
            let km = m / 1000
            let bucket = buckets.min(by: { abs(Double($0) - km) < abs(Double($1) - km) }) ?? Int(km.rounded())
            if pickedByBucket[bucket] == nil {
                pickedByBucket[bucket] = activity
            }
        }
        return pickedByBucket
            .sorted(by: { $0.key < $1.key })
            .compactMap { (bucket, activity) -> RouteSuggestion? in
                guard let m = activity.distanceM else { return nil }
                let km = m / 1000
                let elevation = Int(activity.elevationGainM ?? 0)
                let durationS = activity.durationS ?? (km * 360)
                return RouteSuggestion(
                    id: "garmin-\(activity.id)",
                    name: "\(bucket)K · from Garmin",
                    distanceKm: km,
                    elevationGainMeters: elevation,
                    estimatedDurationMinutes: Int(durationS / 60),
                    points: [],
                    kind: .past
                )
            }
    }

    func nearbyLoopRoutes(around coordinate: CLLocationCoordinate2D, distancesKm: [Double]) async -> [RouteSuggestion] {
        var suggestions: [RouteSuggestion] = []
        for distanceKm in distancesKm {
            if let route = await generatedLoopRoute(around: coordinate, distanceKm: distanceKm) {
                suggestions.append(route)
            }
        }
        return suggestions
    }

    // MARK: DeviceSyncing

    func deviceStatuses() async -> [ConnectedDeviceStatus] {
        guard let userID = currentUserID else {
            return [
                ConnectedDeviceStatus(provider: "Garmin Connect", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil),
                ConnectedDeviceStatus(provider: "HealthKit", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Tap Connect to grant HealthKit access.")
            ]
        }

        let garmin = await fetchGarminConnection(userID: userID)
        let health = ConnectedDeviceStatus(
            provider: "HealthKit",
            state: .disconnected,
            lastSuccessfulSync: nil,
            permissions: [],
            message: "Tap Connect to grant HealthKit access."
        )
        return [garmin, health]
    }

    func connect(provider: String) async -> ConnectedDeviceStatus {
        guard provider == "Garmin Connect" else {
            return await healthSync.requestAccess()
        }
        do {
            try await GarminBridge.shared.connect()
        } catch {
            print("[SupabaseServices] Garmin connect error:", error)
        }
        if let userID = currentUserID {
            return await fetchGarminConnection(userID: userID)
        }
        return ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil)
    }

    func syncNow(provider: String) async -> ConnectedDeviceStatus {
        guard let userID = currentUserID else {
            return ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil)
        }
        if provider == "Garmin Connect" {
            return await fetchGarminConnection(userID: userID)
        }
        return await healthSync.requestAccess()
    }

    func disconnect(provider: String) async -> ConnectedDeviceStatus {
        ConnectedDeviceStatus(provider: provider, state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: "Disconnected")
    }

    // MARK: HealthSyncing

    func requestHealthAccess() async -> ConnectedDeviceStatus {
        await healthSync.requestAccess()
    }

    func saveToHealth(_ run: RecordedRun) async {
        await healthSync.save(run)
    }

    // MARK: Private helpers

    private func fetchProfile(userID: UUID) async -> DBProfile? {
        do {
            let rows: [DBProfile] = try await supabase
                .from("profiles")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch { return nil }
    }

    private func latestGarminMetrics(userID: UUID) async -> DBGarminDailyMetrics? {
        do {
            let rows: [DBGarminDailyMetrics] = try await supabase
                .from("garmin_daily_metrics")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .order("date", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch { return nil }
    }

    private func fetchStreak(userID: UUID) async -> DBUserStreak? {
        do {
            let rows: [DBUserStreak] = try await supabase
                .from("user_streaks")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch { return nil }
    }

    private func fetchGarminConnection(userID: UUID) async -> ConnectedDeviceStatus {
        do {
            let rows: [DBGarminConnection] = try await supabase
                .from("garmin_connections")
                .select()
                .eq("auth_user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value

            if let conn = rows.first {
                let lastSync = conn.lastSyncAt.flatMap { parseISO8601Date($0) }
                let state: DeviceConnectionState = conn.status == "connected" ? .connected : .disconnected
                return ConnectedDeviceStatus(
                    provider: "Garmin Connect",
                    state: state,
                    lastSuccessfulSync: lastSync,
                    permissions: conn.scopes ?? [],
                    message: nil
                )
            }
        } catch {}
        return ConnectedDeviceStatus(provider: "Garmin Connect", state: .disconnected, lastSuccessfulSync: nil, permissions: [], message: nil)
    }

    private func latestCoachMessage(profileID: UUID) async -> String? {
        do {
            let conversations: [DBConversation] = try await supabase
                .from("conversations")
                .select()
                .eq("profile_id", value: profileID.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let conv = conversations.first else { return nil }

            let messages: [DBMessage] = try await supabase
                .from("conversation_messages")
                .select()
                .eq("conversation_id", value: conv.id.uuidString)
                .eq("role", value: "assistant")
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return messages.first?.content
        } catch { return nil }
    }

    private func generatedLoopRoute(around coordinate: CLLocationCoordinate2D, distanceKm: Double) async -> RouteSuggestion? {
        let bearings = [0.0, 120.0, 240.0]
        var closest: RouteSuggestion?
        var closestDelta = Double.greatestFiniteMagnitude

        for bearing in bearings {
            guard let candidate = await outAndBackRoute(around: coordinate, distanceKm: distanceKm, bearingDegrees: bearing) else {
                continue
            }
            let delta = abs(candidate.distanceKm - distanceKm)
            if delta / distanceKm <= 0.15 {
                return candidate
            }
            if delta < closestDelta {
                closest = candidate
                closestDelta = delta
            }
        }

        return closest
    }

    private func outAndBackRoute(around coordinate: CLLocationCoordinate2D, distanceKm: Double, bearingDegrees: Double) async -> RouteSuggestion? {
        let midpoint = coordinate.destination(distanceMeters: distanceKm * 500, bearingDegrees: bearingDegrees)
        do {
            async let outboundTask = directions(from: coordinate, to: midpoint)
            async let inboundTask = directions(from: midpoint, to: coordinate)
            let (outbound, inbound) = try await (outboundTask, inboundTask)
            let totalMeters = outbound.distance + inbound.distance
            guard totalMeters > 0 else { return nil }
            let coordinates = outbound.polyline.coordinates + inbound.polyline.coordinates.dropFirst()
            guard coordinates.count >= 2 else { return nil }
            let points = coordinates.enumerated().map { index, coord in
                RunRoutePoint(
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    timestamp: Date().addingTimeInterval(Double(index)),
                    horizontalAccuracy: 0,
                    altitude: nil
                )
            }
            let actualKm = totalMeters / 1000
            return RouteSuggestion(
                id: "nearby-\(Int(distanceKm * 10))-\(Int(bearingDegrees))-\(coordinate.latitude)-\(coordinate.longitude)",
                name: "\(Int(distanceKm.rounded()))K loop · nearby",
                distanceKm: actualKm,
                elevationGainMeters: 0,
                estimatedDurationMinutes: max(1, Int((actualKm * 360).rounded() / 60)),
                points: points,
                kind: .generated
            )
        } catch {
            return nil
        }
    }

    private func directions(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .walking
        request.requestsAlternateRoutes = true
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.distance < $1.distance }) else {
            throw MKError(.directionsNotFound)
        }
        return route
    }

    private func formatRelativeTime(_ isoString: String?) -> String {
        guard let str = isoString, let date = parseISO8601Date(str) else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "Just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }

    private func parseISO8601Date(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: str) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: str)
    }
}

private extension CLLocationCoordinate2D {
    func destination(distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let radius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let angularDistance = distanceMeters / radius

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}

// MARK: - TodayRecommendation with extra stats

extension TodayRecommendation {
    static let placeholder = TodayRecommendation(
        readiness: 0,
        readinessLabel: "Loading",
        workoutTitle: "Loading",
        distance: "--",
        pace: "--:--",
        elevation: "--",
        coachMessage: "Loading your training data…"
    )
}
