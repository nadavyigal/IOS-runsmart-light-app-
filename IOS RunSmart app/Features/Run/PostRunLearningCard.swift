import SwiftUI

enum PostRunPlanImpact: String, Hashable {
    case changed
    case unchanged
    case unavailable
    case needsReview

    var label: String {
        switch self {
        case .changed: "Changed"
        case .unchanged: "Unchanged"
        case .unavailable: "Unavailable"
        case .needsReview: "Needs review"
        }
    }

    var tint: Color {
        switch self {
        case .changed: .accentSuccess
        case .unchanged: .accentPrimary
        case .unavailable: .textSecondary
        case .needsReview: .accentEnergy
        }
    }
}

enum PostRunLearningSource: String, Hashable {
    case ai = "AI"
    case fallback = "Fallback"
    case report = "Report"
    case heuristic = "Heuristic"
}

enum PostRunLearningAction: Hashable {
    case saveSuggestedWorkout(StructuredNextWorkout, RunReportDetail)
    case unavailable(String)
}

struct PostRunLearningCardModel: Hashable {
    var happened: String
    var learned: String
    var planImpact: PostRunPlanImpact
    var nextActionTitle: String
    var source: PostRunLearningSource
    var action: PostRunLearningAction

    static func make(
        run: RecordedRun?,
        outcome: PostActivityOutcome?,
        report: RunReportDetail?,
        activePlan: TrainingPlanSnapshot?
    ) -> PostRunLearningCardModel {
        let resolvedRun = outcome?.canonicalRun ?? run
        let resolvedReport = report ?? outcome?.report
        let distanceKm = (resolvedRun?.distanceMeters ?? 0) / 1_000
        let duration = resolvedRun?.movingTimeSeconds ?? 0
        let isShort = distanceKm < 0.5 || duration < 180
        let hasPoorGPS = resolvedRun.map { !$0.routePoints.isEmpty && $0.routePoints.count < RouteMatchingService.minimumRoutePoints } ?? false
        let hasNoMap = resolvedRun?.routePoints.isEmpty ?? true
        let matchedBenchmark = resolvedRun?.routeMatchResult?.confidence == .matched

        let happened = happenedText(
            run: resolvedRun,
            distanceKm: distanceKm,
            isShort: isShort,
            hasPoorGPS: hasPoorGPS,
            matchedBenchmark: matchedBenchmark
        )
        let learned = learnedText(
            run: resolvedRun,
            report: resolvedReport,
            isShort: isShort,
            hasPoorGPS: hasPoorGPS,
            hasNoMap: hasNoMap,
            matchedBenchmark: matchedBenchmark
        )
        let impact = planImpact(outcome: outcome, report: resolvedReport, activePlan: activePlan, isShort: isShort)
        let source = source(for: resolvedReport, run: resolvedRun)
        let action = nextAction(report: resolvedReport, impact: impact, isShort: isShort)

        return PostRunLearningCardModel(
            happened: happened,
            learned: learned,
            planImpact: impact,
            nextActionTitle: action.title,
            source: source,
            action: action.kind
        )
    }

    private static func happenedText(
        run: RecordedRun?,
        distanceKm: Double,
        isShort: Bool,
        hasPoorGPS: Bool,
        matchedBenchmark: Bool
    ) -> String {
        guard let run else {
            return "RunSmart saved the activity draft, but no final run data was available."
        }

        let source = run.source.rawValue
        if isShort {
            return "\(source) saved a short \(String(format: "%.1f", distanceKm)) km activity."
        }
        if matchedBenchmark {
            return "\(source) completed \(String(format: "%.1f", distanceKm)) km on a benchmark route."
        }
        if hasPoorGPS {
            return "\(source) completed \(String(format: "%.1f", distanceKm)) km with limited GPS detail."
        }
        return "\(source) completed \(String(format: "%.1f", distanceKm)) km at \(RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm)) /km."
    }

    private static func learnedText(
        run: RecordedRun?,
        report: RunReportDetail?,
        isShort: Bool,
        hasPoorGPS: Bool,
        hasNoMap: Bool,
        matchedBenchmark: Bool
    ) -> String {
        if let report, report.hasGeneratedReport {
            return report.notes.summary
        }
        if isShort {
            return "Coach learned this is too short to change training load by itself."
        }
        if matchedBenchmark {
            return "Coach learned how this route effort compares with your repeatable benchmark."
        }
        if hasPoorGPS {
            return "Coach learned the effort, but route matching may need cleaner GPS next time."
        }
        if hasNoMap, run?.source != .runSmart {
            return "Coach learned the distance and duration, but no route shape was available."
        }
        return "Coach learned this adds real recent load and should keep the next step controlled."
    }

