import SwiftUI

struct RunTabView<Services: RunLogging>: View {
    let services: Services
    var openCoach: () -> Void
    var openSecondary: (String) -> Void

    @State private var metrics: [MetricTile] = [
        MetricTile(title: "Distance", value: "5.24", unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: Color.lime),
        MetricTile(title: "Pace", value: "5:08", unit: "/km", symbol: "timer", tint: Color.lime),
        MetricTile(title: "Time", value: "26:54", unit: "", symbol: "stopwatch", tint: .white),
        MetricTile(title: "Heart Rate", value: "154", unit: "bpm", symbol: "heart", tint: .red)
    ]

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
                            ProgressRing(value: 0.78, lineWidth: 5, icon: "waveform")
                                .frame(width: 58, height: 58)
                            VStack(alignment: .leading, spacing: 3) {
                                SectionLabel(title: "Live Coach")
                                Text("Coach is listening")
                                    .font(.caption)
                                    .foregroundStyle(Color.mutedText)
                                AudioBars()
                                    .frame(width: 150, height: 20)
                            }
                            Spacer()
                            Button(action: openCoach) {
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

                        Text("Ease your shoulders.\nHold \(Text("5:10").foregroundStyle(Color.lime).bold()) pace for the next minute.")
                            .font(.callout)
                            .padding(12)
                            .background(Color.lime.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.lime.opacity(0.28)))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: .center)

                        CoachBubble(message: CoachMessage(text: "You're strong today, Alex. Great rhythm and even effort. Keep it steady.", time: "Just now", isUser: false))
                    }
                }

                GlassCard(padding: 0, glow: Color.lime) {
                    ZStack {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                MetricTileView(metric: metrics[0])
                                    .padding(16)
                                Divider().background(Color.hairline)
                                MetricTileView(metric: metrics[1])
                                    .padding(16)
                            }
                            Divider().background(Color.hairline)
                            HStack(spacing: 0) {
                                MetricTileView(metric: metrics[2])
                                    .padding(16)
                                Divider().background(Color.hairline)
                                MetricTileView(metric: metrics[3])
                                    .padding(16)
                            }
                        }
                        ProgressRing(value: 0.74, lineWidth: 7)
                            .frame(width: 88, height: 88)
                            .padding(14)
                            .background(Color.ink.opacity(0.82))
                            .clipShape(Circle())
                            .shadow(color: Color.lime.opacity(0.42), radius: 18)
                    }
                }

                GlassCard(padding: 8, glow: Color.lime) {
                    ZStack(alignment: .topLeading) {
                        MiniRouteView()
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
                            Text("Hold steady. Relax your shoulders.")
                                .font(.caption)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("CADENCE")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.mutedText)
                            Text("172 spm")
                                .font(.headline)
                            AudioBars()
                                .frame(width: 86, height: 14)
                        }
                    }
                }

                HStack(spacing: 10) {
                    SmallStatCard(title: "Elevation", value: "28", unit: "m", symbol: "mountain.2", tint: Color.lime)
                    SmallStatCard(title: "Zone", value: "4", unit: "Threshold", symbol: "heart", tint: .red)
                    SmallStatCard(title: "Pace Trend", value: "-0:03", unit: "vs last km", symbol: "speedometer", tint: Color.lime)
                }

                HStack(spacing: 18) {
                    RunControlButton(title: "Audio", symbol: "speaker.wave.2.fill", tint: .gray) { openSecondary("Audio Cues") }
                    RunControlButton(title: "Lap", symbol: "flag.fill", tint: .gray) { openSecondary("Lap Marker") }
                    RunControlButton(title: "Pause", symbol: "pause.fill", tint: Color.lime, prominent: true) {}
                    RunControlButton(title: "Finish", symbol: "stop.fill", tint: .red) { openSecondary("Post-Run Summary") }
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
