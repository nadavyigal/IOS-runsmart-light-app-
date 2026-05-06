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
                    gpsStatus: gpsStatus,
                    gpsDetail: gpsDetail,
                    onPauseResume: primaryRunAction,
                    onFinish: finishRun
                )
            } else {
                PreRunView(
                    metrics: metrics,
                    plannedWorkout: router.plannedWorkout,
                    phase: recorder.phase,
                    gpsStatus: gpsStatus,
                    gpsDetail: gpsDetail,
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
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            Task { metrics = await services.currentRunMetrics() }
        }
    }

    private var liveMetrics: [MetricTile] {
        [
            MetricTile(title: "Distance", value: recorder.distanceLabel, unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: .accentPrimary),
            MetricTile(title: "Pace", value: recorder.currentPaceLabel, unit: "/km", symbol: "timer", tint: .accentEnergy),
            MetricTile(title: "Time", value: recorder.movingLabel, unit: "", symbol: "stopwatch", tint: .textPrimary),
            MetricTile(title: "GPS", value: recorder.horizontalAccuracy.map { "\(Int($0))" } ?? "--", unit: "m", symbol: "location.fill", tint: .accentRecovery)
        ]
    }

    private var gpsStatus: String {
        switch recorder.phase {
        case .idle:
            "GPS ready to request"
        case .requestingPermission:
            "Waiting for location permission"
        case .ready:
            "GPS ready"
        case .recording:
            recorder.routePoints.isEmpty ? "Finding GPS signal" : "Recording GPS"
        case .paused:
            "Paused"
        case .denied:
            "Location permission needed"
        case .failed:
            "GPS error"
        }
    }

    private var gpsDetail: String {
        if let message = recorder.lastErrorMessage {
            return message
        }
        switch recorder.phase {
        case .requestingPermission:
            return "Approve location access and the run will start automatically."
        case .recording:
            if let accuracy = recorder.horizontalAccuracy {
                return "Accuracy \(Int(accuracy))m"
            }
            return "Timer is running. Distance appears after the first GPS points."
        case .paused:
            return "Resume to continue distance tracking or finish to save."
        case .denied:
            return "Enable location access in iOS Settings to record outdoor runs."
        default:
            return "Track distance, moving time, pace, and route with phone GPS."
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
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            finishedRun = run
        } else {
            router.open(.postRunSummary(nil))
        }
    }
}
