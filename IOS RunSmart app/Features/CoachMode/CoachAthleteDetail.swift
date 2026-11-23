import Combine
import Network
import SwiftUI

/// C5 data for one athlete: this week and last week, read through Story 2.2's consent-checked RPCs.
@MainActor
final class CoachAthleteDetailModel: ObservableObject {
    @Published private(set) var current: CoachAthleteWeekDays?
    @Published private(set) var previous: CoachAthleteWeekDays?
    @Published private(set) var hasPlan = true
    @Published private(set) var updatedAt: Date?
    @Published private(set) var failure = false
    @Published private(set) var offline = false
    @Published private(set) var revoked = false
    /// C7.3 AC4: the athlete's run notes the coach may read, by run id. Always empty when Coach v2 is off.
    @Published private(set) var runNotes: [Int: String] = [:]
    private(set) var calendar = Calendar(identifier: .gregorian)
    let athleteID: UUID
    let coachV2: Bool
    private let service: any CoachReadServing
    private let fetchNotes: @Sendable ([Int]) async throws -> [Int: String]
    private var inFlight: Task<Void, Never>?

    init(
        athleteID: UUID, service: any CoachReadServing = CoachReadService(), coachV2: Bool = false,
        fetchNotes: @escaping @Sendable ([Int]) async throws -> [Int: String] = { try await CoachRunNotesFetcher.notes(runIDs: $0) }
    ) {
        self.athleteID = athleteID
        self.service = service
        self.coachV2 = coachV2
        self.fetchNotes = fetchNotes
    }

    var hasRuns: Bool {
        [current, previous].compactMap { $0 }.flatMap(\.days)
            .contains { !$0.extraRuns.isEmpty || $0.workouts.contains { $0.run != nil } }
    }

    /// The week strips show with a plan, or without one when the athlete still has recorded runs.
    var showsWeeks: Bool { current != nil && (hasPlan || hasRuns) }

    /// A second call while a load is running waits for that load, so pull-to-refresh never ends early.
    func load(now: Date = .now, locale: Locale = .current, timeZone: TimeZone = .current) async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await perform(now: now, locale: locale, timeZone: timeZone) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func perform(now: Date, locale: Locale, timeZone: TimeZone) async {
        failure = false
        offline = false
        do {
            // The roster is the consent check: a revoked or missing link drops the athlete from it.
            let athletes = try await service.listAthletes()
            guard let athlete = athletes.first(where: { $0.athleteID == athleteID }) else {
                revoked = true
                current = nil
                previous = nil
                runNotes = [:]
                return
            }
            hasPlan = athlete.hasActivePlan
            let week = CoachAthleteWeek(now: now, locale: locale, timeZone: timeZone)
            calendar = week.calendar
            let previousStart = week.calendar.date(byAdding: .day, value: -7, to: week.interval.start)!
            async let planned = service.workouts(
                from: previousStart, to: week.lastDay, athleteIDs: [athleteID], calendar: week.calendar
            )
            // The server filters run dates in UTC. Fetch the boundary dates and then use the coach's days.
            async let recorded = service.runs(
                from: previousStart, to: now, athleteIDs: [athleteID], calendar: .coachRunUTC
            )
            let (workouts, runs) = try await (planned, recorded)
            let athleteRuns = runs.filter { $0.athleteID == athleteID }
            let weeks = CoachAthleteDays.weeks(
                workouts: workouts.filter { $0.athleteID == athleteID },
                runs: athleteRuns, now: now, week: week
            )
            runNotes = coachV2 ? await notes(for: athleteRuns) : [:]
            current = weeks.current
            previous = weeks.previous
            updatedAt = now
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            let code = (error as? URLError)?.code
            offline = code == .notConnectedToInternet || code == .networkConnectionLost
            failure = true
        }
    }

    /// Reads only runs the server marked `has_note`. A failed read never fails the week:
    /// notes from the last good read stay, and a run without one shows no note.
    private func notes(for runs: [CoachRunSummary]) async -> [Int: String] {
        let ids = runs.filter(\.hasNote).map(\.id)
        guard !ids.isEmpty else { return [:] }
        if let fresh = try? await fetchNotes(ids) { return fresh }
        let kept = Set(ids)
        return runNotes.filter { kept.contains($0.key) }
    }
}

