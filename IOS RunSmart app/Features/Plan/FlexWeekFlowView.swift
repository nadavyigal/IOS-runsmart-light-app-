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
    var entryPoint: FlexWeekEntryPoint
    var onDismiss: () -> Void
    var onTalkToCoach: (() -> Void)?

    @State private var step: FlexWeekFlowStep
    @State private var pendingRequest: FlexWeekRequest?
    @State private var outcome: FlexWeekOutcome?
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var restructureStartedAt: Date?
    @State private var priorAdjustmentCount: Int = 0

    init(
        currentWeek: [PlannedWorkout],
        readinessContext: ReadinessContext? = nil,
        preselectedReason: FlexWeekReason? = nil,
        entryPoint: FlexWeekEntryPoint = .planPill,
        onDismiss: @escaping () -> Void,
        onTalkToCoach: (() -> Void)? = nil
    ) {
        self.currentWeek = currentWeek
        self.readinessContext = readinessContext
        self.preselectedReason = preselectedReason
        self.entryPoint = entryPoint
        self.onDismiss = onDismiss
        self.onTalkToCoach = onTalkToCoach
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
                    showInterventionCard: priorAdjustmentCount >= 2,
                    onCancel: cancelAtPicker,
                    onContinue: beginRestructure,
                    onTalkToCoach: onTalkToCoach
                )
                .transition(.opacity)

            case .loading:
                FlexWeekDiffView(
                    originalWeek: currentWeek,
                    outcome: placeholderOutcome,
                    isLoading: true,
                    onCancel: cancelAtLoading,
                    onConfirm: {},
                    onKeepOriginal: cancelAtLoading
                )
                .transition(.opacity)

            case .diff:
                if let outcome {
                    FlexWeekDiffView(
                        originalWeek: currentWeek,
                        outcome: outcome,
                        isLoading: false,
                        onCancel: cancelAtDiff,
                        onConfirm: confirmOutcome,
                        onKeepOriginal: cancelAtDiff
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
        .task {
            priorAdjustmentCount = FlexWeekAdjustmentHistory.historyWithin(7 * 24 * 3600).count
        }
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
        restructureStartedAt = Date()
        step = .loading

        RunSmartAnalytics.flexWeekTriggered(
            reason: request.reason.kind,
            entryPoint: entryPoint
        )

        Task {
            let result = await services.flexCurrentWeek(request)
            outcome = result
            step = .diff
        }
    }

    private func confirmOutcome() {
        guard let outcome, !isApplying else { return }
        isApplying = true
        errorMessage = nil
        let startedAt = restructureStartedAt ?? Date()

        Task {
            let applied = await services.applyFlexWeek(outcome)
            isApplying = false
            guard applied else {
                errorMessage = "Could not save your updated week. Your original plan is unchanged."
                return
            }

            if let reason = pendingRequest?.reason {
                FlexWeekAdjustmentHistory.record(FlexWeekRecord(
                    reason: reason.kind.rawValue,
                    confirmedAt: Date(),
                    changesCount: outcome.changes.count
                ))
            }

            RunSmartAnalytics.flexWeekConfirmed(
                reason: pendingRequest?.reason.kind ?? .tired,
                source: outcome.source,
                changesCount: outcome.changes.count,
                timeToConfirmSeconds: Date().timeIntervalSince(startedAt)
            )

            RunSmartHaptics.success()
            step = .confirmed
        }
    }

    private func cancelAtPicker() {
        RunSmartAnalytics.flexWeekCancelled(step: .picker, reason: nil)
        onDismiss()
    }

    private func cancelAtLoading() {
        RunSmartAnalytics.flexWeekCancelled(step: .loading, reason: pendingRequest?.reason.kind)
        onDismiss()
    }

    private func cancelAtDiff() {
        RunSmartAnalytics.flexWeekCancelled(step: .diff, reason: pendingRequest?.reason.kind)
        onDismiss()
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
