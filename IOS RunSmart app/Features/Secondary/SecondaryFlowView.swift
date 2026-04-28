import SwiftUI

enum SecondaryDestination: Hashable, Identifiable {
    case workoutDetail(WorkoutSummary)
    case planAdjustment
    case reschedule(WorkoutSummary)
    case addActivity
    case routeSelector
    case postRunSummary
    case audioCues
    case lapMarker
    case voiceCoaching
    case coachingTone
    case goalFocus
    case reminders
    case connectedService(String)

    var id: String {
        switch self {
        case .workoutDetail(let w): "workoutDetail-\(w.id)"
        case .planAdjustment: "planAdjustment"
        case .reschedule(let w): "reschedule-\(w.id)"
        case .addActivity: "addActivity"
        case .routeSelector: "routeSelector"
        case .postRunSummary: "postRunSummary"
        case .audioCues: "audioCues"
        case .lapMarker: "lapMarker"
        case .voiceCoaching: "voiceCoaching"
        case .coachingTone: "coachingTone"
        case .goalFocus: "goalFocus"
        case .reminders: "reminders"
        case .connectedService(let name): "connectedService-\(name)"
        }
    }

    var title: String {
        switch self {
        case .workoutDetail(let w): w.title
        case .planAdjustment: "Plan Adjustment"
        case .reschedule: "Reschedule"
        case .addActivity: "Add Activity"
        case .routeSelector: "Route Selector"
        case .postRunSummary: "Post-Run Summary"
        case .audioCues: "Audio Cues"
        case .lapMarker: "Lap Marker"
        case .voiceCoaching: "Voice Coaching"
        case .coachingTone: "Coaching Tone"
        case .goalFocus: "Goal Focus"
        case .reminders: "Reminders & Preferences"
        case .connectedService(let name): name
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
                .foregroundStyle(.white)
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
        case .postRunSummary:
            PostRunSummaryScaffold()
        case .audioCues:
            AudioCuesScaffold()
        case .lapMarker:
            LapMarkerScaffold()
        case .voiceCoaching:
            VoiceCoachingScaffold()
        case .coachingTone:
            CoachingToneScaffold()
        case .goalFocus:
            GoalFocusScaffold()
        case .reminders:
            ReminderPreferencesScaffold()
        case .connectedService(let serviceName):
            ConnectedServiceDetailScaffold(serviceName: serviceName)
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
        }
    }

    private var symbol: String {
        switch destination {
        case .workoutDetail(let workout): workout.kind.symbol
        case .planAdjustment: "slider.horizontal.3"
        case .reschedule: "calendar.badge.clock"
        case .addActivity: "plus.circle.fill"
        case .routeSelector: "map.fill"
        case .postRunSummary: "checkmark.seal.fill"
        case .audioCues: "speaker.wave.2.fill"
        case .lapMarker: "flag.fill"
        case .voiceCoaching: "waveform"
        case .coachingTone: "sparkles"
        case .goalFocus: "target"
        case .reminders: "bell.badge.fill"
        case .connectedService: "link.circle.fill"
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
                    LinearGradient(colors: [Color.lime, Color.electricGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.lime.opacity(0.46), radius: 16)

            VStack(alignment: .leading, spacing: 6) {
                Text(destination.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.mutedText)
            }
        }
        .padding(.top, 8)
    }
}

private struct WorkoutDetailScaffold: View {
    @EnvironmentObject private var router: AppRouter

    var workout: WorkoutSummary

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Today's Session", trailing: workout.distance)
                    Text("Purpose")
                        .font(.headline)
                    Text("Build controlled threshold fitness without turning the workout into a race. The win is even pacing and a strong finish.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.84))

                    HStack(spacing: 10) {
                        FlowChip(text: "Warm up 12 min", symbol: "flame")
                        FlowChip(text: "RPE 7/10", symbol: "speedometer")
                        FlowChip(text: "Cool down 8 min", symbol: "wind")
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Execution Plan")
                    FlowTimelineStep(index: "1", title: "Warm up easy", detail: "Keep breathing relaxed. Add two 20-second strides near the end.")
                    FlowTimelineStep(index: "2", title: "Tempo block", detail: "Hold 5:15/km and keep the effort controlled through the middle.")
                    FlowTimelineStep(index: "3", title: "Finish smooth", detail: "Do not sprint. Let the last 800m feel steady and confident.")
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
    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Activity Type")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        FlowSelectionTile(title: "Easy Run", value: "5.0 km", symbol: "figure.run", selected: true)
                        FlowSelectionTile(title: "Strength", value: "40 min", symbol: "dumbbell", selected: false)
                        FlowSelectionTile(title: "Bike", value: "45 min", symbol: "bicycle", selected: false)
                        FlowSelectionTile(title: "Mobility", value: "20 min", symbol: "figure.flexibility", selected: false)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Manual Entry")
                    DetailLine(label: "Date", value: "Today, 7:10 AM")
                    DetailLine(label: "Effort", value: "Easy, RPE 4")
                    DetailLine(label: "Notes", value: "Felt smooth after the first kilometer.")
                }
            }