/// C7.3 AC4: what the coach may see of an athlete's shared effort and notes. Nil when Coach v2 is off.
struct CoachDaySharing: Equatable {
    let athleteName: String
    let notes: [Int: String]
}

/// C7.3 AC4: the lines under Actual for one run. Empty when sharing is off, effort is not shared
/// and there is no readable note. A hidden note comes back as `has_note` false, so it shows nothing.
nonisolated struct CoachRunSharingLines: Equatable {
    let effort: String?
    let spokenEffort: String?
    let note: String?
    let attribution: String?
    let spokenNote: String?

    var isEmpty: Bool { effort == nil && note == nil }

    init(run: CoachRunSummary, sharing: CoachDaySharing?) {
        guard let sharing else {
            effort = nil; spokenEffort = nil; note = nil; attribution = nil; spokenNote = nil
            return
        }
        effort = CoachRunSharingCopy.effort(run.rpe)
        spokenEffort = effort == nil ? nil : run.rpe.map { "Effort, \($0) of 10" }
        let text = run.hasNote ? sharing.notes[run.id]?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if let text, !text.isEmpty {
            note = CoachRunSharingCopy.quotedNote(text)
            attribution = CoachRunSharingCopy.attribution(athlete: sharing.athleteName)
            spokenNote = "Note from \(sharing.athleteName): \(text)"
        } else {
            note = nil; attribution = nil; spokenNote = nil
        }
    }
}

/// C5 Athlete detail. Plan data is read-only; the coach can write feedback (Story 3.1).
struct CoachAthleteDetailView: View {
    let destination: CoachAthleteDestination
    @StateObject private var model: CoachAthleteDetailModel
    @StateObject private var feedback: CoachFeedbackStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsPreviousWeek = false
    @State private var composer: CoachFeedbackRequest?
    @State private var showsWelcomeEditor = false
    /// C7.1: set once, after the first load, to open on the day the Today row was urgent for.
    @State private var focusedDayISO: String?
    @State private var didFocus = false
    /// C7.11: "Remove {Athlete}". v2 only (flag-off AC); the server does not need the athlete on v2.
    @StateObject private var removeModel = RemoveAthleteModel()
    @State private var showsRemoveSheet = false
    /// Called after the link ended, before the detail closes, so the roster reloads.
    private let onRemoved: () -> Void

    init(destination: CoachAthleteDestination, service: any CoachReadServing = CoachReadService(),
         feedbackService: any CoachFeedbackServing = SupabaseCoachFeedbackService(),
         replyService: any CoachFeedbackReplyFetching = SupabaseCoachFeedbackReplyService(),
         onRemoved: @escaping () -> Void = {}) {
        self.destination = destination
        self.onRemoved = onRemoved
        _model = StateObject(wrappedValue: CoachAthleteDetailModel(
            athleteID: destination.athleteID, service: service, coachV2: destination.coachV2
        ))
        _feedback = StateObject(wrappedValue: Self.feedbackStore(
            destination: destination, service: feedbackService, replies: replyService
        ))
    }

