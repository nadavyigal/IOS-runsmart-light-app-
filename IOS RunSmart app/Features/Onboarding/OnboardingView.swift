import SwiftUI

struct OnboardingView: View {
    @State private var profile: OnboardingProfile
    var onComplete: (OnboardingProfile) -> Void

    private let goals = ["10K improvement", "First 5K", "Half marathon", "Marathon base"]
    private let experiences = ["Getting started", "Building base", "Consistent runner", "Race focused"]
    private let tones = ["Motivating", "Calm", "Direct"]
    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    init(initialProfile: OnboardingProfile, onComplete: @escaping (OnboardingProfile) -> Void) {
        _profile = State(initialValue: initialProfile)
        self.onComplete = onComplete
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                RunSmartHeader(showLogo: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Set up your coach")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("RunSmart will use these preferences with real GPS, HealthKit, and Garmin data.")
                        .foregroundStyle(Color.mutedText)
                }

                GlassCard(glow: Color.lime) {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Runner")
                        TextField("Your name", text: $profile.displayName)
                            .textFieldStyle(OnboardingFieldStyle())
                        PickerRow(title: "Goal", options: goals, selection: $profile.goal)
                        PickerRow(title: "Experience", options: experiences, selection: $profile.experience)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Schedule")
                        Stepper(value: $profile.weeklyRunDays, in: 2...7) {
                            HStack {
                                Text("Runs per week")
                                Spacer()
                                Text("\(profile.weeklyRunDays)")
                                    .foregroundStyle(Color.lime)
                                    .font(.headline)
                            }
                        }
                        .tint(Color.lime)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(weekdays, id: \.self) { day in
                                Button {
                                    toggleDay(day)
                                } label: {
                                    Text(day)
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(profile.preferredDays.contains(day) ? Color.lime : Color.white.opacity(0.08))
                                        .foregroundStyle(profile.preferredDays.contains(day) ? Color.black : Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(title: "Preferences")
                        PickerRow(title: "Units", options: ["Metric", "Imperial"], selection: $profile.units)
                        PickerRow(title: "Coach tone", options: tones, selection: $profile.coachingTone)
                        Toggle("Workout reminders", isOn: $profile.notificationsEnabled)
                            .tint(Color.lime)
                    }
                }

                Button {
                    var completed = profile
                    if completed.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        completed.displayName = "RunSmart Runner"
                    }
                    onComplete(completed)
                } label: {
                    Label("Start RunSmart", systemImage: "figure.run")
                }
                .buttonStyle(NeonButtonStyle())
            }
            .foregroundStyle(.white)
            .padding(20)
            .padding(.bottom, 28)
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

private struct PickerRow: View {
    var title: String
    var options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(Color.mutedText)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { selection = option }
                }
            } label: {
                HStack {
                    Text(selection)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundStyle(Color.lime)
                }
                .padding(12)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct OnboardingFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
