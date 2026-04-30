import SwiftUI

enum SecondaryDestination: Hashable, Identifiable {
    case workoutDetail(WorkoutSummary)
    case planAdjustment
    case reschedule(WorkoutSummary)
    case addActivity
    case routeSelector
    case runReport(DBGarminActivity)
    case postRunSummary(RecordedRun?)
    case audioCues
    case lapMarker
    case voiceCoaching
    case coachingTone
    case goalFocus
    case reminders
    case connectedService(String)
    case challenges
    case recoveryDashboard
    case morningCheckin
    case goalWizard
    case weeklyRecap
    case garminWellness
    case zoneAnalysis
    case routeCreator
    case badgeCabinet
    case shareRun(RecordedRun?)
    case account

    var id: String {
        switch self {
        case .workoutDetail(let w): "workoutDetail-\(w.id)"
        case .planAdjustment: "planAdjustment"
        case .reschedule(let w): "reschedule-\(w.id)"
        case .addActivity: "addActivity"
        case .routeSelector: "routeSelector"
        case .runReport(let activity): "runReport-\(activity.id)"
        case .postRunSummary(let run): "postRunSummary-\(run?.id.uuidString ?? "nil")"
        case .audioCues: "audioCues"
        case .lapMarker: "lapMarker"
        case .voiceCoaching: "voiceCoaching"
        case .coachingTone: "coachingTone"
        case .goalFocus: "goalFocus"
        case .reminders: "reminders"
        case .connectedService(let name): "connectedService-\(name)"
        case .challenges: "challenges"
        case .recoveryDashboard: "recoveryDashboard"
        case .morningCheckin: "morningCheckin"
        case .goalWizard: "goalWizard"
        case .weeklyRecap: "weeklyRecap"
        case .garminWellness: "garminWellness"
        case .zoneAnalysis: "zoneAnalysis"
        case .routeCreator: "routeCreator"
        case .badgeCabinet: "badgeCabinet"
        case .shareRun(let run): "shareRun-\(run?.id.uuidString ?? "nil")"
        case .account: "account"
        }
    }

    var title: String {
        switch self {
        case .workoutDetail(let w): w.title
        case .planAdjustment: "Plan Adjustment"
        case .reschedule: "Reschedule"
        case .addActivity: "Add Activity"
        case .routeSelector: "Route Selector"
        case .runReport: "Run Report"
        case .postRunSummary: "Post-Run Summary"
        case .audioCues: "Audio Cues"
        case .lapMarker: "Lap Marker"
        case .voiceCoaching: "Voice Coaching"
        case .coachingTone: "Coaching Tone"
        case .goalFocus: "Goal Focus"
        case .reminders: "Reminders & Preferences"
        case .connectedService(let name): name
        case .challenges: "Challenges"
        case .recoveryDashboard: "Recovery"
        case .morningCheckin: "Morning Check-In"
        case .goalWizard: "Goal Wizard"
        case .weeklyRecap: "Weekly Recap"
        case .garminWellness: "Garmin Wellness"
        case .zoneAnalysis: "Zone Analysis"
        case .routeCreator: "Route Creator"
        case .badgeCabinet: "Badge Cabinet"
        case .shareRun: "Share Run"
        case .account: "Account"
        }
    }
}

struct SecondaryFlowView: View {
    var destination: SecondaryDestination

    var body: some View {
        ZStack {
            RunSmartBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
                    FlowHeader(destination: destination, subtitle: subtitle, symbol: symbol)
                    content
                    Spacer(minLength: 20)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
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
        case .addActivity:
            AddActivityScaffold()
        case .routeSelector:
            RouteSelectorScaffold()
        case .runReport(let activity):
            RunReportScaffold(activity: activity)
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
        case .garminWellness:
            GarminWellnessViews()
        case .zoneAnalysis:
            ZoneAnalysisView()
        case .routeCreator:
            RouteCreatorView()
        case .badgeCabinet:
            BadgeCabinetView()
        case .shareRun(let run):
            ShareRunView(run: run)
        case .account:
            AccountScaffold()
        }
    }

