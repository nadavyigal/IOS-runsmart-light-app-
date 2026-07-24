import CoreLocation
import SwiftUI

enum SecondaryDestination: Hashable, Identifiable {
    case workoutDetail(WorkoutSummary)
    case planAdjustment
    case reschedule(WorkoutSummary)
    case amendWorkout(WorkoutSummary)
    case addActivity
    case routeSelector
    case runReport(DBGarminActivity)
    case runReportDetail(RunReportDetail)
    case postRunSummary(RecordedRun?)
    case audioCues
    case lapMarker
    case voiceCoaching
    case coachingTone
    case trainingData
    case goalFocus
    case reminders
    case connectedService(String)
    case challenges
    case recoveryDashboard
    case morningCheckin
    case goalWizard
    case weeklyRecap
    case wellnessTrends
    case zoneAnalysis
    case routeCreator
    case badgeCabinet
    case shareRun(RecordedRun?)
    case routeDetail(SavedRoute)
    case account

    var id: String {
        switch self {
        case .workoutDetail(let w): "workoutDetail-\(w.id)"
        case .planAdjustment: "planAdjustment"
        case .reschedule(let w): "reschedule-\(w.id)"
        case .amendWorkout(let w): "amendWorkout-\(w.id)"
        case .addActivity: "addActivity"
        case .routeSelector: "routeSelector"
        case .runReport(let activity): "runReport-\(activity.id)"
        case .runReportDetail(let report): "runReportDetail-\(report.id)"
        case .postRunSummary(let run): "postRunSummary-\(run?.id.uuidString ?? "nil")"
        case .audioCues: "audioCues"
        case .lapMarker: "lapMarker"
        case .voiceCoaching: "voiceCoaching"
        case .coachingTone: "coachingTone"
        case .trainingData: "trainingData"
        case .goalFocus: "goalFocus"
        case .reminders: "reminders"
        case .connectedService(let name): "connectedService-\(name)"
        case .challenges: "challenges"
        case .recoveryDashboard: "recoveryDashboard"
        case .morningCheckin: "morningCheckin"
        case .goalWizard: "goalWizard"
        case .weeklyRecap: "weeklyRecap"
        case .wellnessTrends: "wellnessTrends"
        case .zoneAnalysis: "zoneAnalysis"
        case .routeCreator: "routeCreator"
        case .badgeCabinet: "badgeCabinet"
        case .shareRun(let run): "shareRun-\(run?.id.uuidString ?? "nil")"
        case .routeDetail(let route): "routeDetail-\(route.id)"
        case .account: "account"
        }
    }

    var title: String {
        switch self {
        case .workoutDetail(let w): w.title
        case .planAdjustment: "Plan Adjustment"
        case .reschedule: "Reschedule"
        case .amendWorkout: "Amend Workout"
        case .addActivity: "Add Activity"
        case .routeSelector: "Route Selector"
        case .runReport, .runReportDetail: "Run Report"
        case .postRunSummary: "Post-Run Summary"
        case .audioCues: "Audio Cues"
        case .lapMarker: "Lap Marker"
        case .voiceCoaching: "Voice Coaching"
        case .coachingTone: "Coaching Tone"
        case .trainingData: "Training Data"
        case .goalFocus: "Goal Focus"
        case .reminders: "Reminders & Preferences"
        case .connectedService(let name): name
        case .challenges: "Challenges"
        case .recoveryDashboard: "Recovery"
        case .morningCheckin: "Morning Check-In"
        case .goalWizard: "Goal Wizard"
        case .weeklyRecap: "Weekly Recap"
        case .wellnessTrends: "Wellness Trends"
        case .zoneAnalysis: "Zone Analysis"
        case .routeCreator: "Route Creator"
        case .badgeCabinet: "Badge Cabinet"
        case .shareRun: "Share Run"
        case .routeDetail(let route): route.name
        case .account: "Account"
        }
    }

    var subtitle: String {
        switch self {
        case .workoutDetail:
            "Session plan, purpose, and execution cues."
        case .planAdjustment:
            "Coach logic for safe plan changes."
        case .reschedule:
            "Move a workout without spiking weekly load."
        case .amendWorkout:
            "Adjust the workout details in your active plan."
        case .addActivity:
            "Log a manual run or cross-training session."
        case .routeSelector:
            "Choose a route that fits today's workout."
        case .runReport, .runReportDetail:
            "Review a saved run from your history."
        case .postRunSummary:
            "Review effort and save the completed run."
        case .audioCues:
            "Tune voice prompts, timing, and coaching moments."
        case .lapMarker:
            "Capture a split and annotate the effort."
        case .voiceCoaching:
            "Manage reminder and cue preferences for planned training."
        case .coachingTone:
            "Pick the coach personality for future guidance."
        case .trainingData:
            "Save the baseline your coach uses to size training load."
        case .goalFocus:
            "Tell the coach what to optimize this block around."
        case .reminders:
            "Schedule nudges, check-ins, and recovery prompts."
        case .connectedService:
            "Inspect sync status, permissions, and controls."
        case .challenges:
            "Adopt a challenge and track your progress."
        case .recoveryDashboard:
            "Readiness, sleep, HRV, and recovery signals."
        case .morningCheckin:
            "Capture how the runner feels before training."
        case .goalWizard:
            "Set or revise the training goal."
        case .weeklyRecap:
            "Summarize the week and next coaching move."
        case .wellnessTrends:
            "Body Battery, HRV, and recovery trends from your connected device."
        case .zoneAnalysis:
            "Understand effort distribution and heart rate zones."
        case .routeCreator:
            "Build a route that matches the workout."
        case .badgeCabinet:
            "Browse earned and locked achievements."
        case .shareRun:
            "Prepare a polished run share card."
        case .routeDetail:
            "Route details, benchmark stats, and actions."
        case .account:
            "Manage your sign-in and profile data."
        }
    }

    var symbol: String {
        switch self {
        case .workoutDetail(let workout): workout.kind.symbol
        case .planAdjustment: "slider.horizontal.3"
        case .reschedule: "calendar.badge.clock"
        case .amendWorkout: "slider.horizontal.3"
        case .addActivity: "plus.circle.fill"
        case .routeSelector: "map.fill"
        case .runReport, .runReportDetail: "chart.xyaxis.line"
        case .postRunSummary: "checkmark.seal.fill"
        case .audioCues: "speaker.wave.2.fill"
        case .lapMarker: "flag.fill"
        case .voiceCoaching: "waveform"
        case .coachingTone: "sparkles"
        case .trainingData: "figure.run"
        case .goalFocus: "target"
        case .reminders: "bell.badge.fill"
        case .connectedService: "link.circle.fill"
        case .challenges: "trophy.fill"
        case .recoveryDashboard: "heart.text.square.fill"
        case .morningCheckin: "sunrise.fill"
        case .goalWizard: "target"
        case .weeklyRecap: "calendar.badge.checkmark"
        case .wellnessTrends: "waveform.path.ecg"
        case .zoneAnalysis: "heart.circle.fill"
        case .routeCreator: "point.topleft.down.curvedto.point.bottomright.up"
        case .badgeCabinet: "seal.fill"
        case .shareRun: "square.and.arrow.up"
        case .routeDetail: "map.fill"
        case .account: "person.crop.circle.fill"
        }
    }
}

struct SecondaryFlowView: View {
    var destination: SecondaryDestination

    var body: some View {
        ZStack {
            RunSmartBackground()
            SecondaryContentView(destination: destination)
        }
        .preferredColorScheme(.dark)
    }
}

private struct SecondaryContentView: View {
    var destination: SecondaryDestination

    var body: some View {
        if destination == .goalWizard {
            GoalWizardView()
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
                    FlowHeader(destination: destination)
                    content
                    Spacer(minLength: 20)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(20)
                .padding(.bottom, destination == .trainingData ? 120 : 0)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .workoutDetail(let workout):
            WorkoutDetailScaffold(workout: workout)
        case .planAdjustment:
            PlanAdjustmentScaffold()
        case .reschedule(let workout):
            RescheduleScaffold(workout: workout)
        case .amendWorkout(let workout):
            AmendWorkoutScaffold(workout: workout)
        case .addActivity:
            AddActivityScaffold()
        case .routeSelector:
            RouteSelectorScaffold()
        case .runReport(let activity):
            RunReportScaffold(activity: activity)
        case .runReportDetail(let report):
            RunReportDetailScaffold(report: report)
        case .postRunSummary(let run):
            PostRunSummaryScaffold(run: run)
        case .audioCues:
            AudioCuesScaffold()
        case .lapMarker:
            LapMarkerScaffold()
        case .voiceCoaching:
            VoiceCoachingScaffold()
        case .coachingTone:
            CoachingToneScaffold()
        case .trainingData:
            TrainingDataEditor()
        case .goalFocus:
            GoalFocusEditor()
        case .reminders:
            ReminderPreferencesScaffold()
        case .connectedService(let serviceName):
            ConnectedServiceDetailScaffold(serviceName: serviceName)
        case .challenges:
            ChallengesListView()
        case .recoveryDashboard:
            RecoveryDashboardView()
        case .morningCheckin:
            MorningCheckinView()
        case .goalWizard:
            GoalWizardView()
        case .weeklyRecap:
            WeeklyRecapView()
        case .wellnessTrends:
            WellnessTrendsView()
        case .zoneAnalysis:
            ZoneAnalysisView()
        case .routeCreator:
            RouteCreatorView()
        case .badgeCabinet:
            BadgeCabinetView()
        case .shareRun(let run):
            ShareRunView(run: run)
        case .routeDetail(let route):
            RouteDetailScaffold(route: route)
        case .account:
            AccountScaffold()
        }
    }
}

