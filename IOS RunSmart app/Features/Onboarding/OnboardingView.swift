import SwiftUI

enum OnboardingHealthKitStep {
    static let providerName = HealthKitSyncService.providerName

    static func didConnect(_ status: ConnectedDeviceStatus) -> Bool {
        status.provider == providerName && status.state == .connected
    }
}

struct OnboardingView: View {
    @Environment(\.runSmartServices) private var services

    @State private var profile: OnboardingProfile
    @State private var step = 0
    @State private var healthKitStatus: ConnectedDeviceStatus?
    @State private var isConnectingHealthKit = false
    var onComplete: (OnboardingProfile) -> Void

    private let goals = ["First 5K", "10K PR", "Half Marathon", "Marathon", "Just Run More"]
    private let experiences = ["Getting started", "Building base", "Consistent runner", "Race focused"]
    private let tones = ["Motivating", "Calm", "Direct"]
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let stepCount = 6

    init(initialProfile: OnboardingProfile, onComplete: @escaping (OnboardingProfile) -> Void) {
        _profile = State(initialValue: initialProfile)
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            RunSmartBackground(context: .today(readiness: 82))
            VStack(spacing: 0) {
                progress
                TabView(selection: $step) {
                    goalStep.tag(0)
                    experienceStep.tag(1)
                    scheduleStep.tag(2)
                    privacyStep.tag(3)
                    healthKitStep.tag(4)
                    completionStep.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .foregroundStyle(Color.textPrimary)
        .onAppear {
            if step == 0 {
                Analytics.trackOnboardingStarted()
            }
#if DEBUG
            applyDebugOnboardingStepIfNeeded()
#endif
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
            OnboardingPrimaryButton(title: "Continue", symbol: "arrow.right", action: advance)
        }
    }

    private var experienceStep: some View {
        OnboardingStepShell(title: "Runner experience", subtitle: "This controls how aggressively the plan progresses.", symbol: "figure.run") {
            OnboardingChoiceGrid(options: experiences, selection: $profile.experience)
            OnboardingPrimaryButton(title: "Continue", symbol: "arrow.right", action: advance)
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

    private var privacyStep: some View {
        OnboardingStepShell(title: "Privacy", subtitle: "Choose coaching tone and data signals. You can connect devices later.", symbol: "lock.shield.fill") {
            OnboardingChoiceGrid(options: tones, selection: $profile.coachingTone)
            Toggle("Smart return reminders", isOn: $profile.notificationsEnabled)
                .tint(Color.accentPrimary)
            Text("Reminders are local, low-frequency, and can be turned off from Profile.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            DevicePreviewRow(title: "Garmin Connect", detail: "Import supported runs and wellness signals after you connect Garmin.", symbol: "link.circle.fill")
            RookieChallengeCallout()
            OnboardingPrimaryButton(title: "Confirm Privacy", symbol: "arrow.right", action: advance)
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
            }

            if !isHealthKitConnected {
                Button("Continue without connecting") {
                    advance()
                }
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
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
        Task {
            let status = await services.connect(provider: OnboardingHealthKitStep.providerName)
            healthKitStatus = status
            isConnectingHealthKit = false
            if OnboardingHealthKitStep.didConnect(status) {
                advance()
            }
        }
    }

    private func advance() {
        let stepNames = ["goal", "experience", "schedule", "privacy", "healthkit", "ready"]
        let completedStep = step
        withAnimation(RunSmartMotion.tabSpring) {
            step = min(stepCount - 1, step + 1)
        }
        let name = completedStep < stepNames.count ? stepNames[completedStep] : "unknown"
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

private struct RookieChallengeCallout: View {
    var body: some View {
        HStack(spacing: 12) {
            RunSmartLogoMark(size: 42, filled: false, glow: false)
            VStack(alignment: .leading, spacing: 3) {
                Text("21-Day Rookie Challenge")
                    .font(.bodyMD.weight(.semibold))
                Text("A lightweight starter block for confidence, consistency, and safe progression.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(12)
        .background(Color.accentPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.accentPrimary.opacity(0.24), lineWidth: 1))
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
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(NeonButtonStyle())
    }
}

private struct DevicePreviewRow: View {
    var title: String
    var detail: String
    var symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 40, height: 40)
                .background(Color.accentPrimary.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.bodyMD.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}