    private var subtitle: String {
        switch destination {
        case .workoutDetail:
            "Session plan, purpose, and execution cues."
        case .planAdjustment:
            "Coach logic for safe plan changes."
        case .reschedule:
            "Move a workout without spiking weekly load."
        case .addActivity:
            "Log a manual run or cross-training session."
        case .routeSelector:
            "Choose a route that fits today's workout."
        case .runReport:
            "Review a saved run from your history."
        case .postRunSummary:
            "Review effort and save the completed run."
        case .audioCues:
            "Tune voice prompts, timing, and coaching moments."
        case .lapMarker:
            "Capture a split and annotate the effort."
        case .voiceCoaching:
            "Set how active Coach Spark should be during runs."
        case .coachingTone:
            "Pick the coach personality for future guidance."
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
        case .garminWellness:
            "Wellness panels from connected Garmin data."
        case .zoneAnalysis:
            "Understand effort distribution and heart rate zones."
        case .routeCreator:
            "Build a route that matches the workout."
        case .badgeCabinet:
            "Browse earned and locked achievements."
        case .shareRun:
            "Prepare a polished run share card."
        case .account:
            "Manage your sign-in and profile data."
        }
    }

    private var symbol: String {
        switch destination {
        case .workoutDetail(let workout): workout.kind.symbol
        case .planAdjustment: "slider.horizontal.3"
        case .reschedule: "calendar.badge.clock"
        case .addActivity: "plus.circle.fill"
        case .routeSelector: "map.fill"
        case .runReport: "chart.xyaxis.line"
        case .postRunSummary: "checkmark.seal.fill"
        case .audioCues: "speaker.wave.2.fill"
        case .lapMarker: "flag.fill"
        case .voiceCoaching: "waveform"
        case .coachingTone: "sparkles"
        case .goalFocus: "target"
        case .reminders: "bell.badge.fill"
        case .connectedService: "link.circle.fill"
        case .challenges: "trophy.fill"
        case .recoveryDashboard: "heart.text.square.fill"
        case .morningCheckin: "sunrise.fill"
        case .goalWizard: "target"
        case .weeklyRecap: "calendar.badge.checkmark"
        case .garminWellness: "waveform.path.ecg"
        case .zoneAnalysis: "heart.circle.fill"
        case .routeCreator: "point.topleft.down.curvedto.point.bottomright.up"
        case .badgeCabinet: "seal.fill"
        case .shareRun: "square.and.arrow.up"
        case .account: "person.crop.circle.fill"
        }
    }
}

private struct FlowHeader: View {
    var destination: SecondaryDestination
    var subtitle: String
    var symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(colors: [Color.accentPrimary, Color.accentEnergy], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.accentPrimary.opacity(0.38), radius: 16)

            VStack(alignment: .leading, spacing: 6) {
                Text(destination.title)
                    .font(.displayMD)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.top, 8)
    }
}

private struct WorkoutDetailScaffold: View {
    @EnvironmentObject private var router: AppRouter