    /// C7.7: replies under the notes, only for a Coach v2 athlete (no reply call otherwise).
    private static func feedbackStore(destination: CoachAthleteDestination, service: any CoachFeedbackServing,
                                      replies: any CoachFeedbackReplyFetching) -> CoachFeedbackStore {
        let store = CoachFeedbackStore(athleteID: destination.athleteID, athleteName: destination.name, service: service)
        if destination.coachV2 { store.enableReplies(replies) }
        return store
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                content
                // Story 4.2 adds the edit action and draft bar here. Nothing renders yet.
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 140)
        }
        .navigationTitle(destination.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !model.revoked, !feedback.revoked {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Welcome note for \(destination.name)") { showsWelcomeEditor = true }
                        if destination.coachV2 {
                            Button(role: .destructive) {
                                removeModel.cancel()
                                showsRemoveSheet = true
                            } label: {
                                Text(verbatim: CoachRemovalCopy.menuItem(athlete: destination.name))
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Athlete menu")
                }
            }
        }
        .sheet(isPresented: $showsWelcomeEditor) {
            CoachWelcomeEditor(athlete: destination)
        }
        .sheet(isPresented: $showsRemoveSheet) {
            RemoveAthleteSheet(athleteName: destination.name, model: removeModel) {
                guard await removeModel.confirm(athleteID: destination.athleteID,
                                                athleteName: destination.name) else { return }
                showsRemoveSheet = false
                onRemoved()
                dismiss()
            }
        }
        .task { await model.load() }
        .task {
            await feedback.load()
            await feedback.loadReplies()
        }
        .refreshable {
            await model.load()
            await feedback.load()
            await feedback.loadReplies()
        }
        .onAppear { feedback.startReachability() }
        .onDisappear { feedback.stopReachability() }
        .sheet(item: $composer) { request in
            CoachFeedbackComposer(request: request, store: feedback,
                                  onSaved: { feedback.upsert($0) }, onRevoked: { feedback.markRevoked() })
        }
        .onChange(of: feedback.revoked) { _, revoked in
            if revoked { Task { await model.load() } }
        }
        .onChange(of: model.updatedAt) { _, _ in focusRequestedDay() }
        .navigationDestination(item: $focusedDayISO) { iso in
            if let day = dayFor(iso), let strip = weekContaining(iso) {
                CoachDayDetailView(
                    day: day, calendar: model.calendar, name: destination.name, feedback: feedback,
                    weekStart: CoachReadDay.iso(strip.start, calendar: model.calendar), sharing: sharing
                )
            }
        }
        .onChange(of: model.revoked) { _, revoked in
            guard revoked, !destination.coachV2 else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                dismiss()
            }
        }
    }

    /// C7.3 AC4: effort and notes reach the day detail only while Coach v2 is on.
    private var sharing: CoachDaySharing? {
        destination.coachV2 ? CoachDaySharing(athleteName: destination.name, notes: model.runNotes) : nil
    }

    private func weekContaining(_ iso: String) -> CoachAthleteWeekDays? {
        [model.current, model.previous].compactMap { $0 }.first { $0.days.contains { $0.iso == iso } }
    }

    private func dayFor(_ iso: String) -> CoachDay? { weekContaining(iso)?.days.first { $0.iso == iso } }

    /// C7.1 AC10: a row tap opens the athlete on the reason's day. Runs once, so Back returns to the week.
    private func focusRequestedDay() {
        guard !didFocus, let iso = destination.focusDayISO, destination.coachV2,
              !model.revoked, !model.failure, model.updatedAt != nil, dayFor(iso) != nil else { return }
        didFocus = true
        focusedDayISO = iso
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(LeaveCoachCopy.monogram(for: destination.name))
                .font(.labelLG)
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 44, height: 44)
                .background(Color.surfaceElevated, in: Circle())
                .accessibilityHidden(true)
            Text(destination.name)
                .font(.headingLG)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.revoked {
            ContentCard {
                if destination.coachV2 {
                    // UX spec A.5, revoked mid-session (v2 copy).
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(destination.name) is no longer linked to you.")
                            .foregroundStyle(Color.textPrimary)
                        Button("Back to Today") { dismiss() }
                            .buttonStyle(NeonButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("\(destination.name) is no longer in your group")
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            if model.failure {
                ContentCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.offline ? "You're offline." : "Couldn't load \(destination.name)'s week.")
                            .foregroundStyle(Color.textPrimary)
                        if let date = model.updatedAt {
                            Text("Updated \(date, format: .relative(presentation: .named))")
                                .foregroundStyle(Color.textSecondary)
                        }
                        Button("Retry") { Task { await model.load() } }
                            .buttonStyle(NeonButtonStyle())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if model.updatedAt == nil && !model.failure {
                skeleton
            } else {
                if !model.hasPlan {
                    ContentCard {
                        Text("No plan yet").foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                weeks
            }
        }
    }

    // Recorded runs stay visible without a plan: they show as extra runs.
    @ViewBuilder
    private var weeks: some View {
        if model.showsWeeks, let current = model.current {
            if !model.hasRuns {
                Text("No runs yet").font(.bodyMD).foregroundStyle(Color.textSecondary)
            }
            Text("This week").font(.headingMD).accessibilityAddTraits(.isHeader)
            CoachWeekStrip(week: current, calendar: model.calendar, name: destination.name, feedback: feedback,
                           sharing: sharing)
            weekNote(current)
            if let previous = model.previous {
                DisclosureGroup(isExpanded: $showsPreviousWeek) {
                    VStack(alignment: .leading, spacing: 10) {
                        CoachWeekStrip(week: previous, calendar: model.calendar, name: destination.name, feedback: feedback,
                                       sharing: sharing)
                        weekNote(previous)
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Last week").font(.headingMD).foregroundStyle(Color.textPrimary)
                }
                .tint(Color.accentPrimary)
            }
        } else if let current = model.current {
            // No plan and no runs yet: the strip stays hidden, but a week note still works.
            weekNote(current)
        }
    }

    private func weekNote(_ week: CoachAthleteWeekDays) -> some View {
        let start = CoachReadDay.iso(week.start, calendar: model.calendar)
        return CoachFeedbackSection(store: feedback, target: .week(start), weekStart: start,
                                    buttonTitle: "Week note") { composer = $0 }
    }

    private var skeleton: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8).frame(height: 56)
                    }
                }
                Capsule().frame(width: 160, height: 10)
                Capsule().frame(width: 110, height: 8)
            }
            .foregroundStyle(Color.textSecondary.opacity(0.2))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(destination.name)'s week")
    }
}

