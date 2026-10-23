import SwiftUI

struct RunTabView: View {
    @Environment(\.runSmartServices) private var services
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var recorder: RunRecorder

    @State private var metrics: [MetricTile] = []
    @State private var finishedRun: RecordedRun?
    @State private var postActivityOutcome: PostActivityOutcome?
    @State private var isProcessingFinishedRun = false
    @ObservedObject private var weight = RunnerWeightStore.shared
    @State private var showsWeightSetup = false
    @State private var resumeAfterEndSheet = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false

#if DEBUG
    /// Simulator QA: `-RUNSMART_DEMO_MODE -AUTO_START_RUN -DEMO_GUIDE_INTERVALS` starts a run with a
    /// short warm-up and 6 x 400 m reps so the live guide card shows a rep without a 10 minute wait.
    private static let demoIntervalWorkout = WorkoutSummary(
        id: UUID(), scheduledDate: Date(), planID: nil, weekday: "Thu", date: "22", kind: .intervals,
        title: "6 x 400 m", distance: "6 x 400m", detail: "", isToday: true, isComplete: false,
        durationMinutes: nil, targetPaceSecondsPerKm: nil, intensity: nil, trainingPhase: nil,
        workoutStructure: #"{"steps":[{"type":"warmup","duration_seconds":4},{"type":"repeat","reps_count":6,"rep_distance":"400 m","pace_seconds_per_km":270,"note":"90 s recovery"},{"type":"cooldown","duration_seconds":300}]}"#
    )
#endif

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
                    completedKmSplits: recorder.completedKilometerSplits,
                    phase: recorder.phase,
                    isAutoPaused: recorder.isAutoPaused,
                    guide: recorder.workoutGuide,
                    currentPaceSeconds: recorder.currentPaceSeconds,
                    gpsStatus: gpsStatus,
                    gpsDetail: gpsDetail,
                    elapsedSeconds: recorder.movingSeconds,
                    onPauseResume: primaryRunAction,
                    onFinish: requestFinishRun,
                    onDiscard: requestFinishRun
                )
            } else {
                PreRunView(
                    metrics: metrics,
                    plannedWorkout: router.plannedWorkout,
                    selectedRoute: router.plannedRoute,
                    phase: recorder.phase,
                    gpsStatus: gpsStatus,
                    gpsDetail: gpsDetail,
                    canStartWithoutGPS: recorder.canStartWithoutFix,
                    onStart: startRun,
                    onCancelGPS: cancelGPSWait,
                    onStartWithoutGPS: startWithoutGPS,
                    onRoute: openRouteCreator,
                    onAudio: openAudioCues
                )
            }
        }
        .task {
            await reloadMetrics()
            await weight.refreshHealthWeightIfEnabled()
            if weight.shouldOfferWeightSetup, recorder.pendingRecovery == nil, finishedRun == nil, recorder.phase != .recording, recorder.phase != .paused {
                weight.markWeightSetupOffered()
                showsWeightSetup = true
            }
        }
#if DEBUG
        .onAppear {
            guard RunSmartDemoMode.isEnabled,
                  ProcessInfo.processInfo.arguments.contains("-AUTO_START_RUN"),
                  recorder.phase == .ready else { return }
            if ProcessInfo.processInfo.arguments.contains("-DEMO_GUIDE_INTERVALS"), router.plannedWorkout == nil {
                router.plannedWorkout = Self.demoIntervalWorkout
            }
            recorder.activeWorkoutTitle = router.plannedWorkout?.title
            recorder.activeGuideSteps = router.plannedWorkout.flatMap { StructuredWorkoutFactory.makeGuideSteps(for: $0) }
            recorder.start()
        }