private struct FlowHeader: View {
    var destination: SecondaryDestination

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            headerMark

            VStack(alignment: .leading, spacing: 6) {
                Text(destination.title)
                    .font(.displayMD)
                    .foregroundStyle(Color.textPrimary)
                Text(destination.subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.top, 8)
    }

    /// Header mark. For third-party connected services (e.g. Garmin Connect) we must NOT pair the
    /// RunSmart logo with the service name — Garmin's API Brand Guidelines treat that as implying
    /// ownership of Garmin Connect. True only for destinations whose title itself is a vendor
    /// trademark (e.g. "Garmin Connect", "HealthKit"). Screens that merely display device-sourced
    /// data under a RunSmart-owned name (Recovery, Wellness Trends) attribute the device inline in
    /// their content instead and keep the normal RunSmart header.
    private var usesNeutralServiceMark: Bool {
        switch destination {
        case .connectedService: true
        default: false
        }
    }

    /// True only for Garmin Connect authentication — not other health surfaces.
    private var usesGarminConnectTile: Bool {
        switch destination {
        case .connectedService(let name): name.localizedCaseInsensitiveContains("garmin")
        default: false
        }
    }

    @ViewBuilder
    private var headerMark: some View {
        if usesGarminConnectTile {
            GarminConnectBrandMark.headerTile()
        } else if usesNeutralServiceMark {
            Image(systemName: destination.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 58, height: 58)
                .background(Color.textTertiary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            RunSmartLogoMark(size: 58)
                .shadow(color: Color.accentPrimary.opacity(0.38), radius: 16)
        }
    }
}

private struct WorkoutDetailScaffold: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var workout: WorkoutSummary
    @State private var runMode = "Outdoor"
    @State private var isRemoving = false

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Workout", trailing: workout.distance)
                    Text(workout.title)
                        .font(.title2.bold())
                    if !workout.detail.isEmpty {
                        Text(workout.detail)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.84))
                    } else {
                        Text(workoutPurpose)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.84))
                    }

                    HStack(spacing: 8) {
                        FlowChip(text: workout.distance, symbol: "point.topleft.down.curvedto.point.bottomright.up")
                        if let mins = workout.durationMinutes {
                            FlowChip(text: "\(mins) min", symbol: "clock")
                        } else {
                            FlowChip(text: estimatedDuration, symbol: "clock")
                        }
                        if let paceStr = StructuredWorkoutFactory.derivedPaceLabel(workout: workout) {
                            FlowChip(text: paceStr, symbol: "speedometer")
                        } else {
                            FlowChip(text: targetZone, symbol: "heart")
                        }
                        if let phase = workout.trainingPhase {
                            FlowChip(text: phase, symbol: "flag")
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Plan Tools")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ActionTile(title: "Warm-Up Stretches", symbol: "line.3.horizontal") {}
                        ActionTile(title: "Add Route", symbol: "mappin.and.ellipse") { router.open(.routeSelector) }
                        ActionTile(title: "Link Activity", symbol: "link") { router.open(.addActivity) }
                        ActionTile(title: isRemoving ? "Removing" : "Remove Workout", symbol: "trash", tint: .red) {
                            Task { await removeWorkout() }
                        }
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(["Outdoor", "Treadmill"], id: \.self) { mode in
                    Button { runMode = mode } label: {
                        Text(mode.uppercased())
                            .font(.headline)
                            .foregroundStyle(runMode == mode ? Color.black : Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(runMode == mode ? Color.lime : Color.white.opacity(0.045))
                    }
                    .buttonStyle(.plain)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "square")
                            .foregroundStyle(Color.mutedText)
                        Text("Workout Breakdown")
                            .font(.headline)
                        Spacer()
                    }
                    Text(workout.workoutStructure?.isEmpty == false ? "From the saved plan structure." : "Estimated from the saved workout targets.")
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                    if let steps = StructuredWorkoutFactory.makeSteps(for: workout) {
                        ForEach(steps) { step in
                            WorkoutStepRow(step: step)
                        }
                    } else {
                        Text("Workout breakdown unavailable for this plan item.")
                            .font(.subheadline)
                            .foregroundStyle(Color.mutedText)
                            .padding(.vertical, 8)
                    }
                }
            }

            Button {
                router.startRun(with: workout)
            } label: {
                Text("Start This Workout")
                    .font(.headline)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.lime)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Coach Actions")
                    ActionRow(title: "Reschedule Workout", detail: "Move this session and preserve weekly balance.", symbol: "calendar.badge.clock") {
                        router.open(.reschedule(workout))
                    }
                    ActionRow(title: "Amend Workout", detail: "Update distance, duration, pace, or notes.", symbol: "slider.horizontal.3") {
                        router.open(.amendWorkout(workout))
                    }
                    ActionRow(title: "Choose Route", detail: "Pick a route that matches the target effort.", symbol: "map") {
                        router.open(.routeSelector)
                    }
                    ActionRow(title: "Adjust Plan", detail: "Ask the coach to reshuffle the week.", symbol: "slider.horizontal.3") {
                        router.open(.planAdjustment)
                    }
                }
            }
        }
    }

    private var workoutPurpose: String {
        switch workout.kind {
        case .easy, .parkrun:
            return "Build aerobic habit with relaxed effort. The goal is finishing smooth, not proving fitness."
        case .tempo:
            return "Build controlled threshold fitness without turning the workout into a race."
        case .intervals:
            return "Practice faster running with full control and clean recoveries between efforts."
        case .hills:
            return "Build strength and running economy with short, powerful climbs."
        case .long:
            return "Grow endurance at conversational effort and keep the last third calm."
        case .race:
            return "Execute the plan with a patient start, steady middle, and focused finish."
        case .strength:
            return "Support stronger running mechanics without adding impact load."
        case .recovery:
            return "Absorb the week. Keep movement easy and leave fresher than you started."
        }
    }

    private var estimatedDuration: String {
        switch workout.kind {
        case .long: "70-90 min"
        case .tempo, .intervals, .hills: "45-55 min"
        case .race: "Goal effort"
        case .strength: "40 min"
        case .recovery: "20-30 min"
        default: "25-35 min"
        }
    }

    // WP-44 S3: single-sourced effort vocabulary (was a second, drifting
    // kind→zone mapper).
    private var targetZone: String {
        TrainingMetrics.effortLabel(for: workout.kind)
    }

    private func removeWorkout() async {
        guard !isRemoving else { return }
        isRemoving = true
        let removed = await services.removeWorkout(workoutID: workout.id)
        isRemoving = false
        if removed {
            dismiss()
        }
    }
}

private struct PlanAdjustmentScaffold: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Coach Assessment")
                    Text("Plan changes now write to your real RunSmart training plan. Open a workout to move, remove, or start it; use the goal wizard to regenerate the block from the web coach.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Available Changes")
                    ActionRow(title: "Regenerate Goal Plan", detail: "Create a new web-parity plan from your saved goal.", symbol: "target") {
                        router.open(.goalWizard)
                    }
                    ActionRow(title: "Add Missing Activity", detail: "Log a completed run so reports and plan context stay honest.", symbol: "plus.circle.fill") {
                        router.open(.addActivity)
                    }
                }
            }

            Button(action: { router.open(.addActivity) }) {
                Label("Add Missing Activity", systemImage: "plus.circle.fill")
            }
            .buttonStyle(NeonButtonStyle())
        }
    }
}

private struct RescheduleScaffold: View {
    @Environment(\.runSmartServices) private var services
    @Environment(\.dismiss) private var dismiss

    var workout: WorkoutSummary
    @State private var isSaving = false

    private var options: [(day: String, fit: String, detail: String, date: Date)] {
        let calendar = Calendar.current
        let start = Calendar.current.startOfDay(for: Date())
        return [
            ("Tomorrow", "Best fit", "Keeps the plan moving without inventing a new workout.", calendar.date(byAdding: .day, value: 1, to: start) ?? start),
            ("In 2 days", "Good", "Adds a little more recovery before the session.", calendar.date(byAdding: .day, value: 2, to: start) ?? start),
            ("Next week", "Caution", "Use only when this week is no longer realistic.", calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Moving", trailing: workout.distance)
                    Text(workout.title)
                        .font(.title2.bold())
                    Text("Coach Spark checks load spacing before suggesting a new day.")
                        .foregroundStyle(Color.mutedText)
                }
            }

            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    move(to: option.date)
                } label: {
                    GlassCard {
                        HStack(spacing: 12) {
                            Image(systemName: option.fit == "Best fit" ? "checkmark.circle.fill" : "calendar")
                                .foregroundStyle(option.fit == "Best fit" ? Color.lime : Color.mutedText)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.day)
                                    .font(.headline)
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.mutedText)
                            }
                            Spacer()
                            Text(isSaving ? "Saving" : option.fit)
                                .font(.caption.bold())
                                .foregroundStyle(option.fit == "Caution" ? Color.orange : Color.lime)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
    }

    private func move(to date: Date) {
        Task {
            await moveAsync(to: date)
        }
    }

    private func moveAsync(to date: Date) async {
        isSaving = true
        let moved: Bool
        if Calendar.current.isDate(date, inSameDayAs: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? date) {
            moved = await services.pushWorkoutTomorrow(workoutID: workout.id)
        } else {
            moved = await services.moveWorkout(workoutID: workout.id, to: date)
        }
        isSaving = false
        if moved {
            dismiss()
        }
    }

}

