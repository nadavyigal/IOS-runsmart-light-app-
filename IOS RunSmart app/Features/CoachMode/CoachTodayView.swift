import SwiftUI

// Coach Today, T1 (story C7.1, UX spec A.3 to A.9). Shown above the roster only while
// `CoachV2Gate.state == .on`. Everything here reads `model.today`; there is no data fetching.
//
// The body is a flat `ForEach` inside a `Group` so the parent `LazyVStack` stays lazy with 30 athletes.

/// One thing in the flat Today list.
private enum CoachTodayItem: Identifiable {
    case updatesPill
    case offlineStrip(Date?)
    case refreshFailed(Date?)
    case runsBanner
    /// C7.4: the flags read failed (UX spec A.5, partial data).
    case flagsBanner
    /// C7.4: "Marked handled · Undo" for 5 s after Mark handled.
    case handledToast(UUID)
    /// C7.4: a queued Mark handled the server refused because the link ended.
    case actionFailed(UUID)
    case header(title: String, summary: String?, detail: String?)
    case skeleton(Int)
    case errorNoCache
    case empty
    case groupHeader(CoachTodayGroup, total: Int)
    case row(CoachTodayRow)
    case showAll(CoachTodayGroup, total: Int)

    var id: String {
        switch self {
        case .updatesPill: "pill"
        case .offlineStrip: "offline"
        case .refreshFailed: "refresh-failed"
        case .runsBanner: "runs-banner"
        case .flagsBanner: "flags-banner"
        case .handledToast: "handled-toast"
        case .actionFailed(let id): "action-failed-\(id.uuidString)"
        case .header: "header"
        case .skeleton(let index): "skeleton-\(index)"
        case .errorNoCache: "error"
        case .empty: "empty"
        case .groupHeader(let group, _): "group-\(group.rawValue)"
        case .row(let row): "row-\(row.id.uuidString)"
        case .showAll(let group, _): "show-all-\(group.rawValue)"
        }
    }
}

/// Rows shown in a group before "Show all {n}" (UX spec A.7 item 10).
let coachTodayGroupLimit = 8

struct CoachTodayView: View {
    @ObservedObject var model: CoachAthleteListModel
    /// C7.4: the Mark handled queue, for its toast. The same store the model reads.
    @ObservedObject var flagStore: CoachFlagStore = .shared
    var onShareInvite: (() -> Void)?
    let open: (CoachTodayRow) -> Void
    let retry: () async -> Void

