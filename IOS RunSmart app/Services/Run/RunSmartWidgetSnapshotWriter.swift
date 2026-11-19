import Combine
import Foundation
import WidgetKit

/// Keeps the App Group widget snapshot current: week distance from saved runs, the week goal
/// from the active plan, and whether a run is live. Reloads the widget only when the
/// snapshot actually changed.
@MainActor
final class RunSmartWidgetSnapshotWriter: ObservableObject {
    private let snapshotStore: RunSmartWidgetSnapshotStore
    private let runs: () -> [RecordedRun]
    private let reloadWidget: () -> Void
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    private var isBound = false
    private var isRunInProgress = false

    init(
        snapshotStore: RunSmartWidgetSnapshotStore = .shared,
        runs: @escaping () -> [RecordedRun] = { RunSmartLocalStore.shared.loadRuns() },
        reloadWidget: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: RunSmartWidgetSnapshotStore.widgetKind) },
        calendar: Calendar = .current
    ) {
        self.snapshotStore = snapshotStore
        self.runs = runs
        self.reloadWidget = reloadWidget
        self.calendar = calendar
    }

    /// Follows run start, finish and discard. Bound once by the app shell.
    func bind(recorder: RunRecorder) {
        guard !isBound else { return }
        isBound = true
        recorder.$phase
            .map { $0 == .recording || $0 == .paused }
            .removeDuplicates()
            .sink { [weak self] live in
                MainActor.assumeIsolated { self?.refresh(isRunInProgress: live) }
            }
            .store(in: &cancellables)
        recorder.$lastSavedRun
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            .store(in: &cancellables)
    }

    func refresh(isRunInProgress: Bool? = nil, now: Date = Date()) {
        if let isRunInProgress { self.isRunInProgress = isRunInProgress }
        guard snapshotStore.isAvailable else { return }
        let weekStart = Self.weekStart(for: now, calendar: calendar)
        let previous = snapshotStore.load()
        let carriedGoal = previous?.weekStart == weekStart ? previous?.weekGoalMeters : nil
        let next = RunSmartWidgetSnapshot(
            updatedAt: now,
            weekStart: weekStart,
            weekDistanceMeters: Self.weekDistanceMeters(runs: runs(), weekStart: weekStart, calendar: calendar),
            weekGoalMeters: carriedGoal,
            isRunInProgress: self.isRunInProgress
        )
        write(next, previous: previous)
    }

    /// Called where the active plan's week total is computed (Today load).
    func recordWeekGoal(kilometers: Double?, now: Date = Date()) {
        guard snapshotStore.isAvailable else { return }
        let weekStart = Self.weekStart(for: now, calendar: calendar)
        let previous = snapshotStore.load()
        var next = previous?.weekStart == weekStart ? previous! : RunSmartWidgetSnapshot(
            updatedAt: now,
            weekStart: weekStart,
            weekDistanceMeters: Self.weekDistanceMeters(runs: runs(), weekStart: weekStart, calendar: calendar),
            weekGoalMeters: nil,
            isRunInProgress: isRunInProgress
        )
        next.weekGoalMeters = kilometers.flatMap { $0 > 0 ? $0 * 1_000 : nil }
        next.updatedAt = now
        write(next, previous: previous)
    }

    private func write(_ next: RunSmartWidgetSnapshot, previous: RunSmartWidgetSnapshot?) {
        var comparable = previous
        comparable?.updatedAt = next.updatedAt
        guard comparable != next else { return }
        snapshotStore.save(next)
        reloadWidget()
    }

    nonisolated static func weekStart(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    nonisolated static func weekDistanceMeters(runs: [RecordedRun], weekStart: Date, calendar: Calendar) -> Double {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { return 0 }
        return runs.filter { week.contains($0.startedAt) }.reduce(0) { $0 + max(0, $1.distanceMeters) }
    }
}

extension RunSmartWidgetSnapshotWriter {
    /// One writer for the app, shared by the app shell and the services that know the plan.
    static let shared = RunSmartWidgetSnapshotWriter()
}
