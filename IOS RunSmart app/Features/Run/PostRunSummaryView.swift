import SwiftUI

struct PostRunSummaryView: View {
    var run: RecordedRun?
    var onSave: () -> Void
    var onDelete: () -> Void

    @State private var rpe = 6
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HeroCard(accent: .accentSuccess) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            SectionLabel(title: "Run Saved")
                            Spacer()
                            StatusChip(text: run == nil ? "Draft" : "GPS", tint: .accentPrimary)
                        }

                        Text(distanceLabel)
                            .font(.displayXL)
                            .monospacedDigit()
                            .displayTightTracking()

                        HStack(spacing: 8) {
                            PostRunStatPill(title: "Time", value: timeLabel, tint: .accentPrimary)
                            PostRunStatPill(title: "Pace", value: paceLabel, tint: .accentEnergy)
                            PostRunStatPill(title: "Route", value: routeLabel, tint: .accentRecovery)
                        }

                        RouteMapView(points: run?.routePoints ?? [], title: "Completed route")
                            .frame(height: 142)
                    }
                }

                RPESelector(value: $rpe)

                CoachAnalysisCard(run: run, rpe: rpe)
                SplitPreviewCard(splits: splitRows)
                RecoveryPlanCard()

                HStack(spacing: 10) {
                    Button(action: onSave) {
                        Label("Keep Activity", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(NeonButtonStyle())

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.buttonLabel)
                            .foregroundStyle(Color.accentHeart)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.accentHeart.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(Color.accentHeart.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Color.black.opacity(0.52).ignoresSafeArea())
        .confirmationDialog("Delete this activity?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Activity", role: .destructive, action: onDelete)
            Button("Keep Activity", role: .cancel) {}
        } message: {
            Text("This removes the run from RunSmart. It will not delete anything from Garmin.")
        }
    }

    private var distanceLabel: String {
        guard let run else { return "-- km" }
        return String(format: "%.2f km", run.distanceMeters / 1_000)
    }

    private var timeLabel: String {
        guard let run else { return "--" }
        return RunRecorder.timeLabel(run.movingTimeSeconds)
    }

    private var paceLabel: String {
        guard let run else { return "--" }
        return RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm)
    }

    private var routeLabel: String {
        guard let run else { return "--" }
        return run.routePoints.isEmpty ? "No map" : "\(run.routePoints.count) pts"
    }

    private var splitRows: [SplitRow] {
        guard let run, run.distanceMeters >= 500 else { return [] }
        let fullKm = max(1, Int(run.distanceMeters / 1_000))
        return (1...min(fullKm, 8)).map { km in
            let drift = Double((km % 3) - 1) * 4
            let pace = max(1, run.averagePaceSecondsPerKm + drift)
            return SplitRow(km: km, pace: RunRecorder.paceLabel(secondsPerKm: pace))
        }
    }
}

private struct PostRunStatPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.labelSM)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.metricXS)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color.surfaceCard.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

private struct CoachAnalysisCard: View {
    var run: RecordedRun?
    var rpe: Int

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("COACH ANALYSIS", systemImage: "sparkles")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    StatusChip(text: effortLabel, tint: effortTint)
                }

                Text(headline)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(3)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    CoachInsightTile(title: "Training Benefit", text: benefitText, symbol: "sparkles", tint: .accentPrimary)
                    CoachInsightTile(title: "Plan Fit", text: "This GPS run updates your recent load and helps the next plan decision.", symbol: "target", tint: .accentRecovery)
                    CoachInsightTile(title: "Recovery", text: recoveryText, symbol: "heart", tint: .accentRecovery)
                    CoachInsightTile(title: "Pacing", text: paceText, symbol: "waveform.path.ecg", tint: .accentEnergy)
                }

                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color.accentPrimary)
                        .frame(width: 3)
                    Text(loadText)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(minHeight: 46)

                Text("AI - GPS - RunSmart")
                    .font(.labelSM)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var effortLabel: String {
        switch rpe {
        case 1...4: return "Easy"
        case 5...7: return "Steady"
        default: return "Hard"
        }
    }

    private var effortTint: Color {
        switch rpe {
        case 1...4: return .accentPrimary
        case 5...7: return .accentEnergy
        default: return .accentHeart
        }
    }

    private var headline: String {
        guard let run else { return "No run data was available for analysis." }
        let km = run.distanceMeters / 1_000
        return String(format: "You completed %.2f km at %@ /km average pace.", km, RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm))
    }

    private var benefitText: String {
        rpe <= 6 ? "This supports aerobic consistency without adding unnecessary strain." : "This was a stronger effort. Keep the next run controlled."
    }

    private var recoveryText: String {
        rpe >= 7 ? "Hydrate, refuel, and keep the next 24h lighter." : "Rehydrate and refuel. Easy movement later is enough."
    }

    private var paceText: String {
        guard let run, run.averagePaceSecondsPerKm > 0 else { return "Pace trend appears after more GPS distance." }
        return "Average pace: \(RunRecorder.paceLabel(secondsPerKm: run.averagePaceSecondsPerKm)) /km."
    }

    private var loadText: String {
        guard let run else { return "Save or delete this activity before leaving the summary." }
        return String(format: "%.1f km at %@ effort contributes to your weekly load.", run.distanceMeters / 1_000, effortLabel.lowercased())
    }
}

private struct CoachInsightTile: View {
    var title: String
    var text: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.labelSM)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(Color.surfaceCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

private struct SplitPreviewCard: View {
    var splits: [SplitRow]

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("KM SPLITS", systemImage: "speedometer")
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                    Spacer()
                    Text("\(splits.count) splits")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(14)

                if splits.isEmpty {
                    Text("Splits appear after at least 500m of GPS distance.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                } else {
                    ForEach(splits) { split in
                        HStack {
                            Text("\(split.km)")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 28, alignment: .leading)
                            Text(split.pace)
                                .font(.metricSM)
                                .monospacedDigit()
                            Spacer()
                            Text("km \(split.km)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
    }
}

private struct RecoveryPlanCard: View {
    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: .accentRecovery) {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 42, height: 42)
                    .background(Color.accentPrimary.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(title: "Recovery Plan")
                    Text("Now: rehydrate and refuel with a light snack.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
        }
    }
}

private struct SplitRow: Identifiable {
    var id: Int { km }
    var km: Int
    var pace: String
}
