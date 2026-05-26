import Foundation
@preconcurrency import UserNotifications
import UIKit

enum RunSmartReminderType: String, CaseIterable, Codable, Hashable {
    case workoutDue
    case missedWorkoutRecovery
    case restDayRecovery
    case weeklyRecap

    var categoryIdentifier: String {
        "runsmart.\(rawValue)"
    }

    var defaultDestination: RunSmartNotificationDestination {
        switch self {
        case .workoutDue, .restDayRecovery:
            return .today
        case .missedWorkoutRecovery:
            return .plan
        case .weeklyRecap:
            return .report
        }
    }
}

enum RunSmartNotificationDestination: String, Codable, Hashable {
    case today
    case plan
    case report
}

struct RunSmartReminderContent: Hashable {
    var title: String
    var body: String

    static func content(for type: RunSmartReminderType, workoutTitle: String? = nil) -> RunSmartReminderContent {
        switch type {
        case .workoutDue:
            return RunSmartReminderContent(
                title: "Today's run is ready",
                body: "\(workoutTitle ?? "Your workout") is waiting when your day has room."
            )
        case .missedWorkoutRecovery:
            return RunSmartReminderContent(
                title: "Want to re-plan this run?",
                body: "Life moved. Open Plan to move the session or choose an easier next step."
            )
        case .restDayRecovery:
            return RunSmartReminderContent(
                title: "Recovery counts too",
                body: "Today is a good day to absorb the work. Check your plan when you are ready."
            )
        case .weeklyRecap:
            return RunSmartReminderContent(
                title: "Your weekly recap is ready",
                body: "Review the week, recent runs, and the next calm step."
            )
        }
    }
}

struct RunSmartReminderRequest: Hashable {
    var identifier: String
    var type: RunSmartReminderType
    var fireDate: Date
    var workoutID: UUID?
    var destination: RunSmartNotificationDestination
    var content: RunSmartReminderContent

    static func identifier(for type: RunSmartReminderType, workoutID: UUID? = nil) -> String {
        if let workoutID {
            return "runsmart.reminder.\(type.rawValue).\(workoutID.uuidString)"
        }
        return "runsmart.reminder.\(type.rawValue)"
    }
}

struct RunSmartReminderPlan: Hashable {
    var requests: [RunSmartReminderRequest]
    var shouldCancelExisting: Bool

    static func make(
        profile: OnboardingProfile,
        workouts: [WorkoutSummary],
        recentRuns: [RecordedRun],
        recovery: RecoverySnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RunSmartReminderPlan {
        guard profile.notificationsEnabled else {
            return RunSmartReminderPlan(requests: [], shouldCancelExisting: true)
        }

        let incomplete = workouts.filter { !$0.isComplete }.sorted { $0.scheduledDate < $1.scheduledDate }
        var requests: [RunSmartReminderRequest] = []

        if let dueWorkout = incomplete.first(where: { calendar.isDate($0.scheduledDate, inSameDayAs: now) || isTomorrow($0.scheduledDate, now: now, calendar: calendar) }) {
            let fireDate = reminderDate(for: dueWorkout.scheduledDate, hour: 8, minute: 0, calendar: calendar)
            if fireDate > now {
                requests.append(
                    request(
                        type: .workoutDue,
                        fireDate: fireDate,
                        workout: dueWorkout
                    )
                )
            }
        }

        if let missed = incomplete.first(where: { calendar.startOfDay(for: $0.scheduledDate) < calendar.startOfDay(for: now) }) {
            let fireDate = nextDate(from: now, hour: 18, minute: 30, calendar: calendar)
            requests.append(
                request(
                    type: .missedWorkoutRecovery,
                    fireDate: fireDate,
                    workout: missed,
                    destination: .plan
                )
            )
        }

        if shouldScheduleRecoveryReminder(workouts: workouts, now: now, calendar: calendar) {
            requests.append(
                request(
                    type: .restDayRecovery,
                    fireDate: nextDate(from: now, hour: 10, minute: 30, calendar: calendar),
                    workout: nil
                )
            )
        }

        requests.append(
            request(
                type: .weeklyRecap,
                fireDate: nextWeeklyRecapDate(after: now, calendar: calendar),
                workout: nil,
                destination: .report
            )
        )

        return RunSmartReminderPlan(requests: requests.uniqueByIdentifier(), shouldCancelExisting: false)
    }

    private static func request(
        type: RunSmartReminderType,
        fireDate: Date,
        workout: WorkoutSummary?,
        destination: RunSmartNotificationDestination? = nil
    ) -> RunSmartReminderRequest {
        RunSmartReminderRequest(
            identifier: RunSmartReminderRequest.identifier(for: type, workoutID: workout?.id),
            type: type,
            fireDate: fireDate,
            workoutID: workout?.id,
            destination: destination ?? type.defaultDestination,
            content: RunSmartReminderContent.content(for: type, workoutTitle: workout?.title)
        )
    }

    private static func isTomorrow(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }

    private static func reminderDate(for date: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? date
    }

    private static func nextDate(from now: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }

    private static func nextWeeklyRecapDate(after now: Date, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.weekday = 1
        components.hour = 18
        components.minute = 0
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now.addingTimeInterval(7 * 86_400)
    }

    private static func shouldScheduleRecoveryReminder(workouts: [WorkoutSummary], now: Date, calendar: Calendar) -> Bool {
        let today = workouts.filter { calendar.isDate($0.scheduledDate, inSameDayAs: now) }
        if today.isEmpty { return true }
        return today.allSatisfy { $0.kind == .recovery || $0.kind == .strength }
    }
}

@MainActor
final class PushService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushService()

