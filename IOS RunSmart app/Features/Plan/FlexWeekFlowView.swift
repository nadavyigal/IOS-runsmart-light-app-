import SwiftUI

enum FlexWeekFlowStep {
    case reasonPicker
    case loading
    case diff
    case confirmed
}

struct FlexWeekFlowView: View {
    @Environment(\.runSmartServices) private var services

    var currentWeek: [PlannedWorkout]
    var readinessContext: ReadinessContext?
    var preselectedReason: FlexWeekReason?
    var onDismiss: () -> Void

    @State private var step: FlexWeekFlowStep
    @State private var pendingRequest: FlexWeekRequest?
    @State private var outcome: FlexWeekOutcome?
    @State private var isApplying = false
    @State private var errorMessage: String?

    init(
        currentWeek: [PlannedWorkout],
        readinessContext: ReadinessContext? = nil,
        preselectedReason: FlexWeekReason? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.currentWeek = currentWeek
        self.readinessContext = readinessContext
        self.preselectedReason = preselectedReason
        self.onDismiss = onDismiss
        _step = State(initialValue: .reasonPicker)
    }

    var body: some View {
        ZStack {
            switch step {
            case .reasonPicker:
                FlexWeekReasonPicker(
                    currentWeek: currentWeek,
                    readinessContext: readinessContext,
                    preselectedReason: preselectedReason,
                    onCancel: onDismiss,
                    onContinue: beginRestructure
                )
                .transition(.opacity)

            case .loading:
                FlexWeekDiffView(
                    originalWeek: currentWeek,
                    outcome: placeholderOutcome,
                    isLoading: true,
                    onCancel: onDismiss,
                    onConfirm: {},
                    onKeepOriginal: onDismiss
                )
                .transition(.opacity)

            case .diff:
                if let outcome {
                    FlexWeekDiffView(
                        originalWeek: currentWeek,
                        outcome: outcome,
                        isLoading: false,
                        onCancel: onDismiss,
                        onConfirm: confirmOutcome,
                        onKeepOriginal: onDismiss
                    )
                    .overlay(alignment: .top) {
                        if let errorMessage {
                            flexWeekErrorBanner(errorMessage)
                                .padding(.horizontal, 20)
                                .padding(.top, 72)
                        }
                    }
                    .transition(.opacity)
                }

            case .confirmed:
                confirmationState
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: step)
    }

    private var placeholderOutcome: FlexWeekOutcome {
        FlexWeekOutcome(
            restructuredWeek: currentWeek,
            changes: [],
            safetyWarnings: [],
            source: .deterministicFallback
        )
    }

    private var confirmationState: some View {
        ZStack {
            RunSmartBackground(context: .plan)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Color.accentSuccess)
                Text("Your week is updated")
                    .font(.headingLG.weight(.bold))
                Text("Today, Plan, and weekly progress will reflect the new schedule.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .foregroundStyle(Color.textPrimary)
        }
        .onAppear {
            RunSmartHaptics.success()
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                onDismiss()
            }
        }
    }

    private func flexWeekErrorBanner(_ message: String) -> some View {
        RunSmartPanel(cornerRadius: 16, padding: 14, accent: .accentHeart) {
            Text(message)
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func beginRestructure(_ request: FlexWeekRequest) {
        pendingRequest = request
        errorMessage = nil
        step = .loading

        Task {
            // Story 3 wiring will swap this mock path for `flexCurrentWeek`.
            try? await Task.sleep(nanoseconds: 900_000_000)
            let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
                week: request.currentWeek,
                reason: request.reason
            )
            outcome = FlexWeekOutcome(
                restructuredWeek: updated,
                changes: changes,
                safetyWarnings: [],
                source: .deterministicFallback
            )
            step = .diff
        }
    }

    private func confirmOutcome() {
        guard let outcome, !isApplying else { return }
        isApplying = true
        errorMessage = nil

        Task {
            let applied = await services.applyFlexWeek(outcome)
            isApplying = false
            guard applied else {
                errorMessage = "Could not save your updated week. Your original plan is unchanged."
                return
            }
            RunSmartHaptics.success()
            step = .confirmed
        }
    }
}

#if DEBUG
#Preview("Flex Week Flow") {
    FlexWeekFlowView(
        currentWeek: RunSmartPreviewData.workouts,
        readinessContext: ReadinessContext.make(
            recovery: RunSmartPreviewData.recovery,
            recommendation: RunSmartPreviewData.today
        ),
        onDismiss: {}
    )
    .environment(\.runSmartServices, MockRunSmartServices())
    .preferredColorScheme(.dark)
}
#endif
