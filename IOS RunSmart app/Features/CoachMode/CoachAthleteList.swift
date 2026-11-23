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
    /// C7.1: what Coach Today shows. Nil unless v2 is on and a load finished. The screen never
    /// re-sorts while visible: a background refresh waits in `pending` behind a "New updates" pill.
    @Published private(set) var today: CoachTodaySnapshot?
    @Published private(set) var hasPendingUpdate = false
    private let service: any CoachReadServing
    private let rosterStatus: @Sendable () async throws -> [UUID: Bool]
    private let tracker: any AnalyticsTracking
    /// C7.2: "new since last visit" counts, and the queue the seen write goes through.
    private let seen: any CoachSeenRepository
    private let outbox: CoachV2Outbox
    /// C7.4: the coach's open flags and the "Mark handled" queue. Coach Today shows its toast.
    let flagStore: CoachFlagStore
    /// C7.2: athletes opened on this phone, and when. Their markers stay cleared until the server's
    /// seen_at catches up, so an offline open does not bring the dot back on the next refresh.
    private var localSeen: [UUID: Date] = [:]
    /// What `today` was built from, so a seen athlete can be rebuilt without a network call.
    private var todayInputs: TodayInputs?
    private(set) var ownerID: UUID?
    private var generation = 0
    private var loading = false
    private var needsV2Reload = false
    private var viewedTracked = false
    private var pending: PendingUpdate?

    private struct PendingUpdate {
        let rows: [CoachAthleteRow]
        let today: CoachTodaySnapshot
        let inputs: TodayInputs?
        let updatedAt: Date
    }

    private struct TodayInputs {
        let athletes: [CoachAthleteSummary]
        let workouts: [CoachWorkoutSummary]
        let runs: [CoachRunSummary]
        let runsLoaded: Bool
        let news: [UUID: CoachAthleteNews]
        var flags: [CoachRunFlag] = []
        var flagsLoaded = true
        let now: Date
        let week: CoachAthleteWeek
    }

    /// How a refresh meets the screen. `replace`: pull to refresh, re-entry, foreground, retry.
    /// `quiet`: a timer while Today is on screen. A quiet result that would move rows waits for the pill.
    enum RefreshStyle { case replace, quiet }

    init(
        service: any CoachReadServing = CoachReadService(),
        rosterStatus: @escaping @Sendable () async throws -> [UUID: Bool] = {
            try await SupabaseCoachV2GateRepository().rosterStatus()
        },
        tracker: (any AnalyticsTracking)? = nil,
        seen: any CoachSeenRepository = SupabaseCoachSeenRepository(),
        outbox: CoachV2Outbox? = nil,
        flagStore: CoachFlagStore? = nil
    ) {
        self.service = service
        self.rosterStatus = rosterStatus
        self.tracker = tracker ?? Analytics.shared
        self.seen = seen
        self.outbox = outbox ?? .shared
        self.flagStore = flagStore ?? .shared
        // A queued, undone or answered "Mark handled" moves the row at once (it is the coach's own action).
        self.flagStore.onChange = { [weak self] in
            guard let self, let inputs = self.todayInputs else { return }
            self.today = self.buildToday(inputs)
        }
    }

    /// Called when `CoachV2Gate.state` changes. Off or paused makes no v2 call.
    func applyCoachV2(_ state: CoachV2State) async {
        coachV2 = state
        if state != .on {
            today = nil
            todayInputs = nil
            pending = nil
            hasPendingUpdate = false
            viewedTracked = false
        }
        guard state == .on, ownerID != nil, updatedAt != nil else {
            athletesNeedingUpdate = []
            return
        }
        if today == nil, let owner = ownerID {
            // The rows were loaded with the 1.2.6 window. Today needs the 7-day window, so load again.
            // That load reads the roster status too.
            if loading { needsV2Reload = true } else { await refresh(owner: owner) }
            return
        }
        await loadCoachV2Status(generation: generation)
    }

    /// Show the update that was held back (the "New updates · Refresh" pill).
    func applyPendingUpdate() {
        guard let pending else { return }
        rows = pending.rows
        todayInputs = pending.inputs
        today = pending.inputs.map(buildToday) ?? pending.today
        updatedAt = pending.updatedAt
        self.pending = nil
        hasPendingUpdate = false
    }

    // MARK: C7.1 analytics (v1.3 section 3.8). Only ids, counts and enums leave the device.

    /// Once per visit, when Today first has data on screen.
    func trackTodayViewed() {
        guard coachV2 == .on, let today, !viewedTracked else { return }
        viewedTracked = true
        CoachV2Analytics.track(
            .coachTodayViewed(athleteCount: today.athleteCount, needCount: today.needCount), to: tracker
        )
    }

    func todayDidDisappear() { viewedTracked = false }

    #if DEBUG
    /// Previews and screenshots only: show `snapshot` as if a load had finished.
    func loadPreview(_ snapshot: CoachTodaySnapshot) {
        ownerID = UUID()
        coachV2 = .on
        today = snapshot
        updatedAt = snapshot.generatedAt
    }
    #endif

    // MARK: C7.2 seen state

    /// The coach opened this athlete's detail (UX spec A.4: seen means opening detail, not scrolling past).
    /// Clears the marker on this phone at once and queues `coach_mark_athlete_seen` with the open time.
    /// Flag-off and paused make no v2 call.
    func markSeen(_ athleteID: UUID, now: Date = .now) {
        guard coachV2 == .on, let owner = ownerID else { return }
        let cleared = today?.rows.first { $0.id == athleteID }?.newCount ?? 0
        localSeen[athleteID] = now
        // Today sits under the detail, so rebuilding it here never moves rows while the coach looks at them.
        if let inputs = todayInputs { today = buildToday(inputs) }
        outbox.enqueue(.markSeen(athleteID: athleteID, seenAt: now), userID: owner)
        CoachV2Analytics.track(.coachAthleteSeen(newCount: cleared), to: tracker)
        let outbox = outbox
        Task { await outbox.flush(userID: owner) }
    }

    private func buildToday(_ inputs: TodayInputs) -> CoachTodaySnapshot {
        CoachTodaySnapshot.make(
            athletes: inputs.athletes, workouts: inputs.workouts, runs: inputs.runs, runsLoaded: inputs.runsLoaded,
            news: effectiveNews(inputs.news), flags: flagStore.openFlags(inputs.flags), flagsLoaded: inputs.flagsLoaded,
            now: inputs.now, week: inputs.week
        )
    }

    // MARK: C7.4 flags

    /// "Mark handled" on a Today row (UX spec A.3 item 8). Flag-off and paused make no v2 call.
    func markHandled(_ row: CoachTodayRow) {
        guard coachV2 == .on, let owner = ownerID else { return }
        flagStore.knownNames[row.id] = row.name
        for flag in row.flags { flagStore.markHandled(flag, coachID: owner) }
    }

    /// For the failure line after the athlete left: their row is gone by then.
    func athleteName(_ id: UUID) -> String? {
        today?.rows.first { $0.id == id }?.name ?? flagStore.knownNames[id]
    }

    /// Sends queued resolves first, then reads open flags. A failure shows the banner, never an empty group.
    private func loadFlags(owner: UUID, athleteIDs: [UUID], enabled: Bool) async -> (flags: [CoachRunFlag], loaded: Bool) {
        guard enabled else { return ([], true) }
        await flagStore.flush(coachID: owner)
        do {
            return (try await flagStore.load(athleteIDs: athleteIDs), true)
        } catch {
            if !(error is CancellationError) { print("[CoachToday] flags read failed:", error) }
            return ([], false)
        }
    }

    /// Server counts, minus athletes opened on this phone after the server's seen_at.
    private func effectiveNews(_ server: [UUID: CoachAthleteNews]) -> [UUID: CoachAthleteNews] {
        var result = server
        for (id, openedAt) in localSeen {
            guard let item = server[id] else { continue }
            if let serverSeen = item.seenAt, serverSeen >= openedAt.addingTimeInterval(-1) { continue }
            result[id] = item.seen(at: openedAt)
        }
        return result
    }

    /// Sends queued seen writes first, so the counts read right after reflect them. Any failure shows no markers.
    private func loadNews(owner: UUID, enabled: Bool) async -> [UUID: CoachAthleteNews] {
        guard enabled else { return [:] }
        await outbox.flush(userID: owner)
        do {
            return try await seen.rosterNews()
        } catch {
            if !(error is CancellationError) { print("[CoachToday] news read failed:", error) }
            return [:]
        }
    }

    func trackRowOpened(_ row: CoachTodayRow) {
        guard coachV2 == .on else { return }
        CoachV2Analytics.track(.coachTodayRowOpened(reason: row.reason?.rawValue ?? "none"), to: tracker)
    }

    private var rosterIDs: [UUID] {
        var ids = rows.map(\.id)
        if let today { ids += today.rows.map(\.id) }
        return ids
    }

    private func loadCoachV2Status(generation current: Int) async {
        do {
            let status = try await rosterStatus()
            guard current == generation, coachV2 == .on else { return }
            // Only an explicit false shows the line. A missing row is unknown, not "old app".
            athletesNeedingUpdate = Set(rosterIDs.filter { status[$0] == false })
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
        today = nil
        todayInputs = nil
        localSeen = [:]
        pending = nil
        hasPendingUpdate = false
        viewedTracked = false
    }

    func refresh(owner: UUID, now: Date = .now, style: RefreshStyle = .replace) async {
        await performRefresh(owner: owner, now: now, style: style)
        // The gate turned v2 on while the 1.2.6-window load was running.
        if needsV2Reload, coachV2 == .on, today == nil, !failure, ownerID == owner {
            await performRefresh(owner: owner, now: now, style: style)
        }
    }

    private func performRefresh(owner: UUID, now: Date, style: RefreshStyle) async {
        reset(for: owner)
        guard !loading else { return }
        loading = true
        let current = generation
        defer { if current == generation { loading = false } }
        let v2 = coachV2 == .on
        needsV2Reload = false
        if style == .replace {
            failure = false
            offline = false
        }

        do {
            let athletes = try await service.listAthletes()
            try Task.checkCancellation()
            guard current == generation else { return }
            let ids = athletes.map(\.athleteID)
            let active = Set(ids)
            let week = CoachAthleteWeek(now: now)
            rows.removeAll { !active.contains($0.id) }
            if ids.isEmpty {
                let inputs = v2 ? TodayInputs(
                    athletes: [], workouts: [], runs: [], runsLoaded: true, news: [:], now: now, week: week
                ) : nil
                _ = commit(rows: rows, inputs: inputs, now: now, style: style)
                return
            }

            // Today (v2) reads the last 7 days, which can start before this training week.
            // The roster below it keeps the 1.2.6 week window and 1.2.6 rules.
            let sevenDaysAgo = week.calendar.date(
                byAdding: .day, value: -6, to: week.calendar.startOfDay(for: now)
            )!
            let windowStart = v2 ? min(week.interval.start, sevenDaysAgo) : week.interval.start
            async let planned = service.workouts(
                from: windowStart, to: week.lastDay, athleteIDs: ids, calendar: week.calendar
            )
            // The server filters run dates in UTC. Fetch the boundary dates and then use the coach's week.
            async let recorded = Self.fetchRuns(service, from: windowStart, to: now, athleteIDs: ids)
            // C7.2: only for v2. Flag-off and paused never call it.
            async let fetchedNews = loadNews(owner: owner, enabled: v2)
            // C7.4: only for v2, like the news read.
            async let fetchedFlags = loadFlags(owner: owner, athleteIDs: ids, enabled: v2)
            let workouts = try await planned
            var runsLoaded = true
            var runs: [CoachRunSummary] = []
            switch await recorded {
            case .success(let fetched):
                runs = fetched
            case .failure(let error):
                // 1.2.6: any failure fails the roster. v2: runs may fail alone, and then days read "unknown".
                if !v2 || error is CancellationError { throw error }
                runsLoaded = false
            }
            let weekStartISO = CoachReadDay.iso(week.interval.start, calendar: week.calendar)
            let weeklyWorkouts = v2 ? workouts.filter { $0.scheduledDate >= weekStartISO } : workouts
            let weeklyRuns = runs.filter { week.contains($0.completedAt) && $0.completedAt <= now }
            var latest: [UUID: Date] = [:]
            if runsLoaded {
                let recentIDs = Set(weeklyRuns.map(\.athleteID))
                for id in ids where !recentIDs.contains(id) {
                    try Task.checkCancellation()
                    guard current == generation else { return }
                    latest[id] = try await service.latestRun(for: id, through: now)?.completedAt
                }
            }

            try Task.checkCancellation()
            guard current == generation else { return }
            // Without runs every athlete would look behind, so the roster keeps its last rows.
            let newRows = runsLoaded ? CoachAthleteRow.make(
                athletes: athletes, workouts: weeklyWorkouts, runs: weeklyRuns, latest: latest, now: now, week: week
            ) : rows
            let news = await fetchedNews
            let flagResult = await fetchedFlags
            try Task.checkCancellation()
            guard current == generation else { return }
            let inputs = v2 ? TodayInputs(
                athletes: athletes, workouts: workouts, runs: runs.filter { $0.completedAt <= now },
                runsLoaded: runsLoaded, news: news, flags: flagResult.flags, flagsLoaded: flagResult.loaded,
                now: now, week: week
            ) : nil

            guard commit(rows: newRows, inputs: inputs, now: now, style: style) else { return }
            if coachV2 == .on {
                await loadCoachV2Status(generation: current)
            } else {
                athletesNeedingUpdate = []
                if !v2 { needsV2Reload = false }
            }
            if !v2 && coachV2 == .on { needsV2Reload = true }
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            // A quiet refresh never turns a working screen into an error.
            guard style == .replace else { return }
            let code = (error as? URLError)?.code
            offline = code == .notConnectedToInternet || code == .networkConnectionLost
            failure = true
        }
    }

    /// Shows a finished load. A quiet load that would move rows is held behind the pill instead.
    /// Returns false when it was held.
    private func commit(rows newRows: [CoachAthleteRow], inputs: TodayInputs?, now: Date, style: RefreshStyle) -> Bool {
        if let inputs {
            // The server caught up with an open on this phone: its counts are right again.
            localSeen = localSeen.filter { id, openedAt in
                guard let serverSeen = inputs.news[id]?.seenAt else { return true }
                return serverSeen < openedAt.addingTimeInterval(-1)
            }
        }
        let snapshot = inputs.map(buildToday)
        if style == .quiet, let shown = today, let snapshot, snapshot.layoutSignature != shown.layoutSignature {
            // Rows would move while the coach is looking. Hold the update behind the pill.
            pending = PendingUpdate(rows: newRows, today: snapshot, inputs: inputs, updatedAt: now)
            hasPendingUpdate = true
            return false
        }
        rows = newRows
        todayInputs = inputs
        today = snapshot
        pending = nil
        hasPendingUpdate = false
        updatedAt = now
        return true
    }

    private nonisolated static func fetchRuns(
        _ service: any CoachReadServing, from: Date, to: Date, athleteIDs: [UUID]
    ) async -> Result<[CoachRunSummary], Error> {
        do {
            return .success(try await service.runs(from: from, to: to, athleteIDs: athleteIDs, calendar: .coachRunUTC))
        } catch {
            return .failure(error)
        }
    }
}