private struct AmendWorkoutScaffold: View {
    @Environment(\.runSmartServices) private var services
    @Environment(\.dismiss) private var dismiss

    var workout: WorkoutSummary

    @State private var kind: WorkoutKind
    @State private var distanceKm: Double
    @State private var durationMinutes: Int
    @State private var paceMinutes: Int
    @State private var paceSeconds: Int
    @State private var notes: String
    @State private var isSaving = false
    @State private var failed = false

    private let kinds: [WorkoutKind] = [.easy, .tempo, .intervals, .hills, .long, .race, .recovery]

    init(workout: WorkoutSummary) {
        self.workout = workout
        _kind = State(initialValue: workout.kind)
        _distanceKm = State(initialValue: Self.distanceValue(from: workout.distance))
        _durationMinutes = State(initialValue: workout.durationMinutes ?? 30)
        let pace = workout.targetPaceSecondsPerKm ?? 0
        _paceMinutes = State(initialValue: max(0, pace / 60))
        _paceSeconds = State(initialValue: max(0, pace % 60))
        _notes = State(initialValue: workout.detail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Amending", trailing: workout.weekday)
                    Text(workout.title)
                        .font(.title2.bold())
                    Text("Changes save to the active Supabase workout and refresh Today and Plan.")
                        .font(.callout)
                        .foregroundStyle(Color.mutedText)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Workout Type")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(kinds, id: \.self) { item in
                            Button { kind = item } label: {
                                FlowSelectionTile(title: item.rawValue.capitalized, value: "", symbol: item.symbol, selected: kind == item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Targets")
                    DetailLine(label: "Distance", value: String(format: "%.1f km", distanceKm))
                    Slider(value: $distanceKm, in: 0...42.2, step: 0.1)
                        .tint(Color.lime)
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 0...360, step: 5)
                    Stepper("Pace: \(paceMinutes):\(String(format: "%02d", paceSeconds)) /km", value: $paceMinutes, in: 0...12)
                    Stepper("Pace seconds: \(paceSeconds)", value: $paceSeconds, in: 0...59)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(RunSmartTextFieldStyle())
                }
            }

            if failed {
                Text("Could not save this amendment. Check your connection and try again.")
                    .font(.callout)
                    .foregroundStyle(Color.red)
            }

            Button(action: saveTapped) {
                HStack {
                    if isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Label("Save Amendment", systemImage: "checkmark")
                    }
                }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(isSaving)
        }
    }

    private func saveTapped() {
        Task {
            await save()
        }
    }

    private func save() async {
        isSaving = true
        failed = false
        let pace = paceMinutes > 0 ? (paceMinutes * 60 + paceSeconds) : nil
        let patch = WorkoutPatch(
            kind: kind,
            distanceKm: distanceKm,
            durationMinutes: durationMinutes > 0 ? durationMinutes : nil,
            targetPaceSecondsPerKm: pace,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        )
        let saved = await services.amendWorkout(workoutID: workout.id, patch: patch)
        isSaving = false
        if saved {
            dismiss()
        } else {
            failed = true
        }
    }

    private static func distanceValue(from label: String) -> Double {
        let value = label
            .replacingOccurrences(of: "km", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(value) ?? 0
    }
}

private struct AddActivityScaffold: View {
    @Environment(\.runSmartServices) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKind: WorkoutKind = .easy
    @State private var date = Date()
    @State private var distanceKm = 5.0
    @State private var durationMinutes = 30
    @State private var heartRateText = ""
    @State private var notes = ""
    @State private var savedRun: RecordedRun?
    @State private var isSaving = false

    private let runKinds: [WorkoutKind] = [.easy, .tempo, .intervals, .hills, .long, .race, .parkrun]

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Add Run")
                    Text("Add a workout to your plan, generate a guided version, or use it to keep this week's progress accurate.")
                        .font(.callout)
                        .foregroundStyle(Color.mutedText)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(runKinds, id: \.self) { kind in
                            Button { selectedKind = kind } label: {
                                AddRunKindTile(kind: kind, selected: selectedKind == kind)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Manual Entry")
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    VStack(alignment: .leading, spacing: 6) {
                        DetailLine(label: "Distance", value: String(format: "%.1f km", distanceKm))
                        Slider(value: $distanceKm, in: 0.5...42.2, step: 0.1)
                            .tint(Color.lime)
                    }
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 5...360, step: 5)
                    TextField("Average heart rate (optional)", text: $heartRateText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RunSmartTextFieldStyle())
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(RunSmartTextFieldStyle())
                }
            }

            if let savedRun {
                Label("Saved \(String(format: "%.1f", savedRun.distanceMeters / 1_000)) km to your training history.", systemImage: "checkmark.seal.fill")
                    .font(.callout.bold())
                    .foregroundStyle(Color.lime)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.lime.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button(action: saveRunTapped) {
                HStack {
                    if isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Label("Save Run", systemImage: "checkmark")
                    }
                }
            }
                .buttonStyle(NeonButtonStyle())
                .disabled(isSaving)
        }
    }

    private func saveRunTapped() {
        Task {
            await saveRun()
        }
    }

    private func saveRun() async {
        isSaving = true
        let hr = Int(heartRateText.trimmingCharacters(in: .whitespacesAndNewlines))
        let run = await services.saveManualRun(
            kind: selectedKind,
            date: date,
            distanceKm: distanceKm,
            durationMinutes: durationMinutes,
            averageHeartRateBPM: hr,
            notes: notes
        )
        savedRun = run
        isSaving = false
    }
}