            Button("Save Activity") {}
                .buttonStyle(NeonButtonStyle())
        }
    }
}

private struct RouteSelectorScaffold: View {
    @Environment(\.runSmartServices) private var services
    @State private var routes: [RouteSuggestion] = []
    @State private var selectedRouteID: String?

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
                    SectionLabel(title: "Route Options")
                    if routes.isEmpty {
                        Text("Record a GPS run first, then RunSmart can suggest real routes from your activity history.")
                            .font(.callout)
                            .foregroundStyle(Color.mutedText)
                    } else {
                        ForEach(routes) { route in
                            RouteOptionRow(
                                title: route.name,
                                detail: "\(String(format: "%.1f", route.distanceKm)) km | \(route.elevationGainMeters) m gain",
                                selected: route.id == selectedRouteID
                            )
                            .onTapGesture {
                                selectedRouteID = route.id
                            }
                        }
                    }
                }
            }

            Button("Use This Route") {}
                .buttonStyle(NeonButtonStyle())
        }
        .task {
            routes = await services.routeSuggestions()
            selectedRouteID = routes.first?.id
        }
    }

    private var selectedRoute: RouteSuggestion? {
        routes.first(where: { $0.id == selectedRouteID }) ?? routes.first
    }

    private var routeDetail: String {
        guard let route = selectedRoute else { return "Route suggestions use real recorded GPS data." }
        return "\(String(format: "%.1f", route.distanceKm)) km | \(route.elevationGainMeters) m gain | \(route.estimatedDurationMinutes) min"
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
                    SectionLabel(title: "Live Preview")
                    HStack(spacing: 12) {
                        AudioBars()
                            .frame(width: 110, height: 28)
                        Text("You are a little fast. Ease back five seconds per kilometer.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.84))
                    }
                    .padding(12)
                    .background(Color.lime.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

private struct LapMarkerScaffold: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Current Lap")
                    Text("Lap 5")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                    HStack {
                        MetricBadge(title: "Split", value: "5:07")
                        MetricBadge(title: "Distance", value: "1.00 km")
                        MetricBadge(title: "HR", value: "158")
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Coach Note")
                    Text("Strong rhythm. Mark this lap as controlled tempo and keep the next one even.")
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedText)
                    Button("Mark Lap") {}
                        .buttonStyle(NeonButtonStyle())
                }
            }
        }
    }
}

private struct PostRunSummaryScaffold: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Run Complete")
                    HStack {
                        MetricBadge(title: "Distance", value: "8.2 km")
                        MetricBadge(title: "Avg Pace", value: "5:12")
                        MetricBadge(title: "Time", value: "42:38")
                    }
                    Text("Coach Spark: You nailed the middle tempo block and stayed controlled. That is the exact stimulus we wanted.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.84))
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Splits")
                    ForEach(["5:25", "5:18", "5:12", "5:08", "5:07"], id: \.self) { split in
                        HStack {
                            Text("Lap")
                                .foregroundStyle(Color.mutedText)
                            Spacer()
                            Text(split)
                                .font(.headline)
                            Capsule()
                                .fill(Color.lime.opacity(0.45))
                                .frame(width: 64, height: 6)
                        }
                    }
                }
            }

            Button("Save Run") {}
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

private struct GoalFocusScaffold: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            GlassCard(glow: Color.lime) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Current Focus")
                    FlowSelectionTile(title: "10K Improvement", value: "Primary", symbol: "target", selected: true)
                    FlowSelectionTile(title: "Consistency", value: "Secondary", symbol: "checkmark.seal", selected: false)
                    FlowSelectionTile(title: "Recovery Balance", value: "Guardrail", symbol: "heart", selected: false)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Coach Will Optimize")
                    DetailLine(label: "Workout mix", value: "Tempo plus aerobic base")
                    DetailLine(label: "Load cap", value: "No more than 12% weekly jump")
                    DetailLine(label: "Race estimate", value: "46:30 target")
                }
            }
        }
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
    var serviceName: String
    @State private var status: ConnectedDeviceStatus?
    @State private var isWorking = false

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
        }
        .task {
            let statuses = await services.deviceStatuses()
            status = statuses.first(where: { $0.provider == serviceName })
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