/// Seven day cells in the coach's week order; a vertical day list at XXL Dynamic Type.
struct CoachWeekStrip: View {
    let week: CoachAthleteWeekDays
    let calendar: Calendar
    let name: String
    var feedback: CoachFeedbackStore?
    var sharing: CoachDaySharing?
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        if size >= .xxLarge {
            VStack(spacing: 8) {
                ForEach(week.days) { day in link(day) { CoachDayRow(day: day, calendar: calendar) } }
            }
        } else {
            // Spacing 4 keeps each cell at least 44 pt wide on a 375 pt phone.
            HStack(spacing: 4) {
                ForEach(week.days) { day in link(day) { CoachDayCell(day: day, calendar: calendar) } }
            }
        }
    }

    private func link<Label: View>(_ day: CoachDay, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            CoachDayDetailView(day: day, calendar: calendar, name: name, feedback: feedback,
                               weekStart: CoachReadDay.iso(week.start, calendar: calendar), sharing: sharing)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CoachMetricFormat.spokenDay(day, calendar: calendar))
        .accessibilityAddTraits(.isButton)
    }
}

private extension CoachDayMarker {
    var color: Color {
        switch self {
        case .done: Color.accentSuccess
        case .partial: Color.accentEnergy
        case .missed: Color.accentHeart
        case .extra: Color.accentRecovery
        case .planned, .rest: Color.textSecondary
        }
    }
}

private struct CoachDayCell: View {
    let day: CoachDay
    let calendar: Calendar