private struct RouteSelectorScaffold: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @State private var allSuggestions: [RouteSuggestion] = []
    @State private var selectedRouteID: String?
    @State private var isLoading = false
    @State private var distanceFilter: Double? = nil

    private let filterOptions: [Double?] = [nil, 3, 5, 8, 10, 15]

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {

            // Distance filter bar
            RouteDistanceFilterBar(options: filterOptions, selected: $distanceFilter)

            // Route buckets
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Color.lime)
                    Text("Finding routes near you")
                        .font(.callout)
                        .foregroundStyle(Color.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if allSuggestions.isEmpty {
                RouteDiscoveryEmptyCard(
                    title: "No routes found",
                    message: "Record a GPS run or enable location to generate nearby loops.",
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
            } else {
                routeBuckets
            }

            Button {
                guard let selectedRoute else { return }
                Analytics.trackRouteUsedForRun(routeKind: selectedRoute.kind.rawValue, source: "route_selector")
                router.startRun(with: router.plannedWorkout, route: selectedRoute)
            } label: {
                Text(selectedRoute == nil ? "No Route Available" : "Use This Route")
            }
                .buttonStyle(NeonButtonStyle())
                .disabled(selectedRoute == nil)
        }
        .task { await load() }
        .onChange(of: displayedRouteIDs) { _, ids in
            reconcileSelection(with: ids)
        }
    }

    // MARK: - Buckets

    private var displayed: [RouteSuggestion] {
        RouteSuggestionRanker.filter(allSuggestions, targetDistanceKm: distanceFilter)
    }

    private var benchmarks: [RouteSuggestion] {
        displayed.filter { $0.kind == .benchmark }
    }

    private var myRoutes: [RouteSuggestion] {
        displayed.filter { $0.kind == .saved || $0.kind == .past }
    }

    private var generatedNearby: [RouteSuggestion] {
        displayed.filter { $0.kind == .generated }
    }

    @ViewBuilder
    private var routeBuckets: some View {
        let hasAny = !benchmarks.isEmpty || !myRoutes.isEmpty || !generatedNearby.isEmpty

        if !hasAny {
            RouteDiscoveryEmptyCard(
                title: "No matching routes",
                message: "Try a different distance filter.",
                systemImage: "slider.horizontal.3"
            )
        } else {
            if !benchmarks.isEmpty {
                RouteDiscoverySectionHeader(title: "Benchmarks", count: benchmarks.count)
                ForEach(benchmarks) { r in
                    FullBleedRouteCard(
                        suggestion: r,
                        isSelected: r.id == selectedRouteID,
                        onTap: { selectedRouteID = r.id },
                        onDetail: r.savedRouteID == nil ? nil : { openRouteDetail(r) }
                    )
                }
            }

            if !myRoutes.isEmpty {
                RouteDiscoverySectionHeader(title: "My Routes", count: myRoutes.count)
                ForEach(myRoutes) { r in
                    FullBleedRouteCard(
                        suggestion: r,
                        isSelected: r.id == selectedRouteID,
                        onTap: { selectedRouteID = r.id },
                        onDetail: r.savedRouteID == nil ? nil : { openRouteDetail(r) }
                    )
                }
            }

            if !generatedNearby.isEmpty {
                RouteDiscoverySectionHeader(title: "Generated Nearby", count: generatedNearby.count)
                ForEach(generatedNearby) { r in
                    FullBleedRouteCard(suggestion: r, isSelected: r.id == selectedRouteID) {
                        selectedRouteID = r.id
                    }
                }
            }
        }
    }

    /// Strictly the visible selection. The previous fallback resolved against
    /// `allSuggestions`, so an active distance filter could start a route that
    /// was filtered off screen and rendered nowhere as selected.
    private var selectedRoute: RouteSuggestion? {
        displayed.first(where: { $0.id == selectedRouteID })
    }

    private var displayedRouteIDs: [String] {
        displayed.map(\.id)
    }

    private func reconcileSelection(with ids: [String]) {
        if let selectedRouteID, ids.contains(selectedRouteID) { return }
        selectedRouteID = ids.first
    }

    private func openRouteDetail(_ suggestion: RouteSuggestion) {
        guard let savedRouteID = suggestion.savedRouteID else { return }
        Task {
            let routes = await services.savedRoutes()
            guard let route = routes.first(where: { $0.id == savedRouteID }) else { return }
            await MainActor.run {
                router.open(.routeDetail(route))
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let rankedTask = services.rankedRouteSuggestions(targetDistanceKm: nil)
        let location = await LocationLookupService.shared.currentLocation()
        let generated = await generatedSuggestions(around: location)
        let ranked = await rankedTask
        allSuggestions = mergedSuggestions(ranked + generated)
        reconcileSelection(with: displayedRouteIDs)
    }

    private func generatedSuggestions(around location: CLLocationCoordinate2D?) async -> [RouteSuggestion] {
        guard let location else { return [] }
        let generated = await services.nearbyLoopRoutes(around: location, distancesKm: [5, 8, 10])
        return generated.map { suggestion in
            var enriched = suggestion
            enriched.recommendationReason = RouteSuggestionRanker.reason(
                kind: .generated,
                distanceKm: suggestion.distanceKm,
                targetDistanceKm: nil,
                isFavorite: false,
                daysSinceLastRun: nil
            )
            return enriched
        }
    }

    private func mergedSuggestions(_ suggestions: [RouteSuggestion]) -> [RouteSuggestion] {
        var seen = Set<String>()
        return suggestions.filter { suggestion in
            guard !seen.contains(suggestion.id) else { return false }
            seen.insert(suggestion.id)
            return true
        }
    }
}

private struct RunReportScaffold: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var session: SupabaseSession
    var activity: DBGarminActivity
    @State private var routePoints: [RunRoutePoint] = []
    @State private var report: RunReportDetail?
    @State private var isGenerating = false
    @State private var generationFailed = false
    @State private var showSaveRouteSheet = false
    @State private var isLoadingRoutePoints = true
    @State private var garminDeviceName: String?

    private var garminSourceLabel: String {
        RunSmartAttribution.garminDeviceLabel(
            deviceName: activity.deviceName,
            fallbackGarminDeviceName: garminDeviceName
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Run Summary", trailing: activity.relativeStartLabel)
                    Text(activity.sportLabel)
                        .font(.title2.bold())
                    Text(garminSourceLabel)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricBadge(title: "Distance", value: activity.distanceKmLabel)
                        MetricBadge(title: "Moving time", value: activity.durationLabel)
                        MetricBadge(title: "Avg Pace", value: paceLabel)
                        MetricBadge(title: "Avg HR", value: heartRateLabel)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Details")
                    DetailLine(label: "Started", value: startTimeLabel)
                    DetailLine(label: "Elevation", value: elevationLabel)
                    DetailLine(label: "Calories", value: caloriesLabel)
                    DetailLine(label: "Source", value: garminSourceLabel)
                }
            }

            if let report {
                PostRunLearningCard(run: garminRunWithRoutePoints, outcome: nil, report: report)
                RunReportCoachNotesCard(report: report)
                BenchmarkComparisonLoaderView(run: garminRunWithRoutePoints)
                RunReportRichSignalsCard(report: report)
                RunReportNextWorkoutCard(report: report)
            } else {
                PostRunLearningCard(
                    run: garminRunWithRoutePoints,
                    outcome: nil,
                    report: nil,
                    isProcessing: isGenerating
                )
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Coach Report")
                        Text(generationFailed ? "No coach report yet. Report generation failed, but you can retry from this real activity." : "No coach report yet.")
                            .font(.callout)
                            .foregroundStyle(Color.mutedText)
                        Button(isGenerating ? "Generating..." : "Generate Report", action: generateReportTapped)
                        .buttonStyle(NeonButtonStyle())
                        .disabled(isGenerating)
                    }
                }
            }

            GlassCard(padding: 8, glow: routePoints.isEmpty ? nil : Color.lime) {
                RouteMapView(points: routePoints, title: routePoints.isEmpty ? nil : "Run Route")
                    .frame(height: 210)
            }

            if routePoints.count >= RouteMatchingService.minimumRoutePoints {
                Button {
                    showSaveRouteSheet = true
                } label: {
                    Label("Save Route", systemImage: "map.fill")
                        .font(.buttonLabel)
                        .foregroundStyle(Color.accentPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.accentPrimary.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.55), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Save this Garmin route to your route library.")
            } else if isLoadingRoutePoints {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.textSecondary)
                    Text("Loading Garmin route points.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 4)
            } else if !isLoadingRoutePoints {
                HStack(spacing: 8) {
                    Image(systemName: "map")
                        .foregroundStyle(Color.textSecondary)
                    Text(routePoints.isEmpty ? "No Garmin map data for this activity. Route saving, matching, and benchmark comparisons need GPS points; the run report still works." : "This Garmin map has too few GPS points to save as a repeatable route; the run report still works.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }

            Text("Saved to your history")
                .font(.caption.bold())
                .foregroundStyle(Color.lime)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.lime.opacity(0.11))
                .clipShape(Capsule(style: .continuous))
        }
        .sheet(isPresented: $showSaveRouteSheet) {
            if let run = garminRunWithRoutePoints {
                SaveRouteSheet(run: run)
                    .preferredColorScheme(.dark)
            }
        }
        .task(id: activity.id) { await loadActivityReport() }
    }

    private func loadGarminDeviceFallback() async {
        let statuses = await services.deviceStatuses()
        garminDeviceName = statuses.first { $0.provider == "Garmin Connect" }?.deviceName
    }

    private var garminRunWithRoutePoints: RecordedRun? {
        guard var run = activity.toRecordedRun() else { return nil }
        run.routePoints = routePoints
        return run
    }

    private func generateReportTapped() {
        Task {
            await generateReport()
        }
    }

    private func loadActivityReport() async {
        async let deviceFallbackTask: Void = loadGarminDeviceFallback()
        isLoadingRoutePoints = true
        routePoints = activity.toRecordedRun()?.routePoints ?? []
        if routePoints.isEmpty, let authUserID = session.currentUserID {
            routePoints = await GarminBridge.shared.activityRoutePoints(activityID: activity.activityId, authUserID: authUserID)
        }
        isLoadingRoutePoints = false
        if var run = activity.toRecordedRun() {
            if !routePoints.isEmpty { run.routePoints = routePoints }
            report = await services.runReport(for: run)
        }
        await deviceFallbackTask
    }

    private func generateReport() async {
        guard var run = activity.toRecordedRun() else { return }
        if !routePoints.isEmpty { run.routePoints = routePoints }
        isGenerating = true
        generationFailed = false
        Analytics.trackRunReportGenerateTapped(source: "garmin_activity")
        defer { isGenerating = false }
        if let generated = await services.generateRunReportIfMissing(for: run) {
            report = generated
            Analytics.trackRunReportGenerateSucceeded(source: "garmin_activity")
        } else {
            generationFailed = true
            Analytics.trackRunReportGenerateFailed(source: "garmin_activity")
        }
    }

    private var paceLabel: String {
        if let pace = activity.avgPaceSPerKm, pace > 0 {
            let s = Int(pace.rounded())
            return String(format: "%d:%02d", Int32(s / 60), Int32(s % 60))
        }
        guard let duration = activity.durationS, let meters = activity.distanceM, meters > 0 else {
            return "--"
        }
        let s = Int((duration / (meters / 1000)).rounded())
        return String(format: "%d:%02d", Int32(s / 60), Int32(s % 60))
    }

    private var heartRateLabel: String {
        guard let avgHr = activity.avgHr else { return "--" }
        return "\(avgHr) bpm"
    }

    private var elevationLabel: String {
        guard let elevation = activity.elevationGainM else { return "--" }
        return "\(Int(elevation.rounded())) m"
    }

    private var caloriesLabel: String {
        guard let calories = activity.calories else { return "--" }
        return "\(Int(calories.rounded())) kcal"
    }

    private var startTimeLabel: String {
        guard let date = activity.startDate else { return "--" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct RunReportDetailScaffold: View {
    @Environment(\.runSmartServices) private var services
    @State private var report: RunReportDetail
    @State private var isGenerating = false
    @State private var generationFailed = false
    @State private var reportRun: RecordedRun?

    init(report: RunReportDetail) {
        _report = State(initialValue: report)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Run Summary", trailing: report.dateLabel)
                    Text(report.title)
                        .font(.title2.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricBadge(title: "Distance", value: report.distance)
                        MetricBadge(title: "Moving time", value: report.duration)
                        MetricBadge(title: "Avg Pace", value: report.averagePace)
                        MetricBadge(title: "Avg HR", value: report.averageHeartRate)
                        if let rpeLabel {
                            MetricBadge(title: "RPE", value: rpeLabel)
                        }
                    }
                    Text(report.source)
                        .font(.caption.bold())
                        .foregroundStyle(Color.lime)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.lime.opacity(0.11))
                        .clipShape(Capsule(style: .continuous))
                }
            }
            RunReportCoachNotesCard(report: report)
            ProgressShareCard(payload: .runReport(report))
            ProgressShareButton(payload: .runReport(report))
            PostRunLearningCard(run: reportRun, outcome: nil, report: report, isProcessing: isGenerating)
            BenchmarkComparisonLoaderView(run: reportRun)
            if !report.hasGeneratedReport {
                generateReportCard
            }
            RunReportRichSignalsCard(report: report)
            RunReportNextWorkoutCard(report: report)
        }
        .task(id: report.runID) {
            await loadReportRun()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartReportsDidChange)) { _ in
            Task { await reloadReportIfNeeded() }
        }
    }

    private var generateReportCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Generate Coach Report")
                Text(generationFailed ? "Report generation failed. Check your connection and try again." : "Create a full coach report from this real activity and save it under Recent Run Reports.")
                    .font(.callout)
                    .foregroundStyle(Color.mutedText)
                Button(isGenerating ? "Generating..." : "Generate Report", action: generateReportTapped)
                .buttonStyle(NeonButtonStyle())
                .disabled(isGenerating)
            }
        }
    }

    private var rpeLabel: String? {
        reportRun?.rpe.map { "\($0)/10" }
    }

    private func generateReportTapped() {
        Task {
            await generateReport()
        }
    }

    private func generateReport() async {
        isGenerating = true
        generationFailed = false
        Analytics.trackRunReportGenerateTapped(source: "run_report_detail")
        defer { isGenerating = false }

        if let generated = await services.generateRunReportIfMissing(forRunID: report.runID) {
            report = generated
            await loadReportRun()
            RunSmartHaptics.success()
            Analytics.trackRunReportGenerateSucceeded(source: "run_report_detail")
        } else {
            generationFailed = true
            Analytics.trackRunReportGenerateFailed(source: "run_report_detail")
        }
    }

    private func loadReportRun() async {
        let runs = await services.recentRuns()
        reportRun = runs.first { run in
            run.consolidatedActivityID == report.runID ||
            run.providerActivityID == report.runID ||
            run.id.uuidString == report.runID
        }
    }

    private func reloadReportIfNeeded() async {
        if let generated = await services.generateRunReportIfMissing(forRunID: report.runID) {
            report = generated
        }
        await loadReportRun()
    }
}

