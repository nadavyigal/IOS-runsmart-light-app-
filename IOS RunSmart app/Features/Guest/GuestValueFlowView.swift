import SwiftUI
import Combine

enum GuestJourneyStep: Int, Codable, CaseIterable {
    case goal
    case experience
    case schedule
    case preview
}

struct GuestJourneyState: Codable, Equatable {
    var isActive: Bool
    var profile: OnboardingProfile
    var step: GuestJourneyStep
    var hasSeenPreview: Bool
    var didTrackAuthenticatedUpgrade: Bool

    static let inactive = GuestJourneyState(
        isActive: false,
        profile: .empty,
        step: .goal,
        hasSeenPreview: false,
        didTrackAuthenticatedUpgrade: false
    )

    var upgradeProfile: OnboardingProfile { profile }

    var authenticatedOnboardingStartStep: Int {
        hasSeenPreview ? 3 : 0
    }
}

/// Local-only state for value-before-auth. This store never creates a Supabase
/// user and never writes the runner's answers anywhere except UserDefaults on
/// this device. The full cloud plan is still created only after authentication.
@MainActor
final class GuestJourneyStore: ObservableObject {
    @Published private(set) var state: GuestJourneyState

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "runsmart.guestJourney.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let restored = try? JSONDecoder().decode(GuestJourneyState.self, from: data) {
            state = restored
        } else {
            state = .inactive
        }
    }

    func start() {
        guard !state.isActive else { return }
        var profile = OnboardingProfile.empty
        profile.experience = ""
        state = GuestJourneyState(
            isActive: true,
            profile: profile,
            step: .goal,
            hasSeenPreview: false,
            didTrackAuthenticatedUpgrade: false
        )
        persist()
    }

    func update(profile: OnboardingProfile, step: GuestJourneyStep) {
        state.isActive = true
        state.profile = profile
        state.step = step
        persist()
    }

    func markPreviewSeen() {
        guard !state.hasSeenPreview else { return }
        state.hasSeenPreview = true
        persist()
    }

    func markAuthenticatedUpgradeTracked() {
        guard !state.didTrackAuthenticatedUpgrade else { return }
        state.didTrackAuthenticatedUpgrade = true
        persist()
    }

    func clear() {
        state = .inactive
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct GuestWorkoutPreview: Identifiable, Equatable {
    var id: Date { scheduledDate }
    var scheduledDate: Date
    var weekday: String
    var kind: WorkoutKind
    var title: String
    var distanceKm: Double
    var durationMinutes: Int
    var detail: String
}

struct GuestPlanPreview: Equatable {
    var goal: String
    var experience: String
    var workouts: [GuestWorkoutPreview]

    var firstWorkout: GuestWorkoutPreview {
        precondition(!workouts.isEmpty, "A guest plan preview must contain a first workout")
        return workouts[0]
    }
}

/// A deterministic, conservative Week 1 recommendation. This is intentionally
/// local and modest: it proves personalization before auth without pretending a
/// backend-generated adaptive plan already exists.
enum GuestPlanPreviewBuilder {
    private static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static func make(
        profile: OnboardingProfile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> GuestPlanPreview {
        let dates = selectedDates(profile: profile, now: now, calendar: calendar)
        let baseDistance = baseDistanceKm(experience: profile.experience) * goalMultiplier(goal: profile.goal)

        let workouts = dates.enumerated().map { index, selection in
            let kind = workoutKind(index: index, count: dates.count, experience: profile.experience)
            let distance = roundedHalfKilometer(
                max(2, baseDistance * distanceMultiplier(index: index, count: dates.count, kind: kind))
            )
            let minutesPerKm = estimatedMinutesPerKm(experience: profile.experience)
            return GuestWorkoutPreview(
                scheduledDate: selection.date,
                weekday: selection.day,
                kind: kind,
                title: title(for: kind),
                distanceKm: distance,
                durationMinutes: max(15, Int((distance * minutesPerKm).rounded())),
                detail: detail(for: kind, goal: profile.goal, experience: profile.experience)
            )
        }

        return GuestPlanPreview(
            goal: profile.goal,
            experience: profile.experience,
            workouts: workouts
        )
    }

    private static func selectedDates(
        profile: OnboardingProfile,
        now: Date,
        calendar: Calendar
    ) -> [(day: String, date: Date)] {
        let desiredCount = min(max(profile.weeklyRunDays, 2), 7)
        let preferred = Set(profile.preferredDays.filter(weekdays.contains))
        let start = calendar.startOfDay(for: now)

        let candidates: [(day: String, date: Date)] = weekdays.compactMap { day in
            guard let offset = (1...7).first(where: { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return false }
                return weekday(for: date, calendar: calendar) == day
            }), let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }
            return (day, date)
        }

        var selected = candidates
            .filter { preferred.contains($0.day) }
            .sorted { $0.date < $1.date }
            .prefix(desiredCount)
            .map { $0 }

        if selected.count < desiredCount {
            let chosen = Set(selected.map(\.day))
            selected.append(contentsOf: candidates
                .filter { !chosen.contains($0.day) }
                .sorted { $0.date < $1.date }
                .prefix(desiredCount - selected.count))
        }

        return selected.sorted { $0.date < $1.date }
    }

    private static func weekday(for date: Date, calendar: Calendar) -> String {
        let index = max(1, min(7, calendar.component(.weekday, from: date))) - 1
        return weekdays[index]
    }

    private static func baseDistanceKm(experience: String) -> Double {
        switch experience {
        case "Getting started": 2.5
        case "Building base": 3.5
        case "Consistent runner": 5
        case "Race focused": 6
        default: 3
        }
    }

    private static func goalMultiplier(goal: String) -> Double {
        switch goal {
        case "First 5K": 0.9
        case "10K PR": 1.05
        case "Half Marathon": 1.2
        case "Marathon": 1.4
        case "Just Run More": 1
        default: 1
        }
    }

    private static func workoutKind(index: Int, count: Int, experience: String) -> WorkoutKind {
        if index == 0 { return .easy }
        if index == count - 1 { return .long }
        switch experience {
        case "Consistent runner": return index.isMultiple(of: 2) ? .intervals : .tempo
        case "Race focused": return index.isMultiple(of: 2) ? .tempo : .intervals
        case "Building base": return index.isMultiple(of: 2) ? .recovery : .easy
        default: return .easy
        }
    }

    private static func distanceMultiplier(index: Int, count: Int, kind: WorkoutKind) -> Double {
        if index == 0 { return 1 }
        if index == count - 1 { return 1.35 }
        switch kind {
        case .intervals, .tempo, .hills: return 0.9
        case .recovery: return 0.75
        default: return 1
        }
    }

    private static func estimatedMinutesPerKm(experience: String) -> Double {
        switch experience {
        case "Getting started": 7.5
        case "Building base": 7
        case "Consistent runner": 6.4
        case "Race focused": 5.8
        default: 7
        }
    }

    private static func roundedHalfKilometer(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    private static func title(for kind: WorkoutKind) -> String {
        switch kind {
        case .easy: "Easy foundation run"
        case .intervals: "Controlled intervals"
        case .tempo: "Steady tempo"
        case .long: "Long easy run"
        case .recovery: "Recovery run"
        default: kind.rawValue
        }
    }

    private static func detail(for kind: WorkoutKind, goal: String, experience: String) -> String {
        switch kind {
        case .easy:
            return experience == "Getting started"
                ? "Keep it conversational; walk breaks are welcome."
                : "Comfortable effort to establish your week."
        case .intervals:
            return "Short controlled efforts that support your \(goal.lowercased()) goal."
        case .tempo:
            return "A comfortably hard block with easy running around it."
        case .long:
            return "Stay relaxed and build time on feet, not speed."
        case .recovery:
            return "Very easy movement between your stronger sessions."
        default:
            return "A conservative first-week recommendation."
        }
    }
}

struct GuestValueFlowView: View {
    @ObservedObject var journey: GuestJourneyStore
    var onExitGuest: () -> Void
    var onRequestAuthentication: () -> Void

    @State private var profile: OnboardingProfile
    @State private var step: GuestJourneyStep

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    init(
        journey: GuestJourneyStore,
        onExitGuest: @escaping () -> Void,
        onRequestAuthentication: @escaping () -> Void
    ) {
        self.journey = journey
        self.onExitGuest = onExitGuest
        self.onRequestAuthentication = onRequestAuthentication
        _profile = State(initialValue: journey.state.profile)
        _step = State(initialValue: journey.state.step)
    }

    var body: some View {
        ZStack {
            RunSmartBackground(context: .today(readiness: 82))
            VStack(spacing: 0) {
                progress
                Group {
                    switch step {
                    case .goal: goalStep
                    case .experience: experienceStep
                    case .schedule: scheduleStep
                    case .preview: previewStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.opacity)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .onChange(of: profile) { _, newProfile in
            journey.update(profile: newProfile, step: step)
        }
        .onChange(of: step) { _, newStep in
            journey.update(profile: profile, step: newStep)
            if newStep == .preview {
                trackPreviewIfNeeded()
            }
        }
        .onAppear {
            if step == .preview {
                trackPreviewIfNeeded()
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            Button {
                if step == .goal {
                    onExitGuest()
                } else {
                    withAnimation(RunSmartMotion.tabSpring) {
                        step = GuestJourneyStep(rawValue: step.rawValue - 1) ?? .goal
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.surfaceElevated, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(step == .goal ? "Back to sign in" : "Back")

            ForEach(GuestJourneyStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Color.accentPrimary : Color.border)
                    .frame(height: 4)
            }

            Text("Guest")
                .font(.caption.bold())
                .foregroundStyle(Color.accentPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var goalStep: some View {
        OnboardingStepShell(
            title: "What are you running toward?",
            subtitle: "Three quick answers are enough for a useful first-week preview. No account needed.",
            symbol: "target"
        ) {
            OnboardingChoiceGrid(options: OnboardingView.goalOptions, selection: $profile.goal)
            OnboardingPrimaryButton(
                title: "Continue",
                symbol: "arrow.right",
                isEnabled: OnboardingView.canAdvanceFromGoal(profile),
                action: advance
            )
        }
    }

    private var experienceStep: some View {
        OnboardingStepShell(
            title: "Where are you starting?",
            subtitle: "This keeps the first week challenging enough without overreaching.",
            symbol: "figure.run"
        ) {
            OnboardingChoiceGrid(options: OnboardingView.experienceOptions, selection: $profile.experience)
            OnboardingPrimaryButton(
                title: "Continue",
                symbol: "arrow.right",
                isEnabled: OnboardingView.canAdvanceFromExperience(profile),
                action: advance
            )
        }
    }

    private var scheduleStep: some View {
        OnboardingStepShell(
            title: "Choose your weekly rhythm",
            subtitle: "Pick exactly \(profile.weeklyRunDays) days so the preview fits your real week.",
            symbol: "calendar"
        ) {
            Stepper(value: $profile.weeklyRunDays, in: 2...7) {
                HStack {
                    Text("Runs per week")
                    Spacer()
                    Text("\(profile.weeklyRunDays)")
                        .font(.metricSM)
                        .foregroundStyle(Color.accentPrimary)
                }
            }
            .tint(Color.accentPrimary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(weekdays, id: \.self) { day in
                    Button { toggleDay(day) } label: {
                        Text(day)
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(profile.preferredDays.contains(day) ? Color.accentPrimary : Color.surfaceElevated)
                            .foregroundStyle(profile.preferredDays.contains(day) ? Color.black : Color.textPrimary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if profile.preferredDays.count != profile.weeklyRunDays {
                Text("Select \(profile.weeklyRunDays) days (\(profile.preferredDays.count) selected).")
                    .font(.caption)
                    .foregroundStyle(Color.accentHeart)
            }

            OnboardingPrimaryButton(
                title: "Build my Week 1 preview",
                symbol: "sparkles",
                isEnabled: profile.preferredDays.count == profile.weeklyRunDays,
                action: advance
            )
        }
    }

    private var previewStep: some View {
        let preview = GuestPlanPreviewBuilder.make(profile: profile)
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your first week")
                        .font(.displayMD)
                        .displayTightTracking(-0.8)
                    Text("A conservative preview for \(profile.goal.lowercased()), based on \(profile.experience.lowercased()) and \(profile.weeklyRunDays) runs per week.")
                        .font(.bodyLG)
                        .foregroundStyle(Color.textSecondary)
                }

                GuestFirstWorkoutCard(workout: preview.firstWorkout)

                ContentCard {
                    VStack(spacing: 0) {
                        ForEach(Array(preview.workouts.enumerated()), id: \.element.id) { index, workout in
                            GuestWorkoutPreviewRow(workout: workout)
                            if index < preview.workouts.count - 1 {
                                Divider().overlay(Color.border)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("This preview stays on this iPhone", systemImage: "iphone")
                        .font(.bodyMD.weight(.semibold))
                    Text("Sign in to save your answers, generate the full adaptive plan, sync across devices, connect Apple Health or Garmin, and keep durable progress.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(14)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                OnboardingPrimaryButton(title: "Save & unlock full plan", symbol: "lock.open.fill") {
                    Analytics.trackGuestSignInPrompted(source: "week_one_preview")
                    onRequestAuthentication()
                }

                Button("Edit my answers") {
                    withAnimation(RunSmartMotion.tabSpring) { step = .goal }
                }
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .padding(.bottom, 24)
        }
    }

    private func advance() {
        guard let next = GuestJourneyStep(rawValue: step.rawValue + 1) else { return }
        if next == .preview {
            Analytics.trackGuestProfileCompleted(
                goal: profile.goal,
                experience: profile.experience,
                daysPerWeek: profile.weeklyRunDays
            )
        }
        withAnimation(RunSmartMotion.tabSpring) { step = next }
    }

    private func toggleDay(_ day: String) {
        if profile.preferredDays.contains(day) {
            profile.preferredDays.removeAll { $0 == day }
        } else if profile.preferredDays.count < profile.weeklyRunDays {
            profile.preferredDays.append(day)
        }
    }

    private func trackPreviewIfNeeded() {
        guard !journey.state.hasSeenPreview else { return }
        let preview = GuestPlanPreviewBuilder.make(profile: profile)
        journey.markPreviewSeen()
        Analytics.trackGuestPlanPreviewViewed(
            goal: profile.goal,
            experience: profile.experience,
            daysPerWeek: profile.weeklyRunDays,
            firstWorkoutType: preview.firstWorkout.kind.rawValue
        )
    }
}

private struct GuestFirstWorkoutCard: View {
    var workout: GuestWorkoutPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("YOUR FIRST RECOMMENDED RUN", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(Color.black)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(workout.weekday) · \(workout.title)")
                        .font(.title3.bold())
                    Text(workout.detail)
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.72))
                }
                Spacer(minLength: 12)
                Text(workout.distanceKm.formatted(.number.precision(.fractionLength(1))) + " km")
                    .font(.metricSM)
            }
        }
        .foregroundStyle(Color.black)
        .padding(18)
        .background(Color.accentPrimary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.accentPrimary.opacity(0.25), radius: 18)
    }
}

private struct GuestWorkoutPreviewRow: View {
    var workout: GuestWorkoutPreview

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind.symbol)
                .font(.body.bold())
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 38, height: 38)
                .background(Color.accentPrimary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("\(workout.weekday) · \(workout.title)")
                    .font(.bodyMD.weight(.semibold))
                Text("\(workout.durationMinutes) min · " + workout.distanceKm.formatted(.number.precision(.fractionLength(1))) + " km")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}
