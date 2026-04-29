import SwiftUI

struct RunTabView: View {
    @Environment(\.runSmartServices) private var services
    @Environment(\.runRecorder) private var recorder
    @EnvironmentObject private var router: AppRouter

    @State private var metrics: [MetricTile] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(Color.lime)
                    Spacer()
                    Text("Run")
                        .font(.title2.bold())
                    Spacer()
                    RunSmartHeader(showLogo: false)
                        .frame(width: 92)
                }

                GlassCard(glow: Color.lime) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            ProgressRing(value: liveCoachProgress, lineWidth: 5, icon: "waveform")
                                .frame(width: 58, height: 58)
                            VStack(alignment: .leading, spacing: 3) {
                                SectionLabel(title: "Live Coach")
                                Text(statusText)
                                    .font(.caption)
                                    .foregroundStyle(Color.mutedText)
                                if recorder.phase == .recording {
                                    AudioBars()
                                        .frame(width: 150, height: 20)
                                }
                            }
                            Spacer()
                            Button(action: { router.openCoach(context: "Run") }) {
                                Label("Tap to talk", systemImage: "mic.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.lime)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(.white.opacity(0.05))
                                    .overlay(Capsule().stroke(Color.hairline))
                                    .clipShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        coachCue
                            .font(.callout)
                            .padding(12)
                            .background(Color.lime.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lime.opacity(0.28)))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                GlassCard(padding: 0, glow: Color.lime) {
                    ZStack {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                MetricTileView(metric: liveMetrics[0])
                                    .padding(16)
                                Divider().background(Color.hairline)
                                MetricTileView(metric: liveMetrics[1])
                                    .padding(16)
                            }
                            Divider().background(Color.hairline)
                            HStack(spacing: 0) {
                                MetricTileView(metric: liveMetrics[2])
                                    .padding(16)
                                Divider().background(Color.hairline)
                                MetricTileView(metric: liveMetrics[3])
                                    .padding(16)
                            }
                        }
                        if recorder.phase == .recording || recorder.phase == .paused {
                            ProgressRing(value: gpsAccuracyProgress, lineWidth: 7)
                                .frame(width: 88, height: 88)
                                .shadow(color: Color.lime.opacity(0.42), radius: 18)
                        }
                    }
                }

                GlassCard(padding: 8, glow: Color.lime) {
                    ZStack(alignment: .topLeading) {
                        RouteMapView(points: recorder.routePoints, title: recorder.routePoints.isEmpty ? nil : "Live GPS")
                            .frame(height: 124)
                        HStack(spacing: 5) {
                            Text("GPS")
                            Image(systemName: "chart.bar.fill")
                                .foregroundStyle(Color.lime)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.38))
                        .clipShape(Capsule())
                        .padding(8)
                    }
                }

                GlassCard(padding: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.lime)
                            .padding(10)
                            .background(Color.lime.opacity(0.12))
                            .clipShape(Circle())
                        VStack(alignment: .leading) {
                            SectionLabel(title: "Coach Cue")
                            coachCue
                                .font(.caption)
                        }
                        Spacer()
                        runStatusPill
                    }
                }

                HStack(spacing: 10) {
                    SmallStatCard(
                        title: "Elevation",
                        value: recorder.routePoints.isEmpty ? "--" : String(format: "%.0f", elevationGainMeters),
                        unit: "m", symbol: "mountain.2", tint: Color.lime
                    )
                    SmallStatCard(
                        title: "GPS Points",
                        value: "\(recorder.routePoints.count)",
                        unit: "pts", symbol: "location.fill", tint: .cyan
                    )
                    SmallStatCard(
                        title: "Accuracy",
                        value: recorder.horizontalAccuracy.map { String(format: "%.0f", $0) } ?? "--",
                        unit: "m", symbol: "target", tint: Color.lime
                    )
                }

                HStack(spacing: 18) {
                    RunControlButton(title: "Audio", symbol: "speaker.wave.2.fill", tint: .gray) { router.open(.audioCues) }
                    RunControlButton(title: "Lap", symbol: "flag.fill", tint: .gray) { router.open(.lapMarker) }
                    RunControlButton(title: primaryActionTitle, symbol: primaryActionSymbol, tint: Color.lime, prominent: true) { primaryRunAction() }
                    RunControlButton(title: "Finish", symbol: "stop.fill", tint: .red) { finishRun() }
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .task {
            metrics = await services.currentRunMetrics()
        }
    }

    private var liveCoachProgress: Double {
        switch recorder.phase {
        case .recording: return 1.0
        case .paused: return 0.5
        default: return 0.0
        }
    }

    private var gpsAccuracyProgress: Double {
        guard let acc = recorder.horizontalAccuracy, acc > 0 else { return 0 }
        // 5m or better = 1.0, 30m = 0; clamped.
        return max(0, min(1, (30 - acc) / 25))
    }

    private var liveMetrics: [MetricTile] {
        if recorder.phase == .idle || recorder.phase == .ready, !metrics.isEmpty {
            return metrics
        }
        return [
            MetricTile(title: "Distance", value: recorder.distanceLabel, unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
            MetricTile(title: "Pace", value: recorder.currentPaceLabel, unit: "/km", symbol: "timer", tint: Color.lime),
            MetricTile(title: "Time", value: recorder.movingLabel, unit: "", symbol: "stopwatch", tint: .white),
            MetricTile(title: "GPS", value: recorder.horizontalAccuracy.map { "\(Int($0))" } ?? "--", unit: "m", symbol: "location.fill", tint: .cyan)
        ]
    }

    private var statusText: String {
        switch recorder.phase {
        case .idle: "GPS permission needed"
        case .requestingPermission: "Requesting GPS access"
        case .ready: "Ready to record"
        case .recording: "Recording GPS run"
        case .paused: "Run paused"
        case .denied: "Location access denied"
        case .failed: "GPS error"
        }
    }

    private var coachCue: Text {
        switch recorder.phase {
        case .recording:
            Text("Ease your shoulders. Pace: \(recorder.currentPaceLabel)/km.")
        case .paused:
            Text("Paused. Resume when ready or finish to save.")
        case .denied:
            Text("Location permission required for GPS recording.")
        default:
            Text("Start a GPS run to record distance, route, and pace.")
        }
    }

    private var runStatusPill: some View {
        let label: String
        let color: Color
        switch recorder.phase {
        case .recording:
            label = "Recording"
            color = Color.lime
        case .paused:
            label = "Paused"
            color = .orange
        default:
            label = "Ready"
            color = Color.mutedText
        }
        return Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private var elevationGainMeters: Double {
        let altitudes = recorder.routePoints.compactMap { $0.altitude }
        guard altitudes.count >= 2 else { return 0 }
        var gain: Double = 0
        for i in 1..<altitudes.count {
            let diff = altitudes[i] - altitudes[i-1]
            if diff > 0 { gain += diff }
        }
        return gain
    }

    private var primaryActionTitle: String {
        switch recorder.phase {
        case .recording: "Pause"
        case .paused: "Resume"
        default: "Start"
        }
    }

    private var primaryActionSymbol: String {
        switch recorder.phase {
        case .recording: "pause.fill"
        case .paused: "play.fill"
        default: "location.fill"
        }
    }

    private func primaryRunAction() {
        switch recorder.phase {
        case .recording:
            recorder.pause()
        case .paused:
            recorder.resume()
        default:
            recorder.start()
        }
    }

    private func finishRun() {
        let run = recorder.finish()
        if let run {
            Task { await services.saveToHealth(run) }
        }
        router.open(.postRunSummary(run))
    }
}

struct AudioBars: View {
    private let heights: [CGFloat] = [6, 12, 9, 18, 8, 14, 20, 11, 7, 15, 9, 13, 6]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(Color.lime)
                    .frame(width: 3, height: height)
            }
        }
    }
}

struct RunControlButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 20 : 18, weight: .bold))
                    .foregroundStyle(prominent ? Color.black : tint)
                    .frame(width: prominent ? 62 : 54, height: prominent ? 62 : 54)
                    .background(prominent ? tint : Color.white.opacity(0.1))
                    .clipShape(Circle())
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .buttonStyle(.plain)
    }
}
