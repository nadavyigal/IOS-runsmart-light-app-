import SwiftUI

enum OnboardingHealthKitStep {
    static let providerName = HealthKitSyncService.providerName

    static func didConnect(_ status: ConnectedDeviceStatus) -> Bool {
        status.provider == providerName && status.state == .connected
    }

    /// WP-44 S2: a failed connect used to silently reset the button (audit §4
    /// Risk 7, §10 B5) — the user tapped, nothing visibly happened, and there
    /// was no hint the action failed or where to retry. Nil means connected.
    static func failureMessage(for status: ConnectedDeviceStatus) -> String? {
        guard !didConnect(status) else { return nil }
        return "Couldn't connect Apple Health. You can try again now, or later from Profile."
    }
}

struct OnboardingView: View {
    @Environment(\.runSmartServices) private var services
    @Environment(\.scenePhase) private var scenePhase

    @State private var profile: OnboardingProfile
    @State private var step = 0
    @State private var stepEnteredAt = Date()
    @State private var maxCompletedStep = -1
    @State private var healthKitStatus: ConnectedDeviceStatus?
    @State private var isConnectingHealthKit = false
    @State private var healthKitFailureMessage: String?
    var onComplete: (OnboardingProfile) -> Void

    /// Analytics step names — "privacy" is kept for the renamed Coaching step so
    /// existing PostHog funnels stay intact (WP-44 S4).
    static let analyticsStepNames = ["goal", "experience", "schedule", "privacy", "healthkit", "ready"]

    static let goalOptions = ["First 5K", "10K PR", "Half Marathon", "Marathon", "Just Run More"]
    static let experienceOptions = ["Getting started", "Building base", "Consistent runner", "Race focused"]

    /// WP-44 S4: the step was titled "Privacy" with a "Confirm Privacy" CTA, but
    /// its content is coaching tone + reminders (audit §7/§9 — title didn't match
    /// content). Static so the copy is testable.
    static let coachingStepTitle = "Coaching"
    static let coachingStepCTA = "Continue"

    /// A goal step may only advance once the user has picked a visible option,
    /// so a plan is never built from an empty or unseen goal (audit §4 Risk 9).
    static func canAdvanceFromGoal(_ profile: OnboardingProfile) -> Bool {
        goalOptions.contains(profile.goal)
    }

    static func canAdvanceFromExperience(_ profile: OnboardingProfile) -> Bool {
        experienceOptions.contains(profile.experience)
    }

    private let goals = OnboardingView.goalOptions
    private let experiences = OnboardingView.experienceOptions
    private let tones = ["Motivating", "Calm", "Direct"]
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    // Derived from the analytics names so the progress bar, the step switch,
    // and the funnel names can't drift apart.
    private var stepCount: Int { Self.analyticsStepNames.count }

    init(initialProfile: OnboardingProfile, onComplete: @escaping (OnboardingProfile) -> Void) {
        _profile = State(initialValue: initialProfile)
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            RunSmartBackground(context: .today(readiness: 82))
            VStack(spacing: 0) {
                progress
                // Render only the active step. A page-style TabView let users
                // swipe past a required step (e.g. leave Goal with no visible
                // selection), and blocking that with a drag gesture would also
                // swallow the vertical scrolling inside each step — on a short
                // screen or at large Dynamic Type that can strand the Continue
                // button off-screen. Steps advance only via Continue.
                Group {
                    switch step {
                    case 0: goalStep
                    case 1: experienceStep
                    case 2: scheduleStep
                    case 3: coachingStep
                    case 4: healthKitStep
                    default: completionStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.opacity)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .onAppear {
            if step == 0 {
                Analytics.trackOnboardingStarted()
            }
            stepEnteredAt = Date()
#if DEBUG
            applyDebugOnboardingStepIfNeeded()
#endif
        }
        .onChange(of: step) {
            stepEnteredAt = Date()
        }
        // WP-45: leaving the app mid-onboarding was invisible — only completed
        // steps were tracked, so an abandon at the Goal step looked like nothing.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            let name = step < Self.analyticsStepNames.count ? Self.analyticsStepNames[step] : "unknown"
            Analytics.trackOnboardingStepAbandoned(
                lastStep: name,
                dwellSeconds: Int(Date().timeIntervalSince(stepEnteredAt))
            )
        }
    }

#if DEBUG
    private func applyDebugOnboardingStepIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-RUNSMART_ONBOARDING_STEP"),
              args.indices.contains(idx + 1),
              let requested = Int(args[idx + 1]) else { return }
        step = min(max(requested, 0), stepCount - 1)
    }
#endif

