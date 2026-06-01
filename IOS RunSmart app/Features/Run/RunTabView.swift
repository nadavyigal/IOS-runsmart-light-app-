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
                    selectedRoute: router.plannedRoute,
                    phase: recorder.phase,
                    gpsStatus: gpsStatus,
                    gpsDetail: gpsDetail,
                    onStart: startRun,
                    onRoute: openRouteCreator,
                    onAudio: openAudioCues
                )
            }
        }
        .task {
            await reloadMetrics()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            refreshMetrics()
        }
        .onChange(of: recorder.phase) { oldPhase, newPhase in
            switch newPhase {
            case .recording where oldPhase == .paused:
                VoiceCoachService.shared.resumeSession()
            case .recording:
                VoiceCoachService.shared.startSession()
            case .paused:
                VoiceCoachService.shared.pauseSession()
            case .idle, .ready, .denied, .failed:
                VoiceCoachService.shared.stopSession()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceCoachCueTimerFired)) { _ in
            guard recorder.phase == .recording else { return }
            let context = VoiceCueContext(
                elapsedMinutes: recorder.movingSeconds / 60.0,
                distanceKm: recorder.distanceMeters / 1000.0,
                currentPaceMinPerKm: recorder.distanceMeters > 0
                    ? (recorder.movingSeconds / (recorder.distanceMeters / 1000.0)) / 60.0
                    : 0.0,
                targetPaceMinPerKm: nil,
                workoutGoal: router.plannedWorkout?.title,
                heartRateBPM: nil
            )
            VoiceCoachService.shared.deliverCue(context: context)
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
        func accuracyMessage(_ accuracy: Double) -> String {
            let meters = Int(accuracy)
            if accuracy > 50 {
                return "Weak GPS at \(meters)m. RunSmart keeps recording, but route matching may be less precise."
            }
            if accuracy > 25 {
                return "GPS accuracy \(meters)m. Open sky helps route matching and pace settle."
            }
            return "GPS accuracy \(meters)m. Route recording looks solid."
        }

        switch recorder.phase {
        case .requestingPermission:
            return "Approve location access and the run will start automatically."
        case .acquiringLocation:
            if let accuracy = recorder.horizontalAccuracy {
                return accuracyMessage(accuracy)
            }
            return "Stand near open sky while RunSmart gets a clean first point."
        case .recording:
            if let accuracy = recorder.horizontalAccuracy {
                return "Timer running. \(accuracyMessage(accuracy))"
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

    private func startRun() {
        RunSmartHaptics.medium()
        let source = router.plannedWorkout != nil ? "planned" : "free"
        Analytics.trackRunStarted(source: source)
        recorder.start()
    }

    private func openRouteCreator() {
        router.open(.routeCreator)
    }

    private func openAudioCues() {
        router.open(.audioCues)
    }

    private func reloadMetrics() async {
        metrics = await services.currentRunMetrics()
    }

    private func refreshMetrics() {
        Task { await reloadMetrics() }
    }

    private func finishRun() {
        RunSmartHaptics.medium()
        VoiceCoachService.shared.stopSession()
        let run = recorder.finish()
        if let run {
            router.dismissPostRunSummaryIfNeeded()
            Task { await services.saveToHealth(run) }
            postActivityOutcome = nil
            isProcessingFinishedRun = true
            NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            finishedRun = run
            let isFirst = !UserDefaults.standard.bool(forKey: "analytics.hasCompletedRun")
            UserDefaults.standard.set(true, forKey: "analytics.hasCompletedRun")
            Analytics.trackRunCompleted(
                distanceKm: run.distanceMeters / 1000,
                durationSeconds: Int(run.movingTimeSeconds),
                paceMinKm: run.averagePaceSecondsPerKm / 60,
                runType: router.plannedWorkout?.kind.rawValue ?? "free",
                isFirstRun: isFirst
            )
            Task {
                let outcome = await services.processCompletedActivity(run)
                await MainActor.run {
                    postActivityOutcome = outcome
                    isProcessingFinishedRun = false
                }
            }
        } else {
            finishedRun = nil
            postActivityOutcome = nil
            isProcessingFinishedRun = false
            router.dismissPostRunSummaryIfNeeded()
        }
    }

    private func discardRun() {
        RunSmartHaptics.medium()
        VoiceCoachService.shared.stopSession()
        Analytics.trackRunAbandoned(
            durationSeconds: Int(recorder.movingSeconds),
            distanceKm: recorder.distanceMeters / 1000
        )
        recorder.discard()
        finishedRun = nil
        postActivityOutcome = nil
        isProcessingFinishedRun = false
        router.dismissPostRunSummaryIfNeeded()
        router.clearRunContext()
    }

    private func saveFinishedRun() {
        finishedRun = nil
        postActivityOutcome = nil
        isProcessingFinishedRun = false
        router.dismissPostRunSummaryIfNeeded()
        router.clearRunContext()
        refreshMetrics()
    }

    private func deleteFinishedRun() {
        guard let run = finishedRun else {
            finishedRun = nil
            postActivityOutcome = nil
            isProcessingFinishedRun = false
            router.dismissPostRunSummaryIfNeeded()
            router.clearRunContext()
            return
        }
        Task {
            _ = await services.removeRun(run)
            await MainActor.run {
                finishedRun = nil
                postActivityOutcome = nil
                isProcessingFinishedRun = false
                router.dismissPostRunSummaryIfNeeded()
                router.clearRunContext()
                NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
            }
        }
    }
}
