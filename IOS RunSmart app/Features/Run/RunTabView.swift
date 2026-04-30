import SwiftUI

struct RunTabView: View {
    @Environment(\.runSmartServices) private var services
    @Environment(\.runRecorder) private var recorder
    @EnvironmentObject private var router: AppRouter

    @State private var metrics: [MetricTile] = []
    @State private var finishedRun: RecordedRun?

    var body: some View {
        Group {
            if let finishedRun {
                PostRunSummaryView(run: finishedRun) {
                    self.finishedRun = nil
                }
            } else if recorder.phase == .recording || recorder.phase == .paused {
                LiveRunView(
                    metrics: liveMetrics,
                    routePoints: recorder.routePoints,
                    phase: recorder.phase,
                    coachCue: coachCue,
                    onPauseResume: primaryRunAction,
                    onLap: { router.open(.lapMarker) },
                    onLock: { RunSmartHaptics.light() },
                    onFinish: finishRun
                )
            } else {
                PreRunView(
                    metrics: metrics,
                    onStart: {
                        RunSmartHaptics.medium()
                        recorder.start()
                    },
                    onRoute: { router.open(.routeCreator) },
                    onAudio: { router.open(.audioCues) }
                )
            }
        }
        .task {
            metrics = await services.currentRunMetrics()
        }
    }

    private var liveMetrics: [MetricTile] {
        [
            MetricTile(title: "Distance", value: recorder.distanceLabel, unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: .accentPrimary),
            MetricTile(title: "Pace", value: recorder.currentPaceLabel, unit: "/km", symbol: "timer", tint: .accentEnergy),
            MetricTile(title: "Time", value: recorder.movingLabel, unit: "", symbol: "stopwatch", tint: .textPrimary),
            MetricTile(title: "Heart Rate", value: recorder.horizontalAccuracy.map { "\(Int($0))" } ?? "--", unit: "gps", symbol: "location.fill", tint: .accentRecovery)
        ]
    }

    private var coachCue: String {
        switch recorder.phase {
        case .recording:
            "Ease your shoulders. Pace: \(recorder.currentPaceLabel)/km."
        case .paused:
            "Paused. Resume when ready or finish to save."
        case .denied:
            "Location permission is required for GPS recording."
        default:
            "Start a GPS run to record distance, route, and pace."
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
            finishedRun = run
        } else {
            router.open(.postRunSummary(nil))
        }
    }
}