private struct RunReportCoachNotesCard: View {
    var report: RunReportDetail

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: report.hasGeneratedReport ? "Coach Notes" : "Coach Report", trailing: scoreLabel)
                DetailLine(label: "Insight", value: report.notes.summary)
                if report.hasGeneratedReport {
                    DetailLine(label: "Effort", value: report.notes.effort)
                    DetailLine(label: "Recovery", value: report.notes.recovery)
                } else {
                    Text("This is a real activity, but no generated coach report has been saved yet.")
                        .font(.callout)
                        .foregroundStyle(Color.mutedText)
                }
            }
        }
    }

    private var scoreLabel: String? {
        report.coachScore.map { "Score \($0)" }
    }
}

private struct RunReportRichSignalsCard: View {
    var report: RunReportDetail

    var body: some View {
        if hasSignals {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Run Breakdown")
                    if let insights = report.notes.keyInsights, !insights.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key Insights")
                                .font(.caption.bold())
                                .foregroundStyle(Color.mutedText)
                            ForEach(insights, id: \.self) { insight in
                                Label(insight, systemImage: "sparkle")
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.86))
                            }
                        }
                    }
                    if let pacing = report.notes.pacing, !pacing.isEmpty {
                        DetailLine(label: "Pacing", value: pacing)
                    }
                    if let biomechanics = report.notes.biomechanics, !biomechanics.isEmpty {
                        DetailLine(label: "Biomechanics", value: biomechanics)
                    }
                    if let recovery = report.notes.recoveryTimeline, !recovery.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recovery Timeline")
                                .font(.caption.bold())
                                .foregroundStyle(Color.mutedText)
                            ForEach(recovery, id: \.self) { step in
                                Label(step, systemImage: "clock.arrow.circlepath")
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.86))
                            }
                        }
                    }
                }
            }
        }
    }

    private var hasSignals: Bool {
        report.notes.keyInsights?.isEmpty == false ||
        report.notes.pacing?.isEmpty == false ||
        report.notes.biomechanics?.isEmpty == false ||
        report.notes.recoveryTimeline?.isEmpty == false
    }
}

private struct RunReportNextWorkoutCard: View {
    @Environment(\.runSmartServices) private var services
    var report: RunReportDetail
    @State private var isSaving = false
    @State private var saveState: SaveState = .idle

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Recommended Next Run")
                if let next = report.structuredNextWorkout {
                    DetailLine(label: "Workout", value: next.title)
                    if let date = next.dateLabel { DetailLine(label: "Date", value: date) }
                    if let distance = next.distance { DetailLine(label: "Distance", value: distance) }
                    if let target = next.target { DetailLine(label: "Target", value: target) }
                    if let notes = next.notes { DetailLine(label: "Notes", value: notes) }

                    Button {
                        Task { await save(next) }
                    } label: {
                        HStack {
                            RunSmartLogoMark(size: 24)
                            Text(saveState.buttonTitle(isSaving: isSaving))
                                .font(.buttonLabel)
                            Spacer()
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(Color.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || saveState == .saved)

                    if saveState == .failed {
                        Text(saveFailureMessage)
                            .font(.caption)
                            .foregroundStyle(Color.accentHeart)
                    }
                } else {
                    Text(report.notes.nextSessionNudge)
                        .font(.callout)
                        .foregroundStyle(Color.mutedText)
                }
            }
        }
    }

    private var saveFailureMessage: String {
        PostRunSuggestedWorkoutSaveCopy.failureMessage
    }

    private func save(_ next: StructuredNextWorkout) async {
        isSaving = true
        saveState = .idle
        let saved = await services.saveSuggestedWorkout(next, from: report)
        isSaving = false
        saveState = saved ? .saved : .failed
        if saved { RunSmartHaptics.success() }
    }

    private enum SaveState {
        case idle
        case saved
        case failed

        func buttonTitle(isSaving: Bool) -> String {
            if isSaving { return "Saving..." }
            switch self {
            case .idle: return "Save to Training Plan"
            case .saved: return "Saved to Plan"
            case .failed: return "Try Saving Again"
            }
        }
    }
}

private struct AudioCuesScaffold: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Cue Timing")
                    PreferenceRow(title: "Pace checks", value: "Every 1 km", symbol: "timer")
                    PreferenceRow(title: "Form reminders", value: "Every 8 min", symbol: "figure.run")
                    PreferenceRow(title: "Heart-rate alerts", value: "Zone 4+", symbol: "heart")
                    PreferenceRow(title: "Milestone callouts", value: "On", symbol: "flag")
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Preview")
                    Text("Cue audio will play during a run with your selected coach tone.")
                        .font(.callout)
                        .foregroundStyle(Color.mutedText)
                        .padding(12)
                        .background(Color.lime.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

private struct LapMarkerScaffold: View {
    @Environment(\.runRecorder) private var recorder

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Current Run")
                    if recorder.phase == .recording || recorder.phase == .paused {
                        Text(recorder.distanceLabel + " km")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        HStack {
                            MetricBadge(title: "Moving time", value: recorder.movingLabel)
                            MetricBadge(title: "Pace", value: recorder.currentPaceLabel + " /km")
                        }
                    } else {
                        Text("No active run")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.mutedText)
                        Text("Start a GPS run on the Run tab to capture splits and lap markers.")
                            .font(.caption)
                            .foregroundStyle(Color.mutedText)
                    }
                }
            }
        }
    }
}

private struct PostRunSummaryScaffold: View {
    @Environment(\.dismiss) private var dismiss
    var run: RecordedRun?

    private var distanceLabel: String {
        guard let run else { return "--" }
        return String(format: "%.2f km", run.distanceMeters / 1000)
    }

    private var paceLabel: String {
        guard let run, run.averagePaceSecondsPerKm > 0 else { return "--" }
        let s = Int(run.averagePaceSecondsPerKm)
        return String(format: "%d:%02d", Int32(s / 60), Int32(s % 60))
    }

    private var timeLabel: String {
        guard let run else { return "--" }
        return RunRecorder.timeLabel(run.movingTimeSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: run == nil ? "Run Not Saved" : "Run Complete")
                    HStack {
                        MetricBadge(title: "Distance", value: distanceLabel)
                        MetricBadge(title: "Avg Pace", value: paceLabel)
                        MetricBadge(title: "Moving time", value: timeLabel)
                    }
                    Text(statusCopy)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
            }

            if let run, !run.routePoints.isEmpty {
                GlassCard(padding: 8, glow: Color.lime) {
                    RouteMapView(points: run.routePoints, title: "Your Route")
                        .frame(height: 160)
                }
            }