    private var progress: some View {
        HStack(spacing: 6) {
            // WP-44 S4: onboarding had no back affordance — a mis-tapped Continue
            // was unrecoverable. Steps still only advance via Continue.
            Button {
                withAnimation(RunSmartMotion.tabSpring) {
                    step = max(0, step - 1)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.surfaceElevated, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(step > 0 ? 1 : 0)
            .disabled(step == 0 || isConnectingHealthKit)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("onboarding.back")

            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.accentPrimary : Color.border)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var goalStep: some View {
        OnboardingStepShell(title: "Goal", subtitle: "Pick the result your RunSmart coach should build around.", symbol: "target") {
            OnboardingChoiceGrid(options: goals, selection: $profile.goal)
            OnboardingPrimaryButton(
                title: "Continue",
                symbol: "arrow.right",
                isEnabled: Self.canAdvanceFromGoal(profile),
                action: advance
            )
        }
    }

    private var experienceStep: some View {
        OnboardingStepShell(title: "Runner experience", subtitle: "This controls how aggressively the plan progresses.", symbol: "figure.run") {
            OnboardingChoiceGrid(options: experiences, selection: $profile.experience)
            OnboardingPrimaryButton(
                title: "Continue",
                symbol: "arrow.right",
                isEnabled: Self.canAdvanceFromExperience(profile),
                action: advance
            )
        }
    }

    private var scheduleStep: some View {
        OnboardingStepShell(title: "Weekly rhythm", subtitle: "Choose run days and total weekly frequency.", symbol: "calendar") {
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
            OnboardingPrimaryButton(title: "Continue", symbol: "arrow.right", action: advance)
        }
    }

    // WP-44 S4: Garmin's DevicePreviewRow and the 21-Day Rookie Challenge callout
    // moved out of onboarding — both already exist post-activation (Garmin connect
    // in Profile, the challenge card on Today), so onboarding no longer front-loads
    // marketing before the user has seen the product.
    private var coachingStep: some View {
        OnboardingStepShell(title: Self.coachingStepTitle, subtitle: "Choose coaching tone and reminders. You can connect devices later.", symbol: "person.wave.2.fill") {
            OnboardingChoiceGrid(options: tones, selection: $profile.coachingTone)
            Toggle("Smart return reminders", isOn: $profile.notificationsEnabled)
                .tint(Color.accentPrimary)
            Text("Reminders are local, low-frequency, and can be turned off from Profile.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            OnboardingPrimaryButton(title: Self.coachingStepCTA, symbol: "arrow.right", action: advance)
        }
    }

    private var healthKitStep: some View {
        OnboardingStepShell(
            title: "Apple Health",
            subtitle: "Import workouts and wellness data you already track. You can skip and connect later from Profile.",
            symbol: "heart.fill"
        ) {
            Text("RunSmart uses HealthKit to read only the workout and wellness data you approve, including workouts, routes, heart rate, HRV, sleep, steps, and active energy. If you allow write access, completed GPS runs can be saved back to Health.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            if let healthKitStatus, OnboardingHealthKitStep.didConnect(healthKitStatus) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.lime)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Health connected")
                            .font(.bodyMD.weight(.semibold))
                        if let message = healthKitStatus.message, !message.isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.lime.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                OnboardingPrimaryButton(title: "Continue", symbol: "arrow.right", action: advance)
            } else {
                OnboardingPrimaryButton(title: isConnectingHealthKit ? "Connecting…" : "Connect Apple Health", symbol: "link") {
                    connectHealthKit()
                }
                .disabled(isConnectingHealthKit)
                .accessibilityIdentifier("onboarding.healthkit.connect")

                if let healthKitFailureMessage {
                    Text(healthKitFailureMessage)
                        .font(.caption)
                        .foregroundStyle(Color.accentHeart)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("onboarding.healthkit.failure")
                }
            }

            if !isHealthKitConnected {
                Button("Continue without connecting") {
                    advance()
                }
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .disabled(isConnectingHealthKit)
                .accessibilityIdentifier("onboarding.healthkit.skip")
            }
        }
        .task(id: step) {
            guard step == 4 else { return }
            await refreshHealthKitStatus()
            Analytics.trackHealthKitDisclosureViewed(state: healthKitStatus?.state.rawValue ?? "unknown")
        }
    }

    private var completionStep: some View {
        OnboardingStepShell(title: "Ready", subtitle: "RunSmart is building your plan. Next, commit to your first run.", symbol: "checkmark.seal.fill") {
            OnboardingPrimaryButton(title: "Start RunSmart", symbol: "figure.run") {
                var completed = profile
                if completed.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    completed.displayName = "RunSmart Runner"
                }
                Analytics.trackOnboardingCompleted(
                    goal: completed.goal,
                    experience: completed.experience,
                    daysPerWeek: completed.weeklyRunDays
                )
                onComplete(completed)
            }
        }
    }

    private var isHealthKitConnected: Bool {
        guard let healthKitStatus else { return false }
        return OnboardingHealthKitStep.didConnect(healthKitStatus)
    }

    private func refreshHealthKitStatus() async {
        let statuses = await services.deviceStatuses()
        healthKitStatus = statuses.first(where: { $0.provider == OnboardingHealthKitStep.providerName })
    }

    private func connectHealthKit() {
        guard !isConnectingHealthKit else { return }
        Analytics.trackHealthKitConnectTapped()
        isConnectingHealthKit = true
        healthKitFailureMessage = nil
        let initiatingStep = step
        Task {
            let status = await services.connect(provider: OnboardingHealthKitStep.providerName)
            healthKitStatus = status
            isConnectingHealthKit = false
            // The connect runs a sync after the permission sheet, so the user
            // can navigate (Back/Skip) before it resolves. A stale completion
            // must not advance from — or show errors on — a different step.
            guard step == initiatingStep else { return }
            if OnboardingHealthKitStep.didConnect(status) {
                advance()
            } else {
                healthKitFailureMessage = OnboardingHealthKitStep.failureMessage(for: status)
                Analytics.trackHealthKitConnectFailed(reason: status.state.rawValue)
            }
        }
    }

    private func advance() {
        let completedStep = step
        withAnimation(RunSmartMotion.tabSpring) {
            step = min(stepCount - 1, step + 1)
        }
        // The Back button (WP-44 S4) makes steps re-enterable; only report the
        // first completion of each step or back-then-forward would double-count
        // in the funnel.
        guard completedStep > maxCompletedStep else { return }
        maxCompletedStep = completedStep
        let name = completedStep < Self.analyticsStepNames.count ? Self.analyticsStepNames[completedStep] : "unknown"
        Analytics.trackOnboardingStepCompleted(stepNumber: completedStep + 1, stepName: name)
    }

    private func toggleDay(_ day: String) {
        if profile.preferredDays.contains(day) {
            profile.preferredDays.removeAll { $0 == day }
        } else {
            profile.preferredDays.append(day)
        }
    }
}

private struct OnboardingStepShell<Content: View>: View {
    var title: String
    var subtitle: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    RunSmartLogoMark(size: 76, filled: false, glow: true)
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(Color.black)
                        .frame(width: 52, height: 52)
                        .background(Color.accentPrimary, in: Circle())
                        .shadow(color: Color.accentPrimary.opacity(0.36), radius: 18)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.displayMD)
                        .displayTightTracking(-0.8)
                    Text(subtitle)
                        .font(.bodyLG)
                        .foregroundStyle(Color.textSecondary)
                }
                ContentCard {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                }
            }
            .padding(24)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
    }
}

private struct OnboardingChoiceGrid: View {
    var options: [String]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(option)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(selection == option ? Color.black : Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(10)
                        .background(selection == option ? Color.accentPrimary : Color.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct OnboardingPrimaryButton: View {
    var title: String
    var symbol: String
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(NeonButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