struct CoachAthleteDestination: Hashable {
    let athleteID: UUID
    let name: String
    /// C7.1: the day the detail opens on (`yyyy-MM-dd`, the reason's day). Nil opens the week as before.
    var focusDayISO: String?
    /// C7.1: opened from the v2 Coach tab, so the detail uses the v2 copy for a revoked link.
    var coachV2 = false
}

struct CoachAthleteList: View {
    @ObservedObject var model: CoachAthleteListModel
    let ownerID: UUID
    var planSetupUnavailable = false
    /// C7.1: opens the athlete on the row's reason. Used by Coach Today only.
    var open: (CoachAthleteDestination, CoachTodayRow) -> Void = { _, _ in }
    var onShareInvite: (() -> Void)?
    let retry: () async -> Void
    @State private var showsRoster = false

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
        if model.coachV2 == .on {
            // C7.1: Coach Today above the roster. Off and paused fall through to the 1.2.6 roster below.
            CoachTodayView(model: model, onShareInvite: onShareInvite, open: { row in
                open(
                    CoachAthleteDestination(
                        athleteID: row.id, name: row.name, focusDayISO: row.focusDayISO, coachV2: true
                    ),
                    row
                )
            }, retry: retry)
            allAthletes
        } else {
            roster
        }
    }

    /// T7: the full roster stays one tap below Today. It starts collapsed so rows are not shown twice.
    @ViewBuilder
    private var allAthletes: some View {
        if let today = model.today, today.runsLoaded, !model.rows.isEmpty {
            Button {
                showsRoster.toggle()
            } label: {
                HStack {
                    Text("All athletes (\(model.rows.count))").font(.headingMD).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: showsRoster ? "chevron.down" : "chevron.forward")
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(showsRoster ? "Expanded" : "Collapsed")
            if showsRoster {
                group("Needs attention", statuses: [.behind])
                group("On track", statuses: [.onTrack])
                group("No plan yet", statuses: [.noPlan, .joining])
            }
        }
    }

    @ViewBuilder
    private var roster: some View {
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
                NavigationLink(value: CoachAthleteDestination(
                    athleteID: row.id, name: row.athlete.displayName, coachV2: model.coachV2 == .on
                )) {
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