    private let center: UNUserNotificationCenter
    private var navigationHandler: ((RunSmartNotificationDestination) -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
    }

    func configureNavigation(_ handler: @escaping (RunSmartNotificationDestination) -> Void) {
        navigationHandler = handler
        center.delegate = self
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    @discardableResult
    func scheduleReturnLoopReminders(
        profile: OnboardingProfile,
        workouts: [WorkoutSummary],
        recentRuns: [RecordedRun],
        recovery: RecoverySnapshot
    ) async -> [RunSmartReminderRequest] {
        let plan = RunSmartReminderPlan.make(profile: profile, workouts: workouts, recentRuns: recentRuns, recovery: recovery)
        if plan.shouldCancelExisting {
            cancelAllRunSmartReminders()
            return []
        }

        let granted: Bool
        do {
            granted = try await requestAuthorization()
        } catch {
            return []
        }
        guard granted else { return [] }

        cancelAllRunSmartReminders()
        for request in plan.requests {
            try? await center.add(request.notificationRequest)
        }
        return plan.requests
    }

    func cancelWorkoutReminder(workoutID: UUID) {
        let identifiers = RunSmartReminderType.allCases.map {
            RunSmartReminderRequest.identifier(for: $0, workoutID: workoutID)
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAllRunSmartReminders() {
        center.getPendingNotificationRequests { [center] requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("runsmart.reminder.") || $0.hasPrefix("runsmart.flexWeek.") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func schedulePlanAdjustmentConfirmation(
        workout: WorkoutSummary?,
        notificationsEnabled: Bool,
        planAdjustmentConfirmationsEnabled: Bool
    ) async {
        guard notificationsEnabled, planAdjustmentConfirmationsEnabled else { return }
        guard UIApplication.shared.applicationState != .active else { return }

        let granted: Bool
        do {
            granted = try await requestAuthorization()
        } catch {
            return
        }
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your week is updated"
        if let workout, PlanPresentationModels.isWorkout(workout) {
            content.body = "Tomorrow: \(workout.title.lowercased()) · \(workout.distance) — tap to see your plan."
        } else if let workout {
            content.body = "Tomorrow: rest day — tap to see your updated week."
        } else {
            content.body = "Tap to see tomorrow's updated workout."
        }
        content.sound = .default
        content.userInfo = [
            "type": "plan_adjustment_confirmation",
            "destination": RunSmartNotificationDestination.plan.rawValue
        ]

        let fireDate = Date().addingTimeInterval(30)
        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let request = UNNotificationRequest(
            identifier: "runsmart.flexWeek.confirmation",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        )
        try? await center.add(request)
    }

    func cancelPlanAdjustmentConfirmation() {
        center.removePendingNotificationRequests(withIdentifiers: ["runsmart.flexWeek.confirmation"])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let destinationValue = response.notification.request.content.userInfo["destination"] as? String
        let destination = destinationValue.flatMap(RunSmartNotificationDestination.init(rawValue:)) ?? .today
        await MainActor.run {
            navigationHandler?(destination)
        }
    }
}

private extension RunSmartReminderRequest {
    var notificationRequest: UNNotificationRequest {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = content.title
        notificationContent.body = content.body
        notificationContent.sound = .default
        notificationContent.categoryIdentifier = type.categoryIdentifier
        notificationContent.userInfo = [
            "type": type.rawValue,
            "destination": destination.rawValue,
            "workoutID": workoutID?.uuidString ?? ""
        ]

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        return UNNotificationRequest(
            identifier: identifier,
            content: notificationContent,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        )
    }
}

private extension Array where Element == RunSmartReminderRequest {
    func uniqueByIdentifier() -> [RunSmartReminderRequest] {
        var seen = Set<String>()
        return filter { request in
            guard !seen.contains(request.identifier) else { return false }
            seen.insert(request.identifier)
            return true
        }
    }
}
