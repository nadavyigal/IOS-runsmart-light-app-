import Combine
import SwiftUI

@MainActor
final class CoachAthleteListModel: ObservableObject {
    @Published private(set) var rows: [CoachAthleteRow] = []
    @Published private(set) var updatedAt: Date?
    @Published private(set) var failure = false
    @Published private(set) var offline = false
    /// C7.0: what the v2 gate says for this coach. `.off` keeps the roster exactly as in 1.2.6.
    @Published private(set) var coachV2: CoachV2State = .off
    /// C7.0 AC6: athletes the server reports as not v2-capable. Only filled while v2 is on.
    @Published private(set) var athletesNeedingUpdate: Set<UUID> = []
    private let service: any CoachReadServing
    private let rosterStatus: @Sendable () async throws -> [UUID: Bool]
    private(set) var ownerID: UUID?
    private var generation = 0
    private var loading = false

    init(
        service: any CoachReadServing = CoachReadService(),
        rosterStatus: @escaping @Sendable () async throws -> [UUID: Bool] = {
            try await SupabaseCoachV2GateRepository().rosterStatus()
        }
    ) {
        self.service = service
        self.rosterStatus = rosterStatus
    }

    /// Called when `CoachV2Gate.state` changes. Off or paused makes no v2 call.
    func applyCoachV2(_ state: CoachV2State) async {
        coachV2 = state
        guard state == .on, ownerID != nil, updatedAt != nil else {
            athletesNeedingUpdate = []
            return
        }
        await loadCoachV2Status(generation: generation)
    }

    private func loadCoachV2Status(generation current: Int) async {
        do {
            let status = try await rosterStatus()
            guard current == generation, coachV2 == .on else { return }
            // Only an explicit false shows the line. A missing row is unknown, not "old app".
            athletesNeedingUpdate = Set(rows.map(\.id).filter { status[$0] == false })
        } catch {
            guard current == generation, !(error is CancellationError) else { return }
            athletesNeedingUpdate = []
        }
    }

    func reset(for owner: UUID?) {
        guard ownerID != owner else { return }
        ownerID = owner
        generation += 1
        rows = []
        updatedAt = nil
        failure = false
        offline = false
        loading = false
        athletesNeedingUpdate = []
    }

    func refresh(owner: UUID, now: Date = .now) async {
        reset(for: owner)
        guard !loading else { return }
        loading = true
        let current = generation
        defer { if current == generation { loading = false } }
        failure = false
        offline = false

        do {
            let athletes = try await service.listAthletes()
            try Task.checkCancellation()
            guard current == generation else { return }
            let ids = athletes.map(\.athleteID)
            let active = Set(ids)
            rows.removeAll { !active.contains($0.id) }
            if ids.isEmpty {
                updatedAt = now
                return
            }

            let week = CoachAthleteWeek(now: now)
            async let planned = service.workouts(
                from: week.interval.start, to: week.lastDay, athleteIDs: ids, calendar: week.calendar
            )
            // The server filters run dates in UTC. Fetch the boundary dates and then use the coach's week.
            async let recorded = service.runs(
                from: week.interval.start, to: now, athleteIDs: ids, calendar: .coachRunUTC
            )
            let (workouts, runs) = try await (planned, recorded)
            let weeklyRuns = runs.filter { week.contains($0.completedAt) && $0.completedAt <= now }
            let recentIDs = Set(weeklyRuns.map(\.athleteID))
            var latest: [UUID: Date] = [:]
            for id in ids where !recentIDs.contains(id) {
                try Task.checkCancellation()
                guard current == generation else { return }
                latest[id] = try await service.latestRun(for: id, through: now)?.completedAt
            }

            try Task.checkCancellation()
            guard current == generation else { return }
            rows = CoachAthleteRow.make(
                athletes: athletes, workouts: workouts, runs: weeklyRuns, latest: latest, now: now, week: week
            )
            updatedAt = now
            if coachV2 == .on {
                await loadCoachV2Status(generation: current)
            } else {
                athletesNeedingUpdate = []
            }
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            let code = (error as? URLError)?.code
            offline = code == .notConnectedToInternet || code == .networkConnectionLost
            failure = true
        }
    }
}

struct CoachAthleteDestination: Hashable {
    let athleteID: UUID
    let name: String
}

struct CoachAthleteList: View {
    @ObservedObject var model: CoachAthleteListModel
    let ownerID: UUID
    var planSetupUnavailable = false
    let retry: () async -> Void

