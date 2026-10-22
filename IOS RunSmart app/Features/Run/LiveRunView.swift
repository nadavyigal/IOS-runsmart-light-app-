import SwiftUI

struct LiveRunView: View {
    var metrics: [MetricTile]
    var routePoints: [RunRoutePoint]
    /// Completed full kilometers, cached by `RunRecorder` so the view never walks the whole route.
    var completedKmSplits: [KilometerSplit]
    var phase: RunRecordingPhase
    var isAutoPaused: Bool = false
    var gpsStatus: String
    var gpsDetail: String
    var elapsedSeconds: TimeInterval
    var onPauseResume: () -> Void
    var onFinish: () -> Void
    // Kept for call-site compatibility; discard belongs only in the end sheet.
    var onDiscard: () -> Void
    @ObservedObject private var audioCues = LocalRunCueService.shared
    @State private var page = LivePage.stats
    @State private var showsKmSplits = false

    private enum LivePage: String, CaseIterable {
        case stats = "Stats"
        case map = "Map"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Run")
                    .font(.headingLG)
                Spacer()
                Label("GPS", systemImage: "location.fill")
                    .font(.labelSM)
                    .foregroundStyle(Color.accentRecovery)
                    .accessibilityLabel("\(gpsStatus). \(gpsDetail)")
            }
            .padding(.horizontal, 20)

            Picker("Run page", selection: $page) {
                ForEach(LivePage.allCases, id: \.self) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)

            TabView(selection: $page) {
                statsPage.tag(LivePage.stats)
                LiveRunMapPage(points: routePoints, metrics: metrics, isPaused: phase == .paused, isAutoPaused: isAutoPaused)
                    .tag(LivePage.map)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(alignment: .bottom, spacing: 24) {
                LiveControlButton(
                    title: audioCues.isEnabled ? "Audio" : "Muted",
                    symbol: audioCues.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    tint: audioCues.isEnabled ? .accentPrimary : .textSecondary,
                    action: { audioCues.setEnabled(!audioCues.isEnabled) }
                )
                LiveControlButton(
                    title: phase == .paused ? "Resume" : "Pause",
                    symbol: phase == .paused ? "play.fill" : "pause.fill",
                    tint: .accentPrimary,
                    prominent: true,
                    action: onPauseResume
                )
                HoldToFinishButton(action: onFinish)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .foregroundStyle(Color.textPrimary)
        .background(Color.black.opacity(0.52).ignoresSafeArea())
    }

    private var statsPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                LiveRunStateBanner(phase: phase, elapsedSeconds: elapsedSeconds, isAutoPaused: isAutoPaused)

                if let distance = metrics.first {
                    RunSmartPanel(cornerRadius: 22, padding: 20, accent: .accentPrimary) {
                        LiveMetricCard(metric: distance, isPrimary: true)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(metrics.dropFirst()) { metric in
                        RunSmartPanel(cornerRadius: 18, padding: 14) {
                            LiveMetricCard(metric: metric, isPrimary: false)
                        }
                    }
                }

                if !completedKmSplits.isEmpty {
                    LiveKmSplitsPanel(splits: completedKmSplits, isExpanded: $showsKmSplits)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }
}

/// A tap has no finish action. The long press and VoiceOver action both open
/// the same end sheet; neither saves or discards the run directly.
private struct HoldToFinishButton: View {
    var action: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(Color.surfaceCard)
                Circle().stroke(Color.accentHeart.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentHeart, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "stop.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.accentHeart)
            }
            .frame(width: 72, height: 72)
            Text("Hold to\nfinish")
                .font(.bodyMD.weight(.bold))
                .foregroundStyle(Color.accentHeart)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)
                .frame(width: 84)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 24) {
            guard scenePhase == .active else { return }
            resetHold()
            RunSmartHaptics.medium()
            action()
        } onPressingChanged: { pressing in
            if pressing {
                withAnimation(reduceMotion ? nil : .linear(duration: 1.5)) {
                    progress = 1
                }
            } else {
                resetHold()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Finish run")
        .accessibilityHint("Opens Save, Resume, and Discard options.")
        .accessibilityAction {
            RunSmartHaptics.medium()
            action()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { resetHold() }
        }
        .onDisappear { resetHold() }
    }

    private func resetHold() {
        progress = 0
    }
}

/// Collapsed-by-default live split list — appears only after the first full km (WP-38 S12).
private struct LiveKmSplitsPanel: View {
    var splits: [KilometerSplit]
    @Binding var isExpanded: Bool

