import Combine
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
    private(set) var calendar = Calendar(identifier: .gregorian)
    let athleteID: UUID
    private let service: any CoachReadServing
    private var inFlight: Task<Void, Never>?

    init(athleteID: UUID, service: any CoachReadServing = CoachReadService()) {
        self.athleteID = athleteID
        self.service = service
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
            let weeks = CoachAthleteDays.weeks(
                workouts: workouts.filter { $0.athleteID == athleteID },
                runs: runs.filter { $0.athleteID == athleteID }, now: now, week: week
            )
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

    init(destination: CoachAthleteDestination, service: any CoachReadServing = CoachReadService(),
         feedbackService: any CoachFeedbackServing = SupabaseCoachFeedbackService()) {
        self.destination = destination
        _model = StateObject(wrappedValue: CoachAthleteDetailModel(athleteID: destination.athleteID, service: service))
        _feedback = StateObject(wrappedValue: CoachFeedbackStore(
            athleteID: destination.athleteID, athleteName: destination.name, service: feedbackService
        ))
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
        .task { await model.load() }
        .task { await feedback.load() }
        .refreshable {
            await model.load()
            await feedback.load()
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
        .onChange(of: model.revoked) { _, revoked in
            guard revoked else { return }
            Task {
                try? await Task.sleep(for: .seconds(2))
                dismiss()
            }
        }
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
                Text("\(destination.name) is no longer in your group")
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            CoachWeekStrip(week: current, calendar: model.calendar, name: destination.name, feedback: feedback)
            weekNote(current)
            if let previous = model.previous {
                DisclosureGroup(isExpanded: $showsPreviousWeek) {
                    VStack(alignment: .leading, spacing: 10) {
                        CoachWeekStrip(week: previous, calendar: model.calendar, name: destination.name, feedback: feedback)
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
                               weekStart: CoachReadDay.iso(week.start, calendar: calendar))
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
    @State private var composer: CoachFeedbackRequest?
    /// Several runs on one day each load a map; a revoked link is handled once.
    @State private var handledRevoke = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            CoachDayDetailContent(day: day, calendar: calendar, feedback: feedback, weekStart: weekStart,
                                  open: { composer = $0 },
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