    var workout: WorkoutSummary
    @State private var runMode = "Outdoor"

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Workout", trailing: workout.distance)
                    Text(workout.title)
                        .font(.title2.bold())
                    Text(workoutPurpose)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.84))

                    HStack(spacing: 8) {
                        FlowChip(text: workout.distance, symbol: "point.topleft.down.curvedto.point.bottomright.up")
                        FlowChip(text: estimatedDuration, symbol: "clock")
                        FlowChip(text: targetZone, symbol: "heart")
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
                        ActionTile(title: "Remove Workout", symbol: "trash", tint: .red) {}
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
                        Text("COLLAPSE")
                            .font(.caption.bold())
                            .foregroundStyle(Color.mutedText)
                        Image(systemName: "chevron.up")
                            .foregroundStyle(Color.mutedText)
                    }
                    Text("\(workout.distance) @ \(targetPace)")
                        .font(.headline)
                        .foregroundStyle(Color.mutedText)
                    Text("STEPS")
                        .font(.caption.bold())
                        .foregroundStyle(Color.mutedText)
                    ForEach(Array(breakdownSteps.enumerated()), id: \.offset) { _, step in
                        WorkoutBreakdownStepRow(step: step)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Coach Actions")
                    ActionRow(title: "Reschedule Workout", detail: "Move this session and preserve weekly balance.", symbol: "calendar.badge.clock") {
                        router.open(.reschedule(workout))
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

    private var targetZone: String {
        switch workout.kind {
        case .tempo, .intervals, .hills, .race: "Zone 3-4"
        case .recovery: "Zone 1"
        default: "Zone 2"
        }
    }

    private var targetPace: String {
        switch workout.kind {
        case .tempo: "5:15 min/km"
        case .intervals: "4:45 min/km"
        case .hills: "Strong effort"
        case .race: "Race pace"
        case .recovery: "Easy jog"
        default: "6:10 min/km"
        }
    }

    private var breakdownSteps: [WorkoutBreakdownStep] {
        switch workout.kind {
        case .tempo:
            return [
                .init(title: "Warm Up", duration: "12:00", target: "6:20-6:50 min/km", note: "Easy warm-up", tint: .red),
                .init(title: "Tempo Block", duration: "20:00", target: "5:05-5:25 min/km", note: "Controlled threshold effort", tint: .orange),
                .init(title: "Cool Down", duration: "8:00", target: "6:30-7:10 min/km", note: "Relaxed finish", tint: Color.lime)
            ]
        case .intervals:
            return [
                .init(title: "Warm Up", duration: "10:00", target: "Easy", note: "Add mobility before speed", tint: .red),
                .init(title: "Repeats", duration: "8 x 400 m", target: "4:35-4:55 min/km", note: "Jog 200 m between reps", tint: .blue),
                .init(title: "Cool Down", duration: "10:00", target: "Easy", note: "Let heart rate settle", tint: Color.lime)
            ]
        case .hills:
            return [
                .init(title: "Warm Up", duration: "12:00", target: "Easy", note: "Find a steady climb", tint: .red),
                .init(title: "Hill Repeats", duration: "8 x 45 sec", target: "Strong form", note: "Walk/jog down recovery", tint: .purple),
                .init(title: "Cool Down", duration: "8:00", target: "Easy", note: "Flat and relaxed", tint: Color.lime)
            ]
        case .long:
            return [
                .init(title: "Settle In", duration: "15:00", target: "Zone 2", note: "Start softer than you think", tint: .red),
                .init(title: "Endurance Run", duration: workout.distance, target: "Conversational", note: "Fuel if running over 75 minutes", tint: .blue),
                .init(title: "Finish Smooth", duration: "5:00", target: "Easy", note: "No sprint finish", tint: Color.lime)
            ]
        default:
            return [
                .init(title: "Warm Up", duration: "10:00", target: "7:25-8:26 min/km", note: "Easy warm-up", tint: .red),
                .init(title: "Run", duration: workout.distance, target: targetPace, note: "Continuous relaxed run", tint: .blue),
                .init(title: "Cool Down", duration: "5:00", target: "Easy", note: "Walk or jog home", tint: Color.lime)
            ]
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
                    ReadinessBar(title: "Recovery", value: 0.82, detail: "High")
                    ReadinessBar(title: "Weekly Load", value: 0.64, detail: "Safe")
                    ReadinessBar(title: "Schedule Fit", value: 0.72, detail: "Tight Thu")
                    Text("Recommendation: keep today's tempo, move strength to Friday, and preserve the Sunday long run.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Proposed Changes")
                    PlanChangeRow(day: "Thu", before: "Strength", after: "Recovery Mobility")
                    PlanChangeRow(day: "Fri", before: "Recovery", after: "Strength")
                    PlanChangeRow(day: "Sun", before: "Long Run", after: "Long Run, cap at easy effort")
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
    var workout: WorkoutSummary

    private let options: [(day: String, fit: String, detail: String)] = [
        ("Tomorrow", "Best fit", "Keeps 48h before the long run."),
        ("Friday", "Good", "Swap with strength and keep effort controlled."),
        ("Saturday", "Caution", "Too close to the long run unless Sunday is reduced.")
    ]

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
                        Text(option.fit)
                            .font(.caption.bold())
                            .foregroundStyle(option.fit == "Caution" ? Color.orange : Color.lime)
                    }
                }
            }
        }
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

            Button(action: { Task { await saveRun() } }) {
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
    @State private var pastRoutes: [RouteSuggestion] = []
    @State private var nearbyRoutes: [RouteSuggestion] = []
    @State private var selectedRouteID: String?
    @State private var isLoadingNearby = false
    @State private var locationUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(padding: 10, glow: Color.lime) {
                ZStack(alignment: .bottomLeading) {
                    RouteMapView(points: selectedRoute?.points ?? [], title: selectedRoute?.name)
                        .frame(height: 180)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedRoute?.name ?? "No saved GPS route yet")
                            .font(.headline)
                        Text(routeDetail)
                            .font(.caption)
                            .foregroundStyle(Color.mutedText)
                    }
                    .padding(12)
                    .background(.black.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(10)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Nearby Loops", trailing: isLoadingNearby ? "Searching" : nil)
                    if isLoadingNearby {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(Color.lime)
                            Text("Finding runnable loops near you...")
                                .font(.callout)
                                .foregroundStyle(Color.mutedText)
                        }
                    } else if nearbyRoutes.isEmpty {
                        Text(locationUnavailable ? "Location is unavailable. Enable location access to generate loops near you." : "Generate loop routes around your current location.")
                            .font(.callout)
                            .foregroundStyle(Color.mutedText)
                        Button(locationUnavailable ? "Enable Location" : "Generate Nearby Loops") {
                            Task { await loadNearbyRoutes() }
                        }
                        .buttonStyle(NeonButtonStyle())
                    } else {
                        ForEach(nearbyRoutes) { route in
                            Button {
                                selectedRouteID = route.id
                            } label: {
                                RouteOptionRow(
                                    title: route.name,
                                    detail: "\(String(format: "%.1f", route.distanceKm)) km | \(route.estimatedDurationMinutes) min",
                                    selected: route.id == selectedRouteID
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Button("Regenerate") {
                            Task { await loadNearbyRoutes() }
                        }
                        .buttonStyle(NeonButtonStyle())
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Past Routes")
                    if pastRoutes.isEmpty {
                        Text("Record a GPS run first, then RunSmart can suggest real routes from your activity history.")
                            .font(.callout)
                            .foregroundStyle(Color.mutedText)
                    } else {
                        ForEach(pastRoutes) { route in
                            Button {
                                selectedRouteID = route.id
                            } label: {
                                RouteOptionRow(
                                    title: route.name,
                                    detail: "\(String(format: "%.1f", route.distanceKm)) km | \(route.elevationGainMeters) m gain",
                                    selected: route.id == selectedRouteID
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button("Use This Route") {}
                .buttonStyle(NeonButtonStyle())
                .disabled(selectedRoute == nil)
        }
        .task {
            pastRoutes = await services.routeSuggestions()
            await loadNearbyRoutes()
            selectedRouteID = nearbyRoutes.first?.id ?? pastRoutes.first?.id
        }
    }

    private var selectedRoute: RouteSuggestion? {
        allRoutes.first(where: { $0.id == selectedRouteID }) ?? allRoutes.first
    }

    private var allRoutes: [RouteSuggestion] {
        nearbyRoutes + pastRoutes
    }

    private var routeDetail: String {
        guard let route = selectedRoute else { return "Route suggestions use real recorded GPS data." }
        return "\(String(format: "%.1f", route.distanceKm)) km | \(route.elevationGainMeters) m gain | \(route.estimatedDurationMinutes) min"
    }

    private func loadNearbyRoutes() async {
        isLoadingNearby = true
        locationUnavailable = false
        defer { isLoadingNearby = false }

        guard let coordinate = await LocationLookupService.shared.currentLocation() else {
            nearbyRoutes = []
            locationUnavailable = true
            return
        }

        nearbyRoutes = await services.nearbyLoopRoutes(around: coordinate, distancesKm: [3, 5, 8, 10])
        if selectedRouteID == nil {
            selectedRouteID = nearbyRoutes.first?.id ?? pastRoutes.first?.id
        }
    }
}

private struct RunReportScaffold: View {
    var activity: DBGarminActivity
    @State private var routePoints: [RunRoutePoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Run Summary", trailing: activity.relativeStartLabel)
                    Text(activity.sportLabel)
                        .font(.title2.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricBadge(title: "Distance", value: activity.distanceKmLabel)
                        MetricBadge(title: "Time", value: activity.durationLabel)
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
                    DetailLine(label: "Source", value: "Garmin")
                }
            }

            GlassCard(padding: 8, glow: routePoints.isEmpty ? nil : Color.lime) {
                RouteMapView(points: routePoints, title: routePoints.isEmpty ? nil : "Run Route")
                    .frame(height: 210)
            }

            Text("Saved to your history")
                .font(.caption.bold())
                .foregroundStyle(Color.lime)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.lime.opacity(0.11))
                .clipShape(Capsule(style: .continuous))
        }
        .task(id: activity.id) {
            routePoints = activity.toRecordedRun()?.routePoints ?? []
            if routePoints.isEmpty {
                routePoints = await GarminBridge.shared.activityRoutePoints(activityID: activity.activityId)
            }
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
                            MetricBadge(title: "Time", value: recorder.movingLabel)
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
        let t = Int(run.movingTimeSeconds)
        if t >= 3600 {
            return String(format: "%d:%02d:%02d", Int32(t / 3600), Int32((t % 3600) / 60), Int32(t % 60))
        }
        return String(format: "%d:%02d", Int32(t / 60), Int32(t % 60))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Run Complete")
                    HStack {
                        MetricBadge(title: "Distance", value: distanceLabel)
                        MetricBadge(title: "Avg Pace", value: paceLabel)
                        MetricBadge(title: "Time", value: timeLabel)
                    }
                    Text("Run saved. Great work — your coach will factor this into next week's plan.")
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

            Button("Done") {}
                .buttonStyle(NeonButtonStyle())
        }
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

private struct GoalFocusEditor: View {
    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGoal: String = ""
    @State private var selectedExperience: String = ""
    @State private var selectedStyle: String = ""
    @State private var daysPerWeek: Int = 4
    @State private var isSaving = false
    @State private var saved = false

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

            Button(action: { Task { await save() } }) {
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

    private func save() async {
        var updated = session.onboardingProfile
        updated.goal = selectedGoal
        updated.experience = selectedExperience
        updated.coachingTone = selectedStyle
        updated.weeklyRunDays = daysPerWeek
        isSaving = true
        await session.completeOnboarding(updated)
        isSaving = false
        saved = true
    }
}

private struct ReminderPreferencesScaffold: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Reminders")
                    PreferenceRow(title: "Workout reminder", value: "7:00 AM", symbol: "bell")
                    PreferenceRow(title: "Recovery check-in", value: "Evening", symbol: "moon")
                    PreferenceRow(title: "Shoe mileage alert", value: "At 500 km", symbol: "shoeprints.fill")
                    PreferenceRow(title: "Weekly recap", value: "Sunday", symbol: "calendar")
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
    @State private var status: ConnectedDeviceStatus?
    @State private var isWorking = false
    @State private var recentActivities: [DBGarminActivity] = []

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
                    PermissionRow(title: "Activities", enabled: permissions.contains("Activities") || permissions.contains("Workouts"))
                    PermissionRow(title: "Sleep", enabled: permissions.contains("Sleep"))
                    PermissionRow(title: "Heart rate", enabled: permissions.contains("Heart Rate"))
                    PermissionRow(title: "Routes", enabled: permissions.contains("Routes"))
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Controls")
                    ActionRow(title: "Connect", detail: "Start the real permission or gateway flow.", symbol: "link") {
                        run { await services.connect(provider: serviceName) }
                    }
                    ActionRow(title: "Sync Now", detail: "Pull the latest real activity data.", symbol: "arrow.triangle.2.circlepath") {
                        run { await services.syncNow(provider: serviceName) }
                    }
                    Button("Disconnect \(serviceName)") {
                        run { await services.disconnect(provider: serviceName) }
                    }
                        .buttonStyle(NeonButtonStyle(isDestructive: true))
                        .disabled(isWorking)
                }
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
                                        RecentActivityRow(activity: activity)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            let statuses = await services.deviceStatuses()
            status = statuses.first(where: { $0.provider == serviceName })
            if serviceName == "Garmin Connect", let userID = session.currentUserID {
                recentActivities = await GarminBridge.shared.recentActivities(authUserID: userID, limit: 10)
            }
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

    private func run(_ action: @escaping () async -> ConnectedDeviceStatus) {
        isWorking = true
        Task {
            status = await action()
            isWorking = false
        }
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
                Image(systemName: symbol)
                    .font(.title3.bold())
                    .foregroundStyle(Color.lime)
                    .frame(width: 42, height: 42)
                    .background(Color.lime.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.mutedText)
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
                Image(systemName: symbol)
                    .font(.title3.bold())
                    .foregroundStyle(tint)
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

private struct WorkoutBreakdownStep {
    var title: String
    var duration: String
    var target: String
    var note: String
    var tint: Color
}

private struct WorkoutBreakdownStepRow: View {
    var step: WorkoutBreakdownStep

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
                Text("Intensity Target · \(step.target)")
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedText)
                Text(step.note)
                    .font(.caption.italic())
                    .foregroundStyle(Color.mutedText)
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
            Image(systemName: symbol)
                .foregroundStyle(selected ? Color.black : Color.lime)
                .frame(width: 34, height: 34)
                .background(selected ? Color.lime : Color.lime.opacity(0.12))
                .clipShape(Circle())
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
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.lime : Color.mutedText)
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
            Image(systemName: symbol)
                .foregroundStyle(Color.lime)
                .frame(width: 38, height: 38)
                .background(Color.lime.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var email: String {
        session.currentEmail ?? "--"
    }

    private var memberSince: String {
        guard let createdAt = session.currentMemberSince else { return "--" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt.string(from: createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
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
            .disabled(isSigningOut)

            Text("Signing out returns you to the sign-in screen, where you can register a new account or switch users.")
                .font(.caption)
                .foregroundStyle(Color.mutedText)
                .padding(.horizontal, 4)
        }
    }
}