    var body: some View {
        if model.ownerID == ownerID {
            content
        } else {
            athleteSkeleton
                .accessibilityLabel("Loading athletes")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.coachV2 == .paused {
            // v1.3 §3.7, C7.12: the server kill switch is on. [ASSUMPTION copy]
            Text("Some coach tools are paused for now.")
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if model.failure || planSetupUnavailable {
            ContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.offline ? "You're offline." : "Couldn't load your athletes.")
                        .foregroundStyle(Color.textPrimary)
                    if let date = model.updatedAt {
                        Text("Updated \(date, format: .relative(presentation: .named))")
                            .foregroundStyle(Color.textSecondary)
                    }
                    if !planSetupUnavailable {
                        Button("Retry") { Task { await retry() } }
                            .buttonStyle(NeonButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if model.updatedAt == nil && !model.failure {
            VStack(spacing: 12) {
                ForEach(0..<3) { _ in
                    athleteSkeleton
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading athletes")
        } else if model.updatedAt != nil && model.rows.isEmpty && !model.failure {
            ContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No athletes yet.").font(.headingMD)
                    Text("Share your invite code to get started.")
                    Text("Athletes choose to share before you see anything.")
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            group("Needs attention", statuses: [.behind])
            group("On track", statuses: [.onTrack])
            group("No plan yet", statuses: [.noPlan, .joining])
        }
    }

    private var athleteSkeleton: some View {
        ContentCard {
            HStack(spacing: 12) {
                Circle().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().frame(width: 98, height: 10)
                    Capsule().frame(width: 72, height: 8)
                }
                Spacer()
                Capsule().frame(width: 54, height: 18)
            }
            .foregroundStyle(Color.textSecondary.opacity(0.2))
        }
    }

    @ViewBuilder
    private func group(_ title: String, statuses: Set<CoachAthleteRow.Status>) -> some View {
        let rows = model.rows.filter { statuses.contains($0.status) }
        if !rows.isEmpty {
            Text("\(title) (\(rows.count))")
                .font(.headingMD)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                NavigationLink(value: CoachAthleteDestination(athleteID: row.id, name: row.athlete.displayName)) {
                    CoachAthleteListRow(row: row, needsLatestApp: model.athletesNeedingUpdate.contains(row.id))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CoachAthleteListRow: View {
    let row: CoachAthleteRow
    var needsLatestApp = false
    @Environment(\.dynamicTypeSize) private var size

    private var adherence: String { "\(row.done) of \(row.planned) this week" }
    private var lastRun: String {
        guard let date = row.lastRun else { return "No runs yet" }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: .now)
        if day == today { return "Ran today" }
        let relative = RelativeDateTimeFormatter()
        relative.dateTimeStyle = .named
        return "Ran \(relative.localizedString(for: day, relativeTo: today))"
    }

    private var chipIcon: String {
        switch row.status {
        case .behind: "exclamationmark.circle"
        case .onTrack: "checkmark.circle"
        case .noPlan: "calendar"
        case .joining: "clock"
        }
    }

    var body: some View {
        ContentCard {
            let layout = size >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                HStack(alignment: .top, spacing: 12) {
                    Text(LeaveCoachCopy.monogram(for: row.athlete.displayName))
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceElevated, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.athlete.displayName).font(.bodyLG.weight(.semibold))
                        Text(adherence).font(.bodyMD)
                        Text(lastRun).font(.bodyMD)
                        if needsLatestApp {
                            // UX spec A.5, mixed versions (C7.0 AC6). Later v2 actions use this as their disabled reason.
                            Text("Effort, notes and flags aren't available. \(row.athlete.displayName) needs the latest RunSmart.")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Label(row.status.rawValue, systemImage: chipIcon)
                    .font(.labelLG)
                    .foregroundStyle(chipColor)
                    .padding(8)
                    .background(chipColor.opacity(0.12), in: Capsule())
            }
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        let name = row.athlete.displayName
        guard needsLatestApp else {
            return Text("\(name). \(adherence). \(lastRun). \(row.status.rawValue).")
        }
        return Text("\(name). \(adherence). \(lastRun). \(row.status.rawValue). Effort, notes and flags aren't available. \(name) needs the latest RunSmart.")
    }

    private var chipColor: Color {
        switch row.status {
        case .behind: Color.accentHeart
        case .onTrack: Color.accentSuccess
        case .noPlan, .joining: Color.textSecondary
        }
    }
}