            Button("Done") {
                dismiss()
            }
                .buttonStyle(NeonButtonStyle())
        }
    }

    private var statusCopy: String {
        if run == nil {
            return "RunSmart could not find completed run metrics for this summary. Return to the Run tab and try finishing again."
        }
        return "Run saved. Great work - your coach will factor this into the plan."
    }
}

private struct VoiceCoachingScaffold: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Voice Coaching")
                    PreferenceRow(title: "During workouts", value: "On", symbol: "speaker.wave.2")
                    PreferenceRow(title: "During easy runs", value: "Light", symbol: "figure.walk")
                    PreferenceRow(title: "During races", value: "Focused", symbol: "flag.checkered")
                }
            }

            VoicePreviewCard(text: "Relax your shoulders and keep this pace smooth. You are right on target.")
        }
    }
}

private struct CoachingToneScaffold: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Coach Personality")
                    FlowSelectionTile(title: "Motivating", value: "Selected", symbol: "bolt.fill", selected: true)
                    FlowSelectionTile(title: "Calm", value: "Lower intensity", symbol: "leaf.fill", selected: false)
                    FlowSelectionTile(title: "Technical", value: "Data-first", symbol: "chart.xyaxis.line", selected: false)
                }
            }

            VoicePreviewCard(text: "Strong and steady. This is the kind of controlled work that moves your goal forward.")
        }
    }
}