    private static func planImpact(
        outcome: PostActivityOutcome?,
        report: RunReportDetail?,
        activePlan: TrainingPlanSnapshot?,
        isShort: Bool
    ) -> PostRunPlanImpact {
        if outcome?.didCompletePlannedWorkout == true {
            return .changed
        }
        guard activePlan != nil else {
            return .unavailable
        }
        if isShort || report?.structuredNextWorkout != nil {
            return .needsReview
        }
        return .unchanged
    }

    private static func source(for report: RunReportDetail?, run: RecordedRun?) -> PostRunLearningSource {
        guard let report else {
            return run == nil ? .heuristic : .heuristic
        }
        if !report.hasGeneratedReport {
            return .report
        }
        return report.coachScore == nil ? .fallback : .ai
    }

    private static func nextAction(
        report: RunReportDetail?,
        impact: PostRunPlanImpact,
        isShort: Bool
    ) -> (title: String, kind: PostRunLearningAction) {
        if let report, let next = report.structuredNextWorkout {
            if TrainingPlanRepository.suggestedWorkoutNeedsReview(next) {
                return ("Review suggested workout", .unavailable(PostRunSuggestedWorkoutSaveCopy.reviewMessage))
            }
            return ("Save suggested next run", .saveSuggestedWorkout(next, report))
        }
        if impact == .unavailable {
            return ("Create a plan first", .unavailable("Create a plan first"))
        }
        if isShort {
            return ("Review manually", .unavailable("Review manually"))
        }
        return ("Keep next run easy", .unavailable("Keep next run easy"))
    }
}

struct PostRunLearningCard: View {
    @Environment(\.runSmartServices) private var services
    var run: RecordedRun?
    var outcome: PostActivityOutcome?
    var report: RunReportDetail?
    var isProcessing: Bool = false

    @State private var activePlan: TrainingPlanSnapshot?
    @State private var isSaving = false
    @State private var saveState: SaveState = .idle

    private var model: PostRunLearningCardModel {
        PostRunLearningCardModel.make(
            run: run,
            outcome: outcome,
            report: report,
            activePlan: activePlan
        )
    }

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Label("COACH LEARNED", systemImage: "sparkles")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    StatusChip(text: model.source.rawValue, tint: sourceTint)
                }

                if isProcessing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.accentPrimary)
                        Text("Learning from this run now...")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    learningContent
                }
            }
        }
        .task {
            activePlan = await services.activeTrainingPlan()
        }
    }

    private var learningContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PostRunLearningLine(label: "What happened", value: model.happened)
            PostRunLearningLine(label: "What Coach learned", value: model.learned)

            HStack(spacing: 10) {
                Text("PLAN IMPACT")
                    .font(.labelSM)
                    .foregroundStyle(Color.textTertiary)
                StatusChip(text: model.planImpact.label, tint: model.planImpact.tint)
            }

            Button {
                Task { await performAction() }
            } label: {
                Label(actionTitle, systemImage: actionSymbol)
                    .font(.buttonLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(actionEnabled ? Color.black : Color.textSecondary)
                    .background(actionEnabled ? Color.accentPrimary : Color.surfaceCard, in: Capsule())
                    .overlay(Capsule().stroke(actionEnabled ? Color.accentPrimary.opacity(0.5) : Color.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!actionEnabled || isSaving || saveState == .saved)

            if saveState == .failed {
                Text(PostRunSuggestedWorkoutSaveCopy.failureMessage)
                    .font(.caption)
                    .foregroundStyle(Color.accentHeart)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case let .unavailable(message) = model.action {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(model.planImpact == .needsReview ? Color.accentEnergy : Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionTitle: String {
        if isSaving { return "Saving..." }
        if saveState == .saved { return "Saved to Plan" }
        if saveState == .failed { return "Try Saving Again" }
        return model.nextActionTitle
    }

    private var actionEnabled: Bool {
        if case .saveSuggestedWorkout = model.action {
            return true
        }
        return false
    }

    private var actionSymbol: String {
        switch saveState {
        case .idle: actionEnabled ? "calendar.badge.plus" : "info.circle"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var sourceTint: Color {
        switch model.source {
        case .ai: .accentPrimary
        case .fallback: .accentEnergy
        case .report: .accentRecovery
        case .heuristic: .textSecondary
        }
    }

    private func performAction() async {
        guard case let .saveSuggestedWorkout(next, report) = model.action else { return }
        isSaving = true
        saveState = .idle
        let saved = await services.saveSuggestedWorkout(next, from: report)
        isSaving = false
        saveState = saved ? .saved : .failed
        if saved { RunSmartHaptics.success() }
    }

    private enum SaveState {
        case idle
        case saved
        case failed
    }
}

private struct PostRunLearningLine: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.labelSM)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
