import SwiftUI

struct OnboardingView: View {
    @State private var profile: OnboardingProfile
    @State private var step = 0
    var onComplete: (OnboardingProfile) -> Void

    private let goals = ["First 5K", "10K PR", "Half Marathon", "Marathon", "Just Run More"]
    private let experiences = ["Getting started", "Building base", "Consistent runner", "Race focused"]
    private let tones = ["Motivating", "Calm", "Direct"]
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

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
                    welcome.tag(0)
                    goalStep.tag(1)
                    experienceStep.tag(2)
                    scheduleStep.tag(3)
                    preferencesStep.tag(4)
                    devicesStep.tag(5)
                    completionStep.tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .foregroundStyle(Color.textPrimary)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.accentPrimary : Color.border)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    private var welcome: some View {
        OnboardingStepShell(title: "RunSmart", subtitle: "Your AI Running Coach", symbol: "bolt.fill") {
            TextField("Your name", text: $profile.displayName)
                .textFieldStyle(OnboardingFieldStyle())
            OnboardingPrimaryButton(title: "Get Started", symbol: "arrow.right") {
                advance()
            }
        }
    }

    private var goalStep: some View {
        OnboardingStepShell(title: "What are we training for?", subtitle: "Pick the goal that should shape your plan.", symbol: "target") {
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

    private var preferencesStep: some View {
        OnboardingStepShell(title: "Coach personality", subtitle: "Pick how direct your coach should feel.", symbol: "sparkles") {
            OnboardingChoiceGrid(options: tones, selection: $profile.coachingTone)
            Toggle("Workout reminders", isOn: $profile.notificationsEnabled)
                .tint(Color.accentPrimary)
            OnboardingPrimaryButton(title: "Continue", symbol: "arrow.right", action: advance)
        }
    }

    private var devicesStep: some View {
        OnboardingStepShell(title: "Connect devices", subtitle: "Garmin and HealthKit improve coaching context.", symbol: "applewatch") {
            DevicePreviewRow(title: "Garmin Connect", detail: "Import runs, HRV, sleep, and body battery.", symbol: "link.circle.fill")
            DevicePreviewRow(title: "HealthKit", detail: "Read and write completed workouts.", symbol: "heart.fill")
            OnboardingPrimaryButton(title: "Skip for now", symbol: "arrow.right", action: advance)
        }
    }

    private var completionStep: some View {
        OnboardingStepShell(title: "Your coach is ready", subtitle: "The first plan decision is waiting in Today.", symbol: "checkmark.seal.fill") {
            OnboardingPrimaryButton(title: "Start RunSmart", symbol: "figure.run") {
                var completed = profile
                if completed.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    completed.displayName = "RunSmart Runner"
                }
                onComplete(completed)
            }
        }
    }

    private func advance() {
        withAnimation(RunSmartMotion.tabSpring) {
            step = min(6, step + 1)
        }
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
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 20)
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(Color.black)
                .frame(width: 84, height: 84)
                .background(Color.accentPrimary, in: Circle())
                .shadow(color: Color.accentPrimary.opacity(0.36), radius: 22)
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
            Spacer(minLength: 20)
        }
        .padding(24)
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

private struct OnboardingFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(Color.textPrimary)
            .padding(12)
            .background(Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
