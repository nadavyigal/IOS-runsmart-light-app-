import SwiftUI

struct FlexWeekEntryView: View {
    @Environment(\.runSmartServices) private var services

    var launch: FlexWeekLaunchContext
    var onDismiss: () -> Void

    @State private var currentWeek: [PlannedWorkout] = []
    @State private var readinessContext: ReadinessContext?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if isLoading {
                loadingShell
            } else if loadFailed || currentWeek.isEmpty {
                unavailableShell
            } else {
                FlexWeekFlowView(
                    currentWeek: currentWeek,
                    readinessContext: readinessContext,
                    preselectedReason: launch.preselectedReason,
                    onDismiss: onDismiss
                )
            }
        }
        .task(id: launch.id) {
            await load()
        }
    }

    private var loadingShell: some View {
        ZStack {
            RunSmartBackground(context: .plan)
                .ignoresSafeArea()

            RunSmartPanel(cornerRadius: 22, padding: 20, accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Flex Week")
                    Text("Loading your week…")
                        .font(.headingMD.weight(.bold))
                    ProgressView()
                        .tint(.accentPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
        }
    }

    private var unavailableShell: some View {
        ZStack {
            RunSmartBackground(context: .plan)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("No plan week to adjust")
                    .font(.headingMD.weight(.bold))
                Text("Create or sync a training plan first, then come back to flex the week.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("Close", action: onDismiss)
                    .buttonStyle(NeonButtonStyle())
                    .padding(.horizontal, 20)
            }
            .foregroundStyle(Color.textPrimary)
        }
    }

    private func load() async {
        isLoading = true
        loadFailed = false

        async let weekTask = services.weeklyPlan()
        async let todayTask = services.todayRecommendation()
        async let recoveryTask = services.recoverySnapshot()
        let (week, today, recovery) = await (weekTask, todayTask, recoveryTask)

        currentWeek = week
        readinessContext = ReadinessContext.make(recovery: recovery, recommendation: today)
        loadFailed = week.isEmpty
        isLoading = false
    }
}

struct FlexWeekAdjustPill: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.bodyMD.weight(.bold))
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.accentPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Need to adjust?")
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Tell Coach what changed and rewrite this week.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)

                Text("Flex Week")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentPrimary, in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(14)
            .background(Color.surfaceElevated.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Need to adjust? Open Flex Week")
    }
}

struct FlexWeekTodayLink: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "figure.run.circle")
                    .font(.bodyMD.weight(.semibold))
                Text("Not feeling 100%?")
                    .font(.bodyMD.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Color.accentRecovery)
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Not feeling 100 percent? Adjust your week")
    }
}

#if DEBUG
#Preview("Flex Week Entry") {
    FlexWeekEntryView(
        launch: FlexWeekLaunchContext(entryPoint: .planPill),
        onDismiss: {}
    )
    .environment(\.runSmartServices, MockRunSmartServices())
    .preferredColorScheme(.dark)
}
#endif
