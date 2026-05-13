import SwiftUI

struct RunTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var recorder: RunRecorder

    @State private var metrics: [MetricTile] = []
    @State private var finishedRun: RecordedRun?
    @State private var postActivityOutcome: PostActivityOutcome?
    @State private var isProcessingFinishedRun = false
    @State private var isConfirmingDiscard = false

    var body: some View {
        Group {
            if let finishedRun {
                PostRunSummaryView(
                    run: postActivityOutcome?.canonicalRun ?? finishedRun,
                    outcome: postActivityOutcome,
                    isProcessing: isProcessingFinishedRun,
                    onSave: saveFinishedRun,
                    onDelete: deleteFinishedRun
                )
            } else if recorder.phase == .recording || recorder.phase == .paused {
                LiveRunView(
                    metrics: liveMetrics,
                    routePoints: recorder.displayRoutePoints,
                    phase: recorder.phase,
                    gpsStatus: gpsStatus,
                    gpsDetail: gpsDetail,
                    elapsedSeconds: recorder.movingSeconds,
                    onPauseResume: primaryRunAction,
                    onFinish: finishRun,
                    onDiscard: { isConfirmingDiscard = true }
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
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Workout", role: .destructive) {
                discardRun()
            }
            Button("Keep Workout", role: .cancel) {}
        } message: {
            Text("This removes the current timer, distance, and route.")
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
        case .acquiringLocation:
            "Finding GPS"
        case .ready:
            "GPS ready"
        case .recording:
            "Recording now"
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
        case .acquiringLocation:
            if let accuracy = recorder.horizontalAccuracy {
                return "Current accuracy \(Int(accuracy))m - move outdoors for a stronger lock."
            }
            return "Stand near open sky while RunSmart gets a clean first point."
        case .recording:
            if let accuracy = recorder.horizontalAccuracy {
                return "Timer running - GPS accuracy \(Int(accuracy))m"
            }
            return "Timer running - finding the first GPS point."
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
            RunSmartHaptics.light()
            recorder.pause()
        case .paused:
            RunSmartHaptics.light()
            recorder.resume()
        default:
            recorder.start()
        }
    }

    private func finishRun() {
        RunSmartHaptics.medium()
        let run = recorder.finish()
        if let run {
            Task { await services.saveToHealth(run) }
            postActivityOutcome = nil
            isProcessingFinishedRun = true
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            finishedRun = run
            Task {
                let outcome = await services.processCompletedActivity(run)
                await MainActor.run {
                    postActivityOutcome = outcome
                    isProcessingFinishedRun = false
                }
            }
        } else {
            router.open(.postRunSummary(nil))
        }
    }

    private func discardRun() {
        RunSmartHaptics.medium()
        recorder.discard()
        finishedRun = nil
        postActivityOutcome = nil
        isProcessingFinishedRun = false
    }

    private func saveFinishedRun() {
        finishedRun = nil
        postActivityOutcome = nil
        isProcessingFinishedRun = false
        Task { metrics = await services.currentRunMetrics() }
    }

    private func deleteFinishedRun() {
        guard let run = finishedRun else {
            finishedRun = nil
            return
        }
        Task {
            _ = await services.removeRun(run)
            await MainActor.run {
                finishedRun = nil
                postActivityOutcome = nil
                isProcessingFinishedRun = false
                NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            }
        }
    }
}