    var body: some View {
        RunSmartPanel(cornerRadius: 16, padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Label("KM SPLITS", systemImage: "speedometer")
                            .font(.labelSM)
                            .foregroundStyle(Color.accentPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let latest = splits.last {
                            Text(RunRecorder.paceLabel(secondsPerKm: latest.paceSecondsPerKm))
                                .font(.metricSM)
                                .monospacedDigit()
                                .foregroundStyle(Color.textPrimary)
                            Text("km \(latest.km)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Kilometer splits")
                .accessibilityValue(latestSplitAccessibilityValue)
                .accessibilityHint(isExpanded ? "Collapse split list" : "Expand split list")

                if isExpanded {
                    ForEach(splits) { split in
                        HStack {
                            Text("\(split.km)")
                                .font(.bodyMD)
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 24, alignment: .leading)
                            Text(RunRecorder.paceLabel(secondsPerKm: split.paceSecondsPerKm))
                                .font(.metricSM)
                                .monospacedDigit()
                            Spacer()
                            Text("km \(split.km)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.border.opacity(0.72))
                                .frame(height: 1)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: splits.count)
    }

    private var latestSplitAccessibilityValue: String {
        guard let latest = splits.last else { return "No completed kilometers yet" }
        let pace = RunRecorder.paceLabel(secondsPerKm: latest.paceSecondsPerKm)
        return "\(splits.count) splits. Latest kilometer \(latest.km), pace \(pace) per kilometer."
    }
}

private struct LiveMetricCard: View {
    var metric: MetricTile
    var isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(metric.title.uppercased(), systemImage: metric.symbol)
                .font(.labelSM)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(metric.value)
                .font(isPrimary ? .displayXL : .metric)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(metric.unit)
                .font(.labelSM)
                .foregroundStyle(metric.tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title), \(metric.value) \(metric.unit)")
    }
}

private struct LiveRunStateBanner: View {
    var phase: RunRecordingPhase
    var elapsedSeconds: TimeInterval
    var isAutoPaused = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 42, height: 42)
                Circle()
                    .fill(tint)
                    .frame(width: 13, height: 13)
                    .runSmartPulse(scale: phase == .recording ? 1.35 : 1.0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer()

            Text(RunRecorder.timeLabel(elapsedSeconds))
                .font(.metricSM)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .frame(height: 66)
        .background(Color.surfaceElevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.42), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle). Moving time \(RunRecorder.timeLabel(elapsedSeconds)).")
    }

    private var title: String {
        phase == .paused ? (isAutoPaused ? "Auto-paused" : "Paused") : "Recording"
    }

    private var subtitle: String {
        phase == .paused ? (isAutoPaused ? "Move to resume recording." : "Tap Resume when you are ready.") : "Time is running now."
    }

    private var tint: Color {
        phase == .paused ? .accentEnergy : .accentPrimary
    }
}

private struct LiveControlButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 30 : 24, weight: .bold))
                    .foregroundStyle(prominent ? Color.black : tint)
                    .frame(width: prominent ? 88 : 72, height: prominent ? 88 : 72)
                    .background(prominent ? tint : Color.surfaceCard)
                    .clipShape(Circle())
                Text(title)
                    .font(.bodyMD.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        switch title {
        case "Pause": return "Pauses distance tracking. Moving time stops while paused."
        case "Resume": return "Resumes distance tracking."
        case "Finish": return "Opens finish and save confirmation."
        case "Discard": return "Opens discard workout confirmation."
        case "Audio", "Muted": return "Toggles offline run announcements."
        default: return ""
        }
    }
}