    @State private var expandedGroups: Set<CoachTodayGroup> = []
    @State private var fullGroups: Set<CoachTodayGroup> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            ForEach(items) { item in
                view(for: item)
            }
        }
    }

    // MARK: Items

    private var items: [CoachTodayItem] {
        guard let snapshot = model.today else {
            if model.failure { return [.errorNoCache] }
            // First load ever: the header and 4 skeleton rows. No spinner over the whole screen.
            return [.header(title: Self.fallbackTitle(locale), summary: nil, detail: nil)] + (0..<4).map { .skeleton($0) }
        }
        var list: [CoachTodayItem] = []
        if model.hasPendingUpdate { list.append(.updatesPill) }
        if model.failure {
            list.append(model.offline ? .offlineStrip(model.updatedAt) : .refreshFailed(model.updatedAt))
        }
        if !snapshot.runsLoaded { list.append(.runsBanner) }
        if !snapshot.flagsLoaded { list.append(.flagsBanner) }
        list += flagStore.failedAthletes.map { .actionFailed($0) }
        if let toast = flagStore.toastFlagID { list.append(.handledToast(toast)) }
        list.append(.header(
            title: snapshot.headerTitle(locale: locale), summary: snapshot.summaryLine, detail: snapshot.caughtUpDetail
        ))
        guard snapshot.athleteCount > 0 else { return list + [.empty] }

        let groups = snapshot.groups
        for group in groups {
            let rows = snapshot.rows(in: group)
            list.append(.groupHeader(group, total: rows.count))
            guard isExpanded(group, onlyGroup: groups.count == 1) else { continue }
            let limited = rows.count > coachTodayGroupLimit && !fullGroups.contains(group)
            for row in limited ? Array(rows.prefix(coachTodayGroupLimit)) : rows { list.append(.row(row)) }
            if limited { list.append(.showAll(group, total: rows.count)) }
        }
        return list
    }

    private static func fallbackTitle(_ locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE d MMM"
        return "Today, " + formatter.string(from: Date())
    }

    /// Groups that need the coach are always open. The others start collapsed, except when a group is
    /// the only one on screen (nobody has a plan yet), where a collapsed header would leave a blank screen.
    private func isExpanded(_ group: CoachTodayGroup, onlyGroup: Bool) -> Bool {
        !group.startsCollapsed || onlyGroup || expandedGroups.contains(group)
    }

    // MARK: Views

    @ViewBuilder
    private func view(for item: CoachTodayItem) -> some View {
        switch item {
        case .updatesPill:
            Button {
                model.applyPendingUpdate()
            } label: {
                Text("New updates · Refresh")
                    .font(.labelLG)
                    .foregroundStyle(Color.accentPrimary)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color.surfaceElevated, in: Capsule())
                    .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        case .offlineStrip(let date):
            strip("Offline · updated \(Self.clock(date))")
        case .refreshFailed(let date):
            ContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't refresh · showing \(Self.clock(date))").foregroundStyle(Color.textPrimary)
                    tryAgain
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .runsBanner:
            ContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Runs didn't load, so some days may look empty. Try again.")
                        .foregroundStyle(Color.textPrimary)
                    tryAgain
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .flagsBanner:
            ContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(RunFlagCopy.flagsFailed).foregroundStyle(Color.textPrimary)
                    tryAgain
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .handledToast(let flagID):
            Button {
                flagStore.undo(flagID)
            } label: {
                Text(RunFlagCopy.markedHandledToast)
                    .font(.labelLG)
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.surfaceElevated, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Undo marks the flag open again")
        case .actionFailed(let athleteID):
            Button {
                flagStore.failedAthletes.removeAll { $0 == athleteID }
            } label: {
                strip(RunFlagCopy.actionFailed(athlete: model.athleteName(athleteID) ?? "This athlete"))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Dismisses this message")
        case .header(let title, let summary, let detail):
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headingLG)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let summary {
                    Text(summary).font(.bodyLG).foregroundStyle(Color.textPrimary)
                }
                if let detail {
                    Text(detail).font(.bodyMD).foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        case .skeleton:
            skeletonRow
        case .errorNoCache:
            ContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load your athletes.").foregroundStyle(Color.textPrimary)
                    tryAgain
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .empty:
            ContentCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No athletes yet").font(.headingMD).foregroundStyle(Color.textPrimary)
                    Text("Share your invite link. Athletes show up here once they join.")
                        .foregroundStyle(Color.textSecondary)
                    if let onShareInvite {
                        Button("Share invite link", action: onShareInvite)
                            .buttonStyle(NeonButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .groupHeader(let group, let total):
            groupHeader(group, total: total)
        case .row(let row):
            CoachTodayRowView(
                row: row, needsLatestApp: model.athletesNeedingUpdate.contains(row.id), open: { open(row) },
                markHandled: row.flags.isEmpty ? nil : { model.markHandled(row) }
            )
        case .showAll(let group, let total):
            Button {
                fullGroups.insert(group)
            } label: {
                Text("Show all \(total)")
                    .font(.labelLG)
                    .foregroundStyle(Color.accentPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var tryAgain: some View {
        Button("Try again") { Task { await retry() } }
            .buttonStyle(NeonButtonStyle())
    }

    /// Non-dismissable (UX spec A.5, offline).
    private func strip(_ text: String) -> some View {
        Text(text)
            .font(.labelLG)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous))
    }

    @ViewBuilder
    private func groupHeader(_ group: CoachTodayGroup, total: Int) -> some View {
        let title = group.title(count: total)
        if group.startsCollapsed, total > 0, model.today?.groups.count != 1 {
            let open = expandedGroups.contains(group)
            Button {
                toggle(group)
            } label: {
                HStack {
                    Text(title).font(.headingMD).foregroundStyle(Color.textPrimary)
                    Spacer()
                    // The chevron mirrors in RTL; "forward" and "down" are direction-neutral names.
                    Image(systemName: open ? "chevron.down" : "chevron.forward")
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
        } else {
            Text(title)
                .font(.headingMD)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func toggle(_ group: CoachTodayGroup) {
        let change = {
            if expandedGroups.contains(group) { expandedGroups.remove(group) } else { expandedGroups.insert(group) }
        }
        // Reduced motion: no row animation (UX spec A.8).
        if reduceMotion { change() } else { withAnimation(.easeInOut(duration: 0.2)) { change() } }
    }

    private var skeletonRow: some View {
        ContentCard {
            HStack(spacing: 12) {
                Circle().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().frame(width: 98, height: 10)
                    Capsule().frame(width: 150, height: 8)
                    Capsule().frame(width: 120, height: 8)
                }
                Spacer()
            }
            .foregroundStyle(Color.textSecondary.opacity(0.2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading athletes")
    }

    private static func clock(_ date: Date?) -> String {
        guard let date else { return "earlier" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: Row

extension CoachTodayDayState {
    var color: Color {
        switch self {
        case .done, .extra: Color.accentSuccess
        case .partial: Color.accentEnergy
        case .missed: Color.accentHeart
        case .rest, .planned, .unknown: Color.textSecondary
        }
    }
}

extension CoachTodayReason {
    var color: Color {
        switch self {
        case .pain, .somethingOff, .missedToday, .missedYesterday: Color.accentHeart
        case .behind: Color.accentEnergy
        case .reply, .newRun, .changedGoal, .changedWorkout: Color.accentPrimary
        }
    }
}

struct CoachTodayRowView: View {
    let row: CoachTodayRow
    var needsLatestApp = false
    let open: () -> Void
    /// C7.4: set only on rows with open flags (UX spec A.3 item 8).
    var markHandled: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var size
    /// The day the adjustable dots strip is on. Nil until the coach swipes up or down.
    @State private var steppedDay: Int?

    /// UX spec A.8: from XXL the chip moves under the name and the dots get their own line. From AX3 the
    /// dots become a text line.
    private var stacked: Bool { size >= .xxLarge }
    private var textOnlyDays: Bool { size >= .accessibility3 }

    var body: some View {
        Button(action: open) {
            ContentCard {
                HStack(alignment: .top, spacing: 12) {
                    Text(LeaveCoachCopy.monogram(for: row.name))
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceElevated, in: Circle())
                        // C7.2: the "new" dot on the trailing-top corner. It is drawn only together with
                        // the "{n} new" text next to the name (UX spec A.3 item 4).
                        .overlay(alignment: .topTrailing) {
                            if row.newLabel != nil { newDot.offset(x: 2, y: -2) }
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        nameAndChip
                        if let preview = row.flagPreview {
                            // The athlete's own words, coach-only, in their own direction (C7.15).
                            Text(verbatim: preview)
                                .font(.bodyMD)
                                .foregroundStyle(Color.textPrimary)
                                .naturalTextDirection(preview)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(row.todayLine)
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if needsLatestApp {
                            // Same mixed-version line as the roster (C7.0 AC6).
                            Text("Effort, notes and flags aren't available. \(row.name) needs the latest RunSmart.")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        daysLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(steppedDay.map { row.days[$0].spoken } ?? "")
        .accessibilityAdjustableAction { direction in
            // Swipe up steps to a later day, swipe down to an earlier one. The first step starts at today.
            let last = row.days.count - 1
            guard last >= 0 else { return }
            switch direction {
            case .increment: steppedDay = min((steppedDay ?? last) + 1, last)
            case .decrement: steppedDay = max((steppedDay ?? last + 1) - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Open \(row.name)", open)
        .accessibilityAction(named: "Write feedback", open)
        .modifier(MarkHandledActions(markHandled: markHandled))
    }

    private var spokenLabel: String {
        needsLatestApp
            ? row.spokenSentence + " Effort, notes and flags aren't available. \(row.name) needs the latest RunSmart."
            : row.spokenSentence
    }

    @ViewBuilder
    private var nameAndChip: some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.name)
                    .font(.bodyLG.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if let newLabel = row.newLabel {
                    // Pairs with the dot on the monogram (UX spec A.3 item 4).
                    Text(newLabel)
                        .font(.labelSM)
                        .foregroundStyle(Color.accentPrimary)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let reason = row.reason, let chip = row.chipText {
                // Icon plus text: the chip never relies on color.
                Label(chip, systemImage: reason.icon)
                    .font(.labelLG)
                    .foregroundStyle(reason.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(reason.color.opacity(0.12), in: Capsule())
            }
        }
    }

    private var newDot: some View {
        Circle()
            .fill(Color.accentPrimary)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.surfaceBase, lineWidth: 1.5))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var daysLine: some View {
        if textOnlyDays {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.daysSummaryText).font(.bodyMD).foregroundStyle(Color.textPrimary)
                progress
            }
        } else {
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            layout {
                // Oldest at the leading edge, today at the trailing edge. An HStack mirrors in RTL.
                HStack(spacing: 6) {
                    ForEach(row.days) { day in
                        Image(systemName: day.state.glyph)
                            .font(.system(size: 15, weight: day.state == .planned ? .heavy : .semibold))
                            .foregroundStyle(day.state.color)
                            .frame(width: 20, height: 20)
                    }
                }
                if !stacked { Spacer(minLength: 8) }
                progress
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        if let text = row.weekProgress {
            Text(text).font(.labelSM).foregroundStyle(Color.textSecondary)
        }
    }
}

/// C7.4: "Mark handled" as a long-press menu item and a VoiceOver custom action, on flag rows only.
private struct MarkHandledActions: ViewModifier {
    let markHandled: (() -> Void)?

    func body(content: Content) -> some View {
        if let markHandled {
            content
                .contextMenu {
                    Button(RunFlagCopy.markHandled, systemImage: "checkmark.circle", action: markHandled)
                }
                .accessibilityAction(named: RunFlagCopy.markHandled, markHandled)
        } else {
            content
        }
    }
}

// MARK: Previews

#if DEBUG
extension CoachTodaySnapshot {
    /// 30 fixture athletes across every group, for the previews and the simulator screenshots.
    static func previewFixture(
        athletes count: Int = 30, runsLoaded: Bool = true, withNews: Bool = false, withFlags: Bool = false,
        flagsLoaded: Bool = true, now: Date = Date(timeIntervalSince1970: 1_795_000_000)
    ) -> CoachTodaySnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        let week = CoachAthleteWeek(now: now, locale: Locale(identifier: "en_GB"), timeZone: calendar.timeZone)
        let names = ["Yoni", "Noa", "Avi", "Maya", "Dana", "Omer", "Lior", "Tamar", "Gil", "Shir",
                     "Eitan", "Roni", "Hila", "Amit", "Nir", "Tal", "Yael", "Ido", "Mor", "Ben",
                     "Dor", "Lia", "Uri", "Neta", "Ran", "Sivan", "Alon", "Gal", "Keren", "Zeev"]
        let athletes = (0..<count).map { index in
            CoachAthleteSummary(
                athleteID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                displayName: names[index % names.count], linkedAt: now.addingTimeInterval(-86_400 * 40),
                hasActivePlan: index % 10 != 9
            )
        }
        var workouts: [CoachWorkoutSummary] = []
        var runs: [CoachRunSummary] = []
        let todayStart = calendar.startOfDay(for: now)
        for (index, athlete) in athletes.enumerated() where athlete.hasActivePlan {
            for back in 0..<7 {
                let day = calendar.date(byAdding: .day, value: -back, to: todayStart)!
                guard (index + back) % 3 != 2 else { continue }   // some rest days
                let workoutID = UUID()
                workouts.append(previewWorkout(workoutID, athlete.athleteID, CoachReadDay.iso(day, calendar: calendar), index + back))
                // Mostly done; every 4th athlete skips; every 7th is partial.
                let skips = index % 4 == 0 && back <= 1
                if !skips {
                    let km = index % 7 == 0 ? 3.0 : 5.0
                    runs.append(previewRun(index * 10 + back, athlete.athleteID, workoutID, day.addingTimeInterval(8 * 3600), km))
                }
            }
        }
        return CoachTodaySnapshot.make(
            athletes: athletes, workouts: workouts, runs: runs, runsLoaded: runsLoaded,
            news: withNews ? previewNews(athletes, now: now) : [:],
            flags: withFlags && flagsLoaded ? previewFlags(athletes, now: now) : [], flagsLoaded: flagsLoaded, now: now, week: week,
            locale: Locale(identifier: "en_GB")
        )
    }

    /// C7.2 markers: new runs, a goal change, a changed workout, and news on rows that are also urgent.
    static func previewNews(_ athletes: [CoachAthleteSummary], now: Date) -> [UUID: CoachAthleteNews] {
        var news: [UUID: CoachAthleteNews] = [:]
        let patterns: [Int: CoachAthleteNews] = [
            1: CoachAthleteNews(newRuns: 2, oldestNewAt: now.addingTimeInterval(-20_000)),
            2: CoachAthleteNews(newRuns: 1, newEvents: 1, latestEventKind: .goalChange, oldestNewAt: now.addingTimeInterval(-50_000)),
            3: CoachAthleteNews(newEvents: 1, latestEventKind: .goalChange, oldestNewAt: now.addingTimeInterval(-9_000)),
            4: CoachAthleteNews(newRuns: 3, oldestNewAt: now.addingTimeInterval(-80_000)),
            5: CoachAthleteNews(newEvents: 1, latestEventKind: .athleteMove, oldestNewAt: now.addingTimeInterval(-4_000)),
            8: CoachAthleteNews(newRuns: 1, oldestNewAt: now.addingTimeInterval(-3_000))
        ]
        for (index, athlete) in athletes.enumerated() {
            if let item = patterns[index] { news[athlete.athleteID] = item }
        }
        return news
    }

    /// C7.4: a pain flag with a note, two flags on one athlete, a run-less "something off" and a deleted run.
    static func previewFlags(_ athletes: [CoachAthleteSummary], now: Date) -> [CoachRunFlag] {
        func flag(_ index: Int, _ kind: RunFlagKind, _ note: String?, hoursAgo: Double, runDeleted: Bool = false) -> CoachRunFlag? {
            guard athletes.indices.contains(index) else { return nil }
            return CoachRunFlag(
                id: UUID(uuidString: String(format: "f0000000-0000-4000-8000-%012d", index * 10 + Int(hoursAgo)))!,
                athleteID: athletes[index].athleteID, runID: runDeleted ? nil : index, runDeleted: runDeleted,
                kind: kind, note: note, createdAt: now.addingTimeInterval(-hoursAgo * 3600)
            )
        }
        return [
            flag(0, .pain, "Knee, after Sunday's long run", hoursAgo: 30),
            flag(3, .off, "Slept badly all week and my legs feel heavy on every easy run so far", hoursAgo: 5),
            flag(6, .pain, "כאב בשוק השמאלית", hoursAgo: 8),
            flag(6, .off, nil, hoursAgo: 2),
            flag(7, .off, nil, hoursAgo: 12, runDeleted: true)
        ].compactMap { $0 }
    }

    private static func previewWorkout(_ id: UUID, _ athlete: UUID, _ date: String, _ seed: Int) -> CoachWorkoutSummary {
        let types = ["easy", "tempo", "long", "intervals"]
        let json = """
        {"id":"\(id)","athlete_id":"\(athlete)","plan_id":"\(UUID())","scheduled_date":"\(date)",
        "type":"\(types[seed % types.count])","planned_distance":5,"planned_duration_minutes":30,"completed":false}
        """
        return try! JSONDecoder().decode(CoachWorkoutSummary.self, from: Data(json.utf8))
    }

    private static func previewRun(_ id: Int, _ athlete: UUID, _ workout: UUID, _ at: Date, _ km: Double) -> CoachRunSummary {
        let stamp = ISO8601DateFormatter().string(from: at)
        let json = """
        {"id":\(id),"athlete_id":"\(athlete)","workout_id":"\(workout)","completed_at":"\(stamp)",
        "distance_km":\(km),"duration_seconds":\(Int(km * 330))}
        """
        return try! JSONDecoder().decode(CoachRunSummary.self, from: Data(json.utf8))
    }
}

#Preview("Coach Today, 30 athletes") {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
            CoachTodayView(
                model: CoachAthleteListModel.previewModel(.previewFixture()), onShareInvite: nil, open: { _ in }, retry: {}
            )
        }
        .padding(.horizontal, 18)
    }
    .background(Color.surfaceBase)
}

#Preview("Coach Today, new to review") {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
            CoachTodayView(
                model: CoachAthleteListModel.previewModel(.previewFixture(athletes: 10, withNews: true)),
                onShareInvite: nil, open: { _ in }, retry: {}
            )
        }
        .padding(.horizontal, 18)
    }
    .background(Color.surfaceBase)
}

#Preview("Coach Today, pain flags") {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
            CoachTodayView(
                model: CoachAthleteListModel.previewModel(.previewFixture(athletes: 10, withNews: true, withFlags: true)),
                onShareInvite: nil, open: { _ in }, retry: {}
            )
        }
        .padding(.horizontal, 18)
    }
    .background(Color.surfaceBase)
}

#Preview("Coach Today, runs failed") {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
            CoachTodayView(
                model: CoachAthleteListModel.previewModel(.previewFixture(athletes: 6, runsLoaded: false)),
                onShareInvite: nil, open: { _ in }, retry: {}
            )
        }
        .padding(.horizontal, 18)
    }
    .background(Color.surfaceBase)
}

extension CoachAthleteListModel {
    /// A model that already shows `snapshot`. Previews and screenshots only.
    static func previewModel(_ snapshot: CoachTodaySnapshot) -> CoachAthleteListModel {
        let model = CoachAthleteListModel()
        model.loadPreview(snapshot)
        return model
    }
}
#endif