#endif
        .onAppear {
            updateTabBarVisibility()
            updateRunSessionSideEffects(for: recorder.phase)
            recorder.onRecoveredRunAutoSaved = { [services] run in
                Self.processRecoveredRunSilently(run, services: services)
            }
        }
        .onDisappear {
            router.isTabBarHidden = false
            RunScreenAwakePolicy.setRecordingActive(false)
            RunLiveActivityController.end()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            refreshMetrics()
        }
        .onChange(of: finishedRun?.id) { _, _ in
            updateTabBarVisibility()
        }
        .onChange(of: recorder.phase) { oldPhase, newPhase in
            updateTabBarVisibility()
            updateRunSessionSideEffects(for: newPhase)
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
        .onReceive(NotificationCenter.default.publisher(for: .runSmartLiveActivityPauseResume)) { _ in
            primaryRunAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartLiveActivityFinish)) { _ in
            requestFinishRun()
        }
        .onChange(of: recorder.distanceLabel) { _, _ in
            syncRunLiveActivity()
        }
        .onChange(of: recorder.movingLabel) { _, _ in
            syncRunLiveActivity()
        }
        .onChange(of: recorder.currentPaceLabel) { _, _ in
            syncRunLiveActivity()
        }
        .sheet(isPresented: $isConfirmingFinish, onDismiss: {
            recorder.isEndDecisionPending = false
            if resumeAfterEndSheet, recorder.phase == .paused { recorder.resume() }
            resumeAfterEndSheet = false
        }) {
            VStack(spacing: 22) {
                Text("End this run?").font(.title2.bold())
                Text("\(recorder.distanceLabel) km · \(recorder.movingLabel)")
                    .font(.title3.monospacedDigit())
                Text(isVeryShortRun ? "Short activities may be saved for review without counting as meaningful training." : "Your run stays paused while you decide.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Save Run") {
                    resumeAfterEndSheet = false
                    finishRun()
                }.buttonStyle(.borderedProminent)
                Button("Resume") {
                    resumeAfterEndSheet = true
                    isConfirmingFinish = false
                }
                    .buttonStyle(.bordered)
                Button("Discard Run", role: .destructive) {
                    isConfirmingDiscard = true
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled()
            .alert("Discard this run?", isPresented: $isConfirmingDiscard) {
                Button("Discard Run", role: .destructive) {
                    resumeAfterEndSheet = false
                    isConfirmingFinish = false
                    discardRun()
                }
                Button("Keep Run", role: .cancel) {}
            } message: {
                Text("The distance, time and route of this run will be deleted. This cannot be undone.")
            }
        }
        .sheet(isPresented: $showsWeightSetup) {
            NavigationStack {
                ScrollView { RunnerWeightSettingsView().padding() }
                    .navigationTitle("Calorie estimate")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsWeightSetup = false }
                        }
                    }
            }
        }
        // The app was killed or crashed mid-run. Every button clears
        // `pendingRecovery`, so the alert cannot be dismissed without an answer.
        .alert(
            "Unfinished run found",
            isPresented: Binding(
                get: { isRecoveryPromptVisible },
                set: { _ in }
            )
        ) {
            if recorder.canResumeRecoveredRun {
                Button("Resume Run") {
                    recorder.resumeRecoveredRun()
                }
            }
            Button("Save Run") {
                saveRecoveredRun()
            }
            Button("Discard", role: .destructive) {
                recorder.discardRecoveredRun()
            }
        } message: {
            Text(recoveryMessage)
        }
    }

    private var isRecoveryPromptVisible: Bool {
        recorder.pendingRecovery != nil
            && recorder.phase != .recording
            && recorder.phase != .paused
            && finishedRun == nil
    }

    private var recoveryMessage: String {
        guard let checkpoint = recorder.pendingRecovery else { return "" }
        let distance = String(format: "%.2f km", checkpoint.distanceMeters / 1_000)
        let moving = RunRecorder.timeLabel(checkpoint.movingSecondsAtSave)
        let started = Calendar.current.isDateInToday(checkpoint.startedAt)
            ? checkpoint.startedAt.formatted(date: .omitted, time: .shortened)
            : checkpoint.startedAt.formatted(date: .abbreviated, time: .shortened)
        let choices = recorder.canResumeRecoveredRun
            ? "Resume it, save it, or discard it."
            : "Save it or discard it."
        return "\(distance), \(moving) moving time, started \(started). \(choices)"
    }

    private var liveMetrics: [MetricTile] {
        [
            MetricTile(title: "Distance", value: recorder.distanceLabel, unit: "km", symbol: "point.topleft.down.curvedto.point.bottomright.up", tint: .accentPrimary),
            MetricTile(title: "Moving time", value: recorder.movingLabel, unit: "", symbol: "stopwatch", tint: .textPrimary),
            MetricTile(title: "Average Pace", value: recorder.averagePaceLabel, unit: "/km", symbol: "speedometer", tint: .accentRecovery),
            MetricTile(title: "Current Pace", value: recorder.currentPaceLabel, unit: "/km", symbol: "timer", tint: .accentEnergy),
            MetricTile(title: "Calories", value: recorder.estimatedActiveKilocalories.map { String(format: "%.0f", $0) } ?? "--", unit: weight.weightKg == nil ? "Weight needed" : "kcal · est.", symbol: "flame", tint: .accentEnergy)
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
            if recorder.routePoints.isEmpty {
                return "Timer running. Waiting for the first good GPS point; distance starts then."
            }
            if let accuracy = recorder.horizontalAccuracy {
                return "Timer running. \(accuracyMessage(accuracy))"
            }
            return "Timer running."
        case .paused:
            return "Resume to continue distance tracking or finish to save."
        case .denied:
            return "Enable location access in iOS Settings to record outdoor runs."
        default:
            return "Track distance, moving time, pace, and route with phone GPS."
        }
    }

    private var shouldHideTabBar: Bool {
        finishedRun != nil || recorder.phase == .recording || recorder.phase == .paused
    }

    private var isVeryShortRun: Bool {
        recorder.distanceMeters < 100 || recorder.movingSeconds < 60
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
        recorder.activeWorkoutTitle = router.plannedWorkout?.title
        recorder.activeGuideSteps = router.plannedWorkout.flatMap { StructuredWorkoutFactory.makeGuideSteps(for: $0) }
        recorder.start()
    }

    private func cancelGPSWait() {
        RunSmartHaptics.light()
        recorder.cancelAcquiring()
    }

    private func startWithoutGPS() {
        RunSmartHaptics.medium()
        // run_started already fired when the runner tapped Start; no second event.
        recorder.startWithoutFix()
    }

    private func openRouteCreator() {
        router.open(.routeCreator)
    }

    private func openAudioCues() {
        router.open(.audioCues)
    }

    private func updateTabBarVisibility() {
        router.isTabBarHidden = shouldHideTabBar
    }

    private func requestFinishRun() {
        guard recorder.phase == .recording || recorder.phase == .paused, !isConfirmingFinish else { return }
        RunSmartHaptics.light()
        resumeAfterEndSheet = recorder.phase == .recording
        recorder.isEndDecisionPending = true
        if resumeAfterEndSheet { recorder.pause() }
        isConfirmingFinish = true
    }

    private func updateRunSessionSideEffects(for phase: RunRecordingPhase) {
        let isLiveRun = phase == .recording || phase == .paused
        RunScreenAwakePolicy.setRecordingActive(isLiveRun)
        syncRunLiveActivity()
        if !isLiveRun {
            RunLiveActivityController.end()
        }
    }

    private func syncRunLiveActivity() {
        let isLiveRun = recorder.phase == .recording || recorder.phase == .paused
        RunLiveActivityController.sync(
            workoutTitle: router.plannedWorkout?.title ?? recorder.activeWorkoutTitle ?? "Free Run",
            distanceLabel: recorder.distanceLabel,
            movingTimeLabel: recorder.movingLabel,
            paceLabel: recorder.currentPaceLabel,
            isPaused: recorder.phase == .paused,
            isActive: isLiveRun
        )
    }

    private func reloadMetrics() async {
        metrics = await services.currentRunMetrics()
    }

    private func refreshMetrics() {
        Task { await reloadMetrics() }
    }

    private func finishRun() {
        RunSmartHaptics.medium()
        isConfirmingFinish = false
        VoiceCoachService.shared.stopSession()
        let run = recorder.finish()
        if let run {
            presentFinishedRun(run)
        } else {
            finishedRun = nil
            postActivityOutcome = nil
            isProcessingFinishedRun = false
            router.dismissPostRunSummaryIfNeeded()
        }
        updateTabBarVisibility()
    }

    /// Shared tail of finishing a live run and saving a recovered one: health export,
    /// post-run summary and activity processing.
    private func presentFinishedRun(_ run: RecordedRun) {
        router.dismissPostRunSummaryIfNeeded()
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
                updateTabBarVisibility()
            }
            // Strava: after processing, off the main actor, never blocks. A failure is kept for the next foreground.
            await StravaUploadCoordinator.shared.autoUploadIfEnabled(run)
        }
        updateTabBarVisibility()
    }

    /// A recovered run that was saved because a new run started: same Health export and
    /// processing as any finished run, without taking over the screen the new run is using.
    private static func processRecoveredRunSilently(_ run: RecordedRun, services: any RunSmartServiceProviding) {
        NotificationCenter.default.post(name: .runSmartRunsDidChange, object: nil)
        Task {
            await services.saveToHealth(run)
            _ = await services.processCompletedActivity(run)
            await StravaUploadCoordinator.shared.autoUploadIfEnabled(run)
        }
    }

    private func saveRecoveredRun() {
        RunSmartHaptics.medium()
        if let run = recorder.saveRecoveredRun() {
            presentFinishedRun(run)
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
        updateTabBarVisibility()
    }

    private func saveFinishedRun() {
        finishedRun = nil
        postActivityOutcome = nil
        isProcessingFinishedRun = false
        router.dismissPostRunSummaryIfNeeded()
        router.clearRunContext()
        refreshMetrics()
        updateTabBarVisibility()
    }

    private func deleteFinishedRun() {
        guard let run = finishedRun else {
            finishedRun = nil
            postActivityOutcome = nil
            isProcessingFinishedRun = false
            router.dismissPostRunSummaryIfNeeded()
            router.clearRunContext()
            updateTabBarVisibility()
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
                updateTabBarVisibility()
            }
        }
    }
}