    var body: some View {
        let marker = day.marker
        VStack(spacing: 4) {
            Text(day.date, format: Date.FormatStyle(calendar: calendar).weekday(.narrow))
                .font(.labelSM)
                .foregroundStyle(Color.textSecondary)
            Image(systemName: marker.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(marker.color)
            Text(marker == .rest ? "Rest" : marker.label)
                .font(.labelSM)
                .foregroundStyle(marker.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CoachDayRow: View {
    let day: CoachDay
    let calendar: Calendar

    var body: some View {
        let marker = day.marker
        HStack(spacing: 12) {
            Image(systemName: marker.icon).foregroundStyle(marker.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date, format: Date.FormatStyle(calendar: calendar).weekday(.wide).day().month(.wide))
                    .font(.bodyLG)
                    .foregroundStyle(Color.textPrimary)
                Text(marker.label).font(.bodyMD).foregroundStyle(marker.color)
            }
            Spacer()
            Image(systemName: "chevron.forward").foregroundStyle(Color.textSecondary)
        }
        .padding(12)
        .frame(minHeight: 44)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// C6 Day detail: Planned and Actual side by side.
struct CoachDayDetailView: View {
    let day: CoachDay
    let calendar: Calendar
    let name: String
    var feedback: CoachFeedbackStore?
    var weekStart = ""
    var sharing: CoachDaySharing?
    @State private var composer: CoachFeedbackRequest?
    /// Several runs on one day each load a map; a revoked link is handled once.
    @State private var handledRevoke = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            CoachDayDetailContent(day: day, calendar: calendar, feedback: feedback, weekStart: weekStart,
                                  sharing: sharing, open: { composer = $0 },
                                  onRunRevoked: {
                                      // Back to the athlete screen, which shows "no longer in your group".
                                      guard !handledRevoke else { return }
                                      handledRevoke = true
                                      feedback?.markRevoked()
                                      dismiss()
                                  })
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 140)
        }
        .navigationTitle(Text(day.date, format: Date.FormatStyle(calendar: calendar).weekday(.wide).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $composer) { request in
            if let feedback {
                CoachFeedbackComposer(request: request, store: feedback, onSaved: { feedback.upsert($0) }) {
                    feedback.markRevoked()
                    // Back to the athlete screen, which shows the "no longer in your group" state.
                    dismiss()
                }
            }
        }
    }
}

struct CoachDayDetailContent: View {
    let day: CoachDay
    let calendar: Calendar
    var feedback: CoachFeedbackStore?
    var weekStart = ""
    /// C7.3 AC4: shared effort and notes. Nil (Coach v2 off) shows neither.
    var sharing: CoachDaySharing?
    var open: (CoachFeedbackRequest) -> Void = { _ in }
    /// Set by the day detail to show each run's map (Story 6.2). Nil draws no map.
    var onRunRevoked: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if day.workouts.isEmpty && day.extraRuns.isEmpty {
                ContentCard {
                    Text("Rest day").foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(day.workouts) { item in
                workoutCard(item)
                if let run = item.run {
                    mapBlock(run)
                    feedbackSection(run)
                }
            }
            ForEach(day.extraRuns, id: \.id) { run in
                extraCard(run)
                mapBlock(run)
                feedbackSection(run)
            }
        }
    }

    private func workoutCard(_ item: CoachDayWorkout) -> some View {
        let workout = item.workout
        let run = item.run
        let marker = CoachDayMarker(item.state)
        return ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(CoachMetricFormat.workoutTitle(workout.type)).font(.headingMD)
                    Spacer()
                    Label(marker.label, systemImage: marker.icon)
                        .font(.labelLG)
                        .foregroundStyle(marker.color)
                }
                if item.matchedByDate {
                    Text("Matched by date").font(.labelLG).foregroundStyle(Color.textSecondary)
                }
                columnsHeader
                metricRow("Date", planned: dayText(day.date), actual: run.map { dayText($0.completedAt) })
                metricRow(
                    "Distance",
                    planned: workout.plannedDistance > 0 ? CoachMetricFormat.distance(workout.plannedDistance) : nil,
                    actual: run.map { CoachMetricFormat.distance($0.distanceKm) },
                    difference: run.flatMap {
                        CoachMetricFormat.distanceDifference(planned: workout.plannedDistance, actual: $0.distanceKm)
                    }
                )
                metricRow(
                    "Duration",
                    planned: workout.plannedDurationMinutes.flatMap { $0 > 0 ? CoachMetricFormat.duration(seconds: $0 * 60) : nil },
                    actual: run.map { CoachMetricFormat.duration(seconds: $0.durationSeconds) },
                    difference: run.flatMap { run in
                        workout.plannedDurationMinutes.flatMap {
                            CoachMetricFormat.durationDifference(plannedMinutes: $0, actualSeconds: run.durationSeconds)
                        }
                    }
                )
                metricRow(
                    "Pace",
                    planned: workout.targetPace.flatMap { $0 > 0 ? CoachMetricFormat.pace(secondsPerKm: $0) : nil },
                    actual: run.flatMap(CoachMetricFormat.paceSeconds).map(CoachMetricFormat.pace)
                )
                metricRow("Avg HR", planned: nil, actual: run?.averageHeartRate.map(CoachMetricFormat.heartRate))
                if let run { sharingLines(run) }
                if run == nil {
                    Text(item.state == .missed ? "Missed" : "Not run yet")
                        .font(.bodyMD)
                        .foregroundStyle(item.state == .missed ? Color.accentHeart : Color.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func mapBlock(_ run: CoachRunSummary) -> some View {
        if let onRunRevoked {
            CoachRunMapBlock(run: run, calendar: calendar, onRevoked: onRunRevoked)
        }
    }

    @ViewBuilder
    private func feedbackSection(_ run: CoachRunSummary) -> some View {
        if let feedback {
            CoachFeedbackSection(store: feedback, target: .run(Int64(run.id)), weekStart: weekStart,
                                 buttonTitle: "Write feedback", open: open)
        }
    }

    private func extraCard(_ run: CoachRunSummary) -> some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Extra run", systemImage: CoachDayMarker.extra.icon)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                columnsHeader
                metricRow("Date", planned: nil, actual: dayText(run.completedAt))
                metricRow("Distance", planned: nil, actual: CoachMetricFormat.distance(run.distanceKm))
                metricRow("Duration", planned: nil, actual: CoachMetricFormat.duration(seconds: run.durationSeconds))
                metricRow("Pace", planned: nil, actual: CoachMetricFormat.paceSeconds(for: run).map(CoachMetricFormat.pace))
                metricRow("Avg HR", planned: nil, actual: run.averageHeartRate.map(CoachMetricFormat.heartRate))
                sharingLines(run)
            }
        }
    }

    /// C7.3 AC4: "Effort 7/10", then the note in quotes with the athlete's name under it.
    /// The note keeps its own direction (a Hebrew note in an English screen reads right to left).
    @ViewBuilder
    private func sharingLines(_ run: CoachRunSummary) -> some View {
        let lines = CoachRunSharingLines(run: run, sharing: sharing)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(Color.textSecondary.opacity(0.2))
                if let effort = lines.effort {
                    Text(effort)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .accessibilityLabel(lines.spokenEffort ?? effort)
                }
                if let note = lines.note, let attribution = lines.attribution {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note)
                            .font(.bodyMD)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .naturalTextDirection(note)
                        Text(attribution)
                            .font(.labelLG)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(lines.spokenNote ?? note)
                }
            }
        }
    }

