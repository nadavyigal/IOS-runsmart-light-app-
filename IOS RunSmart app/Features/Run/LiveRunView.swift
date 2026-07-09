import SwiftUI

struct LiveRunView: View {
    var metrics: [MetricTile]
    var routePoints: [RunRoutePoint]
    /// Full GPS route for split math — must match post-run `run.routePoints` (WP-38 S12).
    var splitRoutePoints: [RunRoutePoint]
    var phase: RunRecordingPhase
    var gpsStatus: String
    var gpsDetail: String
    var elapsedSeconds: TimeInterval
    var onPauseResume: () -> Void
    var onFinish: () -> Void
    var onDiscard: () -> Void
    @ObservedObject private var voiceCoach = VoiceCoachService.shared
    @State private var showsKmSplits = false

    var body: some View {
        GeometryReader { proxy in
            // WP-37 S4 follow-up: on shorter screens (e.g. iPhone SE 3rd gen,
            // 375x667pt) the fixed-height panels above leave less room than the
            // button row + its labels need, and a bare VStack has no scroll
            // fallback — labels were silently clipped past the screen edge with
            // no way to reveal them. minHeight (not maxHeight) lets the Spacer
            // below still pin the buttons to the bottom on tall screens exactly
            // as before, while short screens scroll instead of clipping.
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    RunSmartTopBar(title: "Run")

                    GPSStatusPill(status: gpsStatus, detail: gpsDetail, phase: phase)
                    LiveRunStateBanner(phase: phase, elapsedSeconds: elapsedSeconds)

                    RunSmartPanel(cornerRadius: 22, padding: 0, accent: .accentPrimary) {
                        if let primaryMetric = metrics.first {
                            VStack(spacing: 0) {
                                LiveMetricCard(metric: primaryMetric, isPrimary: true)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 16)
                                    .padding(.bottom, 12)

                                HStack(spacing: 0) {
                                    ForEach(Array(metrics.dropFirst().enumerated()), id: \.element.id) { index, metric in
                                        LiveMetricCard(metric: metric, isPrimary: false)
                                            .padding(14)
                                            .frame(maxWidth: .infinity, minHeight: 94)
                                            .overlay(alignment: .leading) {
                                                Rectangle()
                                                    .fill(Color.border.opacity(0.72))
                                                    .frame(width: index == 0 ? 0 : 1)
                                            }
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: max(174, min(218, proxy.size.height * 0.25)))

                    if routePoints.isEmpty {
                        RunSmartRoutePreview(title: "GPS", showGPS: true, height: max(82, min(124, proxy.size.height * 0.14)))
                    } else {
                        RunSmartPanel(cornerRadius: 20, padding: 8) {
                            RouteMapView(points: routePoints, title: "GPS", isLive: true)
                                .frame(height: max(78, min(116, proxy.size.height * 0.13)))
                        }
                    }

                    if !completedKmSplits.isEmpty {
                        LiveKmSplitsPanel(splits: completedKmSplits, isExpanded: $showsKmSplits)
                    }

                    Spacer(minLength: 0)

                    // WP-37 S3: never show 4 buttons. Coach is irrelevant while paused
                    // (VoiceCoachService is itself paused, so there's nothing to mute),
                    // so the paused state swaps it for Discard instead of appending a
                    // fourth button — keeps the row at 3 buttons on every screen width.
                    HStack(alignment: .bottom, spacing: 18) {
                        LiveControlButton(title: phase == .paused ? "Resume" : "Pause", symbol: phase == .paused ? "play.fill" : "pause.fill", tint: .accentPrimary, prominent: true, action: onPauseResume)
                        LiveControlButton(title: "Finish", symbol: "stop.fill", tint: .accentHeart, prominent: false, action: onFinish)
                        if phase == .paused {
                            LiveControlButton(title: "Discard", symbol: "trash.fill", tint: .accentHeart, prominent: false, action: onDiscard)
                        } else {
                            LiveControlButton(
                                title: voiceCoach.isEnabled ? "Coach" : "Muted",
                                symbol: voiceCoach.isEnabled ? "waveform" : "waveform.slash",
                                tint: voiceCoach.isEnabled ? .accentPrimary : .textSecondary,
                                prominent: false,
                                action: { voiceCoach.setEnabled(!voiceCoach.isEnabled) }
                            )
                        }
                    }
                    .padding(.bottom, 28)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 0)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .background(Color.black.opacity(0.52).ignoresSafeArea())
    }

    private var completedKmSplits: [KilometerSplit] {
        RunRecorder.kilometerSplits(from: splitRoutePoints)
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
    }
}

private struct LiveRunStateBanner: View {
    var phase: RunRecordingPhase
    var elapsedSeconds: TimeInterval

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
    }

    private var title: String {
        phase == .paused ? "Paused" : "Recording"
    }

    private var subtitle: String {
        phase == .paused ? "Distance tracking is stopped." : "Time is running now."
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
                    .font(.system(size: prominent ? 34 : 24, weight: .bold))
                    .foregroundStyle(prominent ? Color.black : tint)
                    .frame(width: prominent ? 112 : 78, height: prominent ? 112 : 78)
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
    }
}