private struct TrainingDataEditor: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedExperience = ""
    @State private var ageText = ""
    @State private var weeklyDistanceKm = 0.0
    @State private var selectedSource: TrainingDataSource = .manual
    @State private var daysPerWeek = 4
    @State private var recentRuns: [RecordedRun] = []
    @State private var isSaving = false
    @State private var saved = false
    @State private var failed = false

    private let experiences = ["Beginner", "Intermediate", "Advanced", "Competitive"]

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            if let estimate = estimatedWeeklyDistance {
                GlassCard(glow: Color.lime) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Detected Baseline", trailing: estimateSource.displayName)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", estimate))
                                .font(.metric)
                                .monospacedDigit()
                            Text("km / week")
                                .font(.bodyMD.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Button {
                            weeklyDistanceKm = estimate
                            selectedSource = estimateSource
                        } label: {
                            Label("Use Estimate", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(NeonButtonStyle())
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Running Experience")
                    ForEach(experiences, id: \.self) { exp in
                        Button { selectedExperience = exp } label: {
                            FlowSelectionTile(title: exp, value: experienceDetail(exp), symbol: "figure.run", selected: selectedExperience == exp)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Age")
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                        .font(.metricSM)
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("13-90 years")
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Average Weekly Distance")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.0f", weeklyDistanceKm))
                            .font(.metric)
                            .monospacedDigit()
                        Text("km / week")
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Slider(value: $weeklyDistanceKm, in: 0...120, step: 1)
                        .tint(Color.lime)
                    Stepper("\(daysPerWeek) run days per week", value: $daysPerWeek, in: 1...7)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            if weeklyDistanceRequired && weeklyDistanceKm <= 0 {
                Label("Intermediate and advanced plans need a weekly distance baseline.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.accentRecovery)
            }

            if !ageText.isEmpty && parsedAge == nil {
                Label("Enter an age between 13 and 90.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Color.accentRecovery)
            }

            if saved {
                Label("Training data saved.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.lime)
                    .font(.headline)
            }

            if failed {
                Text("Training data could not be saved to your RunSmart profile. Check your connection and try again.")
                    .font(.callout)
                    .foregroundStyle(Color.red)
            }

            Button(action: saveTapped) {
                HStack {
                    if isSaving {
                        ProgressView().tint(.black)
                    } else {
                        Label("Save Training Data", systemImage: "checkmark")
                    }
                }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(isSaving || selectedExperience.isEmpty || parsedAge == nil || (weeklyDistanceRequired && weeklyDistanceKm <= 0))

            Color.clear.frame(height: 96)
        }
        .task {
            loadInitialState()
            recentRuns = await services.recentRuns()
            if session.onboardingProfile.averageWeeklyDistanceKm == nil,
               let estimate = estimatedWeeklyDistance,
               weeklyDistanceKm <= 0 {
                weeklyDistanceKm = estimate
                selectedSource = estimateSource
            }
        }
    }

    private var estimatedWeeklyDistance: Double? {
        TrainingDataBaseline.averageWeeklyDistanceKm(from: recentRuns)
    }

    private var parsedAge: Int? {
        let trimmed = ageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let age = Int(trimmed), (13...90).contains(age) else { return nil }
        return age
    }

    private var estimateSource: TrainingDataSource {
        TrainingDataBaseline.inferredSource(from: recentRuns) ?? .runSmart
    }

    private var weeklyDistanceRequired: Bool {
        let lower = selectedExperience.lowercased()
        return lower.contains("intermediate") || lower.contains("advanced") || lower.contains("competitive")
    }

    private func saveTapped() {
        Task {
            await save()
        }
    }

    private func loadInitialState() {
        let profile = session.onboardingProfile
        selectedExperience = normalizedExperience(profile.experience)
        ageText = profile.age.map(String.init) ?? ""
        weeklyDistanceKm = profile.averageWeeklyDistanceKm ?? 0
        selectedSource = profile.trainingDataSource ?? .manual
        daysPerWeek = max(1, min(7, profile.weeklyRunDays))
    }

    private func normalizedExperience(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("advanced") { return "Advanced" }
        if lower.contains("competitive") { return "Competitive" }
        if lower.contains("beginner") || lower.contains("base") || lower.contains("new") { return "Beginner" }
        if lower.contains("intermediate") || lower.contains("consistent") { return "Intermediate" }
        return "Intermediate"
    }

    private func experienceDetail(_ value: String) -> String {
        switch value {
        case "Beginner": "New or rebuilding"
        case "Intermediate": "Steady weekly running"
        case "Advanced": "Higher volume or workouts"
        default: "Race-focused training"
        }
    }

    private func save() async {
        var updated = session.onboardingProfile
        updated.experience = selectedExperience
        updated.age = parsedAge
        updated.averageWeeklyDistanceKm = weeklyDistanceKm > 0 ? weeklyDistanceKm : nil
        updated.trainingDataSource = updated.averageWeeklyDistanceKm == nil ? nil : selectedSource
        updated.trainingDataUpdatedAt = Date()
        updated.weeklyRunDays = daysPerWeek

        isSaving = true
        await session.completeOnboarding(updated)
        let request = TrainingGoalRequest(
            displayName: updated.displayName,
            goal: updated.goal.isEmpty ? "10K Improvement" : updated.goal,
            experience: updated.experience,
            age: updated.age,
            averageWeeklyDistanceKm: updated.averageWeeklyDistanceKm,
            trainingDataSource: updated.trainingDataSource,
            weeklyRunDays: updated.weeklyRunDays,
            preferredDays: updated.preferredDays,
            coachingTone: updated.coachingTone,
            targetDate: Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
        )
        let savedToPlan = await services.saveTrainingGoal(request)
        isSaving = false
        saved = savedToPlan
        failed = !savedToPlan

        if savedToPlan {
            RunSmartHaptics.success()
            dismiss()
        }
    }
}

private struct GoalFocusEditor: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGoal: String = ""
    @State private var selectedExperience: String = ""
    @State private var selectedStyle: String = ""
    @State private var daysPerWeek: Int = 4
    @State private var isSaving = false
    @State private var saved = false
    @State private var failed = false

    private let goals = ["5K / Speed", "10K Improvement", "Half Marathon", "Marathon", "Build Habit"]
    private let experiences = ["Building Base", "Intermediate", "Advanced", "Competitive"]
    private let styles = ["Motivating", "Technical", "Supportive", "Strict"]

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Primary Goal")
                    ForEach(goals, id: \.self) { goal in
                        Button { selectedGoal = goal } label: {
                            FlowSelectionTile(title: goal, value: "", symbol: "target", selected: selectedGoal == goal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Experience Level")
                    ForEach(experiences, id: \.self) { exp in
                        Button { selectedExperience = exp } label: {
                            FlowSelectionTile(title: exp, value: "", symbol: "figure.run", selected: selectedExperience == exp)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Coaching Style")
                    ForEach(styles, id: \.self) { style in
                        Button { selectedStyle = style } label: {
                            FlowSelectionTile(title: style, value: "", symbol: "sparkles", selected: selectedStyle == style)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Days Per Week")
                    Stepper("\(daysPerWeek) days", value: $daysPerWeek, in: 1...7)
                        .foregroundStyle(.white)
                }
            }

            if saved {
                Label("Goals saved!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.lime)
                    .font(.headline)
            }

            if failed {
                Text("Goal saved locally, but the web coach did not generate a plan. Try again later.")
                    .font(.callout)
                    .foregroundStyle(Color.red)
            }

            Button(action: saveTapped) {
                HStack {
                    if isSaving { ProgressView().tint(.black) }
                    else { Label("Save Goals", systemImage: "checkmark") }
                }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(isSaving || selectedGoal.isEmpty)
        }
        .onAppear {
            selectedGoal = session.onboardingProfile.goal
            selectedExperience = session.onboardingProfile.experience
            selectedStyle = session.onboardingProfile.coachingTone
            daysPerWeek = session.onboardingProfile.weeklyRunDays
        }
    }

    private func saveTapped() {
        Task {
            await save()
        }
    }

    private func save() async {
        guard !selectedGoal.isEmpty else {
            print("[GoalFocusEditor] ❌ Cannot save: no goal selected")
            return
        }
        
        var updated = session.onboardingProfile
        updated.goal = selectedGoal
        updated.experience = selectedExperience.isEmpty ? session.onboardingProfile.experience : selectedExperience
        updated.coachingTone = selectedStyle.isEmpty ? session.onboardingProfile.coachingTone : selectedStyle
        updated.weeklyRunDays = daysPerWeek
        
        isSaving = true
        await session.completeOnboarding(updated)
        let request = TrainingGoalRequest(
            displayName: updated.displayName,
            goal: updated.goal,
            experience: updated.experience,
            age: updated.age,
            averageWeeklyDistanceKm: updated.averageWeeklyDistanceKm,
            trainingDataSource: updated.trainingDataSource,
            weeklyRunDays: updated.weeklyRunDays,
            preferredDays: updated.preferredDays,
            coachingTone: updated.coachingTone,
            targetDate: Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
        )
        let savedToPlan = await services.saveTrainingGoal(request)
        isSaving = false
        saved = savedToPlan
        failed = !savedToPlan
        
        print("[GoalFocusEditor] \(savedToPlan ? "✅" : "❌") Saved goals: \(selectedGoal), \(selectedExperience), \(selectedStyle), \(daysPerWeek) days/week")
        if savedToPlan {
            dismiss()
        }
    }
}

private struct ReminderPreferencesScaffold: View {
    @EnvironmentObject private var session: SupabaseSession

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Reminders")
                    Toggle(isOn: Binding(
                        get: { session.onboardingProfile.notificationsEnabled },
                        set: { session.setNotificationsEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart return reminders")
                                .font(.bodyMD.weight(.semibold))
                            Text("Low-frequency prompts for planned runs, gentle recovery, and weekly recap.")
                                .font(.caption)
                                .foregroundStyle(Color.mutedText)
                        }
                    }
                    .tint(Color.lime)
                    Toggle(isOn: Binding(
                        get: { session.onboardingProfile.planAdjustmentConfirmationsEnabled },
                        set: { session.setPlanAdjustmentConfirmationsEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Plan adjustment confirmations")
                                .font(.bodyMD.weight(.semibold))
                            Text("A single nudge after Flex Week confirms, summarizing tomorrow's workout.")
                                .font(.caption)
                                .foregroundStyle(Color.mutedText)
                        }
                    }
                    .tint(Color.lime)
                    PreferenceRow(title: "Workout due", value: session.onboardingProfile.notificationsEnabled ? "Morning" : "Off", symbol: "bell")
                    PreferenceRow(title: "Recovery re-plan", value: session.onboardingProfile.notificationsEnabled ? "Evening if needed" : "Off", symbol: "arrow.triangle.2.circlepath")
                    PreferenceRow(title: "Rest day reminder", value: session.onboardingProfile.notificationsEnabled ? "Late morning" : "Off", symbol: "moon")
                    PreferenceRow(title: "Weekly recap", value: session.onboardingProfile.notificationsEnabled ? "Sunday" : "Off", symbol: "calendar")
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Quiet Hours")
                    DetailLine(label: "Start", value: "9:30 PM")
                    DetailLine(label: "End", value: "6:30 AM")
                }
            }
        }
    }
}

private struct ConnectedServiceDetailScaffold: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SupabaseSession
    var serviceName: String
    private let store = RunSmartLocalStore.shared
    @State private var status: ConnectedDeviceStatus?
    @State private var isWorking = false
    @State private var recentActivities: [DBGarminActivity] = []
    @State private var garminDeviceName: String?
    @State private var healthRuns: [RecordedRun] = []
    @State private var firstSyncReview: FirstSyncReview?

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Connection")
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon)
                            .font(.title)
                            .foregroundStyle(statusColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusTitle)
                                .font(.title3.bold())
                            Text(statusSubtitle)
                                .foregroundStyle(Color.mutedText)
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Permissions")
                    if serviceName == "HealthKit" {
                        Text("RunSmart uses HealthKit to read only the workout and wellness data you approve, including workouts, routes, heart rate, HRV, sleep, steps, and active energy. If you allow write access, completed GPS runs can be saved back to Health.")
                            .font(.callout)
                            .foregroundStyle(Color.mutedText)
                    }
                    PermissionRow(title: "Activities", enabled: permissions.contains("Activities") || permissions.contains("Workouts"))
                    PermissionRow(title: "Sleep", enabled: permissions.contains("Sleep"))
                    PermissionRow(title: "Heart rate", enabled: permissions.contains("Heart Rate") || permissions.contains("Resting HR"))
                    if serviceName == "HealthKit" {
                        PermissionRow(title: "HRV", enabled: permissions.contains("HRV"))
                        PermissionRow(title: "Steps", enabled: permissions.contains("Steps"))
                    }
                    PermissionRow(title: "Routes", enabled: permissions.contains("Routes"))
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Controls")
                    ActionRow(title: "Connect", detail: connectActionDetail, symbol: "link") {
                        trackConnectionIntent()
                        run { await services.connect(provider: serviceName) }
                    }
                    ActionRow(title: "Sync Now", detail: syncActionDetail, symbol: "arrow.triangle.2.circlepath") {
                        run { await services.syncNow(provider: serviceName) }
                    }
                    Button("Disconnect \(serviceName)") {
                        run { await services.disconnect(provider: serviceName) }
                    }
                        .buttonStyle(NeonButtonStyle(isDestructive: true))
                        .disabled(isWorking)
                }
            }

            if let firstSyncReview, !firstSyncReview.seen {
                FirstSyncReviewCard(
                    review: firstSyncReview,
                    onNextAction: handleFirstSyncNextAction,
                    onDismiss: markFirstSyncReviewSeen
                )
            }

            if serviceName == "Garmin Connect" {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Recent Activities")
                        if recentActivities.isEmpty {
                            Text("No activities synced yet. Tap Sync Now above once Garmin is connected.")
                                .font(.callout)
                                .foregroundStyle(Color.mutedText)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(recentActivities, id: \.id) { activity in
                                    Button {
                                        router.open(.runReport(activity))
                                    } label: {
                                        RecentActivityRow(activity: activity, fallbackGarminDeviceName: garminDeviceName)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            if serviceName == "HealthKit" {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Imported From Health")
                        if healthRuns.isEmpty {
                            Text("No Health workouts imported yet. Tap Sync Now after granting Health access.")
                                .font(.callout)
                                .foregroundStyle(Color.mutedText)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(healthRuns.prefix(8)) { run in
                                    ActivityRow(run: run, onTap: {
                                        router.open(.postRunSummary(run))
                                    })
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await load()
            trackDisclosureViewedIfNeeded()
        }
    }

    private var permissions: [String] { status?.permissions ?? [] }

    private var statusTitle: String {
        switch status?.state ?? .disconnected {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Disconnected"
        case .error: "Needs attention"
        }
    }

    private var statusSubtitle: String {
        if let date = status?.lastSuccessfulSync {
            return "Last sync \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return status?.message ?? "No sync has completed yet."
    }

    private var statusIcon: String {
        switch status?.state ?? .disconnected {
        case .connected: "checkmark.circle.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .disconnected: "link.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch status?.state ?? .disconnected {
        case .connected: Color.lime
        case .connecting: .cyan
        case .disconnected: Color.mutedText
        case .error: .orange
        }
    }

    private var connectActionDetail: String {
        if serviceName == "HealthKit" {
            return "Open the HealthKit permission sheet for approved read/write access."
        }
        return "Start the real permission or gateway flow."
    }

    private var syncActionDetail: String {
        if serviceName == "HealthKit" {
            return "Import the latest approved HealthKit workout and wellness data."
        }
        return "Pull the latest real activity data."
    }

    private func trackDisclosureViewedIfNeeded() {
        guard serviceName == "HealthKit" else { return }
        Analytics.trackHealthKitDisclosureViewed(state: status?.state.rawValue ?? "unknown")
    }

    private func trackConnectionIntent() {
        guard serviceName == "HealthKit" else { return }
        Analytics.trackHealthKitConnectTapped()
    }

    private func run(_ action: @escaping () async -> ConnectedDeviceStatus) {
        isWorking = true
        Task {
            status = await action()
            await load()
            isWorking = false
        }
    }

    private func load() async {
        let statuses = await services.deviceStatuses()
        status = statuses.first(where: { $0.provider == serviceName })
        if serviceName == "Garmin Connect" {
            garminDeviceName = status?.deviceName
        }
        if serviceName == "Garmin Connect", let userID = session.currentUserID {
            let activities = await GarminBridge.shared.recentActivities(authUserID: userID, limit: 20)
            recentActivities = Array(GarminImportProcessor.normalizedActivities(from: activities, isHidden: store.isRunHidden).prefix(10))
        }
        if serviceName == "HealthKit" {
            let runs = await services.recentRuns()
            healthRuns = runs.filter { $0.source == .healthKit }
        }
        firstSyncReview = await services.firstSyncReview(provider: serviceName)
    }

    private func markFirstSyncReviewSeen() {
        Task {
            await services.markFirstSyncReviewSeen(provider: serviceName)
            firstSyncReview = await services.firstSyncReview(provider: serviceName)
        }
    }

    private func handleFirstSyncNextAction() {
        guard let action = firstSyncReview?.nextAction else { return }
        Task {
            await services.markFirstSyncReviewSeen(provider: serviceName)
            await MainActor.run {
                switch action {
                case .today:
                    router.selectedTab = .today
                case .report:
                    router.selectedTab = .report
                case .plan:
                    router.selectedTab = .plan
                }
                router.activeSheet = nil
            }
        }
    }
}

private struct FirstSyncReviewCard: View {
    var review: FirstSyncReview
    var onNextAction: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        GlassCard(glow: Color.accentPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(title: "\(review.provider.displayName) first sync")
                        Text(review.summary)
                            .font(.callout)
                            .foregroundStyle(Color.textPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    DetailLine(label: "Imported", value: "\(review.importedCount)")
                    DetailLine(label: "Skipped", value: "\(review.skippedDuplicateCount) duplicate or hidden")
                    DetailLine(label: "Routes", value: "\(review.routeAvailabilityCount) available / \(review.routeLessCount) route-less")
                }

                Text(review.routeSummary)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)

                if !review.recentImportedActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent imports")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        ForEach(review.recentImportedActivities) { activity in
                            FirstSyncActivityRow(activity: activity)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach can now use")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    ForEach(review.coachCanUse, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "sparkle")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentPrimary)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button(review.nextAction.title, action: onNextAction)
                        .buttonStyle(NeonButtonStyle())
                    Button("Got it", action: onDismiss)
                        .buttonStyle(.plain)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }
}

private struct FirstSyncActivityRow: View {
    var activity: FirstSyncActivitySummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.hasRoute ? "map.fill" : "map")
                .font(.caption.weight(.bold))
                .foregroundStyle(activity.hasRoute ? Color.accentPrimary : Color.textTertiary)
                .frame(width: 28, height: 28)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.caption.weight(.semibold))
                Text(activity.dateLabel)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
            Text(activity.distanceLabel)
                .font(.caption.weight(.semibold))
        }
        .padding(8)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ActionRow: View {
    var title: String
    var detail: String
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RunSmartIconMark(size: 42, tint: .lime)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                }
                Spacer()
                RunSmartIconMark(size: 22, tint: .mutedText)
            }
            .padding(10)
            .background(.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ActionTile: View {
    var title: String
    var symbol: String
    var tint: Color = Color.lime
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RunSmartIconMark(size: 34, tint: tint)
                Text(title.uppercased())
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(tint == .red ? .red : .white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .padding(10)
            .background(.white.opacity(0.045))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutStepRow: View {
    var step: WorkoutStep

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(step.tint)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.headline)
                Text(step.duration)
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedText)
                Text("Target · \(step.target)")
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedText)
                if !step.note.isEmpty {
                    Text(step.note)
                        .font(.caption.italic())
                        .foregroundStyle(Color.mutedText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.white.opacity(0.055))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AddRunKindTile: View {
    var kind: WorkoutKind
    var selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: kind.symbol)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            .frame(height: 58)
            Text(kind.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 116)
        .background(selected ? Color.lime.opacity(0.12) : Color.white.opacity(0.045))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Color.lime : Color.hairline, lineWidth: selected ? 1.4 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var colors: [Color] {
        switch kind {
        case .easy: [Color.green, Color.mint]
        case .tempo: [Color.orange, Color.red]
        case .intervals: [Color.pink, Color.purple]
        case .hills: [Color.green, Color.teal]
        case .long: [Color.blue, Color.cyan]
        case .race: [Color.red, Color.pink]
        case .parkrun: [Color.teal, Color.green]
        case .strength: [Color.gray, Color.white.opacity(0.5)]
        case .recovery: [Color.mint, Color.green.opacity(0.5)]
        }
    }
}

private struct RunSmartTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .foregroundStyle(.white)
            .background(.white.opacity(0.055))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct FlowTimelineStep: View {
    var index: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(index)
                .font(.caption.bold())
                .foregroundStyle(Color.black)
                .frame(width: 26, height: 26)
                .background(Color.lime)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
            }
        }
    }
}

private struct FlowChip: View {
    var text: String
    var symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.bold())
            .foregroundStyle(Color.lime)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.lime.opacity(0.1))
            .clipShape(Capsule(style: .continuous))
    }
}

