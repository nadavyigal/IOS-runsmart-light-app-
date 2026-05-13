import SwiftUI

struct PreRunView: View {
    var metrics: [MetricTile]
    var plannedWorkout: WorkoutSummary?
    var phase: RunRecordingPhase
    var gpsStatus: String
    var gpsDetail: String
    var onStart: () -> Void
    var onRoute: () -> Void
    var onAudio: () -> Void

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                RunSmartTopBar(title: "Run")

                GPSStatusPill(status: gpsStatus, detail: gpsDetail, phase: phase)

                RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(title: "Ready")
                            Text(plannedWorkout?.title ?? "Free Run")
                                .font(.displayMD)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                            Text(workoutDetail)
                                .font(.metricSM)
                                .foregroundStyle(Color.accentPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }

                        HStack(alignment: .center, spacing: 16) {
                            StartRunButton(title: startTitle, isWaiting: phase == .requestingPermission || phase == .acquiringLocation, action: onStart)
                            Spacer()
                            VStack(alignment: .leading, spacing: 9) {
                                Label("GPS route", systemImage: "location.fill")
                                Label("Pace", systemImage: "timer")
                                Label("Moving time", systemImage: "stopwatch")
                            }
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 132, alignment: .leading)
                        }

                        HStack(spacing: 10) {
                            RunOptionButton(title: "Route", symbol: "map.fill", tint: .accentRecovery, action: onRoute)
                            RunOptionButton(title: "Audio", symbol: "speaker.wave.2.fill", tint: .accentPrimary, action: onAudio)
                        }
                    }
                }

                Button(action: onRoute) {
                    RunSmartRoutePreview(title: "GPS preview", showGPS: true, height: max(118, min(170, proxy.size.height * 0.18)))
                }
                .buttonStyle(.plain)

                if let lastRun = metrics.first {
                    RunSmartPanel(cornerRadius: 18, padding: 12) {
                        HStack(spacing: 12) {
                            SectionLabel(title: "Last Run")
                            Spacer()
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(lastRun.value)
                                    .font(.metricSM)
                                Text(lastRun.unit)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(lastRun.tint)
                            }
                        }
                    }
                }
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 128)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.black.opacity(0.52).ignoresSafeArea())
    }

    private var workoutDetail: String {
        guard let workout = plannedWorkout else { return "GPS tracking - pace - route" }
        var parts = [workout.distance]
        if let pace = StructuredWorkoutFactory.derivedPaceLabel(workout: workout) {
            parts.append(pace)
        }
        if !workout.detail.isEmpty {
            parts.append(workout.detail)
        }
        return parts.joined(separator: " - ")
    }

    private var startTitle: String {
        switch phase {
        case .requestingPermission:
            return "Starting..."
        case .acquiringLocation:
            return "Finding GPS"
        case .denied:
            return "Allow GPS"
        default:
            return "Start Run"
        }
    }
}

private struct RunOptionButton: View {
    var title: String
    var symbol: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RunSmartPanel(cornerRadius: 16, padding: 12) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.bodyMD.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct StartRunButton: View {
    var title: String
    var isWaiting: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: isWaiting ? "location.fill" : "play.fill")
                    .font(.system(size: 34, weight: .black))
                Text(title)
                    .font(.buttonLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(Color.black)
            .frame(width: 132, height: 132)
            .background(Color.accentPrimary, in: Circle())
            .shadow(color: Color.accentPrimary.opacity(0.46), radius: 24)
            .runSmartPulse(scale: isWaiting ? 1.01 : 1.035)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(isWaiting)
    }
}

struct GPSStatusPill: View {
    var status: String
    var detail: String
    var phase: RunRecordingPhase

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(status)
                    .font(.bodyMD.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(Color.surfaceElevated.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
    }

    private var symbol: String {
        switch phase {
        case .recording:
            return "location.fill"
        case .requestingPermission, .acquiringLocation:
            return "location.circle"
        case .denied, .failed:
            return "location.slash.fill"
        default:
            return "location"
        }
    }

    private var tint: Color {
        switch phase {
        case .denied, .failed:
            return .accentHeart
        case .paused, .acquiringLocation:
            return .accentEnergy
        default:
            return .accentPrimary
        }
    }
}