    private var columnsHeader: some View {
        HStack {
            Text("").frame(width: 76, alignment: .leading)
            Text("Planned").frame(maxWidth: .infinity, alignment: .leading)
            Text("Actual").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.labelLG)
        .foregroundStyle(Color.textSecondary)
        .accessibilityHidden(true)
    }

    private func metricRow(_ title: String, planned: String?, actual: String?, difference: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.bodyMD).foregroundStyle(Color.textSecondary).frame(width: 76, alignment: .leading)
            Text(planned ?? "—").font(.bodyMD).foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(actual ?? "—").font(.bodyMD).foregroundStyle(Color.textPrimary)
                if let difference {
                    Text(difference).font(.labelLG).foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). Planned \(planned ?? "none"). Actual \(actual ?? "none")\(difference.map { ", \($0)" } ?? "").")
    }

    private func dayText(_ date: Date) -> String {
        CoachMetricFormat.isolate(date.formatted(Date.FormatStyle(calendar: calendar).day().month(.abbreviated)))
    }
}

// MARK: C7.11 remove confirm

/// "Remove {Athlete}?" Lists the effects, with Cancel and Remove the same size and no timer,
/// like the athlete's A13 leave sheet. Cancel calls nothing.
struct RemoveAthleteSheet: View {
    let athleteName: String
    @ObservedObject var model: RemoveAthleteModel
    var onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pathMonitor: NWPathMonitor?

    var body: some View {
        ScrollView {
            RemoveAthleteSheetContent(athleteName: athleteName, model: model, onCancel: {
                model.cancel()
                dismiss()
            }, onConfirm: onConfirm)
            .padding(20)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isWorking)
        .onAppear(perform: startReachability)
        .onDisappear {
            pathMonitor?.cancel()
            pathMonitor = nil
        }
    }

    private func startReachability() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in model.isOnline = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "remove-athlete-path"))
        pathMonitor = monitor
    }
}

/// The sheet's content, split out so the screenshot test renders it without a sheet.
struct RemoveAthleteSheetContent: View {
    let athleteName: String
    @ObservedObject var model: RemoveAthleteModel
    var onCancel: () -> Void
    var onConfirm: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: CoachRemovalCopy.title(athlete: athleteName))
                .font(.headingLG)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: CoachRemovalCopy.sheet(athlete: athleteName))
                .font(.bodyMD)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.isOnline ? model.errorMessage : CoachRemovalCopy.offline {
                Text(verbatim: message)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.accentAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                // Same size on purpose: the labels fill each half, so neither action looks preferred.
                Button(action: onCancel) {
                    Text(CoachRemovalCopy.cancel)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking)

                Button {
                    Task { await onConfirm() }
                } label: {
                    Group {
                        if model.isWorking {
                            ProgressView()
                        } else {
                            Text(verbatim: CoachRemovalCopy.menuItem(athlete: athleteName))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!model.isOnline || model.isWorking)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