private struct DetailLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Color.mutedText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private struct ReadinessBar: View {
    var title: String
    var value: Double
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(Color.mutedText)
                Spacer()
                Text(detail)
                    .font(.caption.bold())
                    .foregroundStyle(Color.lime)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.electricGreen, Color.lime], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(value))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct PlanChangeRow: View {
    var day: String
    var before: String
    var after: String

    var body: some View {
        HStack(spacing: 12) {
            Text(day)
                .font(.caption.bold())
                .foregroundStyle(Color.black)
                .frame(width: 42, height: 42)
                .background(Color.lime)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(before)
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
                Text(after)
                    .font(.headline)
            }
        }
        .padding(10)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FlowSelectionTile: View {
    var title: String
    var value: String
    var symbol: String
    var selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RunSmartIconMark(size: 34, tint: .lime, selected: selected)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(selected ? Color.lime : Color.mutedText)
            }
            Spacer()
        }
        .padding(12)
        .background(selected ? Color.lime.opacity(0.1) : Color.white.opacity(0.045))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Color.lime : Color.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RouteOptionRow: View {
    var title: String
    var detail: String
    var selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            RunSmartIconMark(size: 30, tint: selected ? .lime : .mutedText, selected: selected)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
            }
            Spacer()
        }
        .padding(10)
        .background(selected ? Color.lime.opacity(0.08) : Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PreferenceRow: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        HStack(spacing: 12) {
            RunSmartIconMark(size: 38, tint: .lime)
            Text(title)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(Color.lime)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.lime.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(10)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MetricBadge: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.mutedText)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct VoicePreviewCard: View {
    var text: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Preview")
                HStack(spacing: 12) {
                    CoachAvatar(size: 42, showBolt: true)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
            }
        }
    }
}

private struct PermissionRow: View {
    var title: String
    var enabled: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Label(enabled ? "Enabled" : "Off", systemImage: enabled ? "checkmark.circle.fill" : "minus.circle")
                .font(.caption.bold())
                .foregroundStyle(enabled ? Color.lime : Color.mutedText)
        }
    }
}

private struct AccountScaffold: View {
    @EnvironmentObject private var session: SupabaseSession
    @State private var isSigningOut = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    private var email: String {
        session.currentEmail ?? "--"
    }

    private var memberSince: String {
        guard let createdAt = session.currentMemberSince else { return "--" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: createdAt)
    }

    private var isDemoMode: Bool {
        RunSmartDemoMode.isEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            if isDemoMode {
                GlassCard(glow: Color.accentAmber) {
                    Label(
                        "Demo Mode is local only. No Apple, Supabase, Garmin, HealthKit, analytics, or account deletion calls are made.",
                        systemImage: "video.badge.checkmark"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Signed In")
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Color.lime)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.displayName.isEmpty ? "RunSmart Runner" : session.displayName)
                                .font(.headline)
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(Color.mutedText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Account Details")
                    HStack {
                        Text("Email").foregroundStyle(Color.mutedText)
                        Spacer()
                        Text(email).font(.subheadline).lineLimit(1).truncationMode(.middle)
                    }
                    HStack {
                        Text("Member since").foregroundStyle(Color.mutedText)
                        Spacer()
                        Text(memberSince).font(.subheadline)
                    }
                    HStack {
                        Text("Auth provider").foregroundStyle(Color.mutedText)
                        Spacer()
                        Label("Apple", systemImage: "apple.logo").font(.subheadline)
                    }
                }
            }

            Button {
                isSigningOut = true
                Task {
                    await session.signOut()
                    isSigningOut = false
                }
            } label: {
                if isSigningOut {
                    ProgressView().tint(.white)
                } else {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .buttonStyle(NeonButtonStyle(isDestructive: true))
            .disabled(isSigningOut || isDemoMode)

            Text(isDemoMode ? "Sign out is disabled while recording Demo Mode." : "Signing out returns you to the sign-in screen, where you can register a new account or switch users.")
                .font(.caption)
                .foregroundStyle(Color.mutedText)
                .padding(.horizontal, 4)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Delete Account")
                    Text("Permanently delete your account, training plans, run history, and all personal data from RunSmart. This cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)

                    // Delete Account
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        if isDeletingAccount {
                            ProgressView().tint(.white)
                        } else {
                            Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
                        }
                    }
                    .buttonStyle(NeonButtonStyle(isDestructive: true))
                    .disabled(isDeletingAccount || isSigningOut || isDemoMode)
                }
            }
        }
        .confirmationDialog(
            "Delete your RunSmart account?",
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, training plans, and run history. This cannot be undone.")
        }
        .alert("Could not delete account", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "Please try again.")
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        do {
            try await session.deleteAccount()
            // Success: session is cleared and the app returns to sign-in.
        } catch {
            deleteAccountError = error.localizedDescription
        }
        isDeletingAccount = false
    }
}
