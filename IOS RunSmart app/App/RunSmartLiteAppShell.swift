import SwiftUI
import Combine

enum RunSmartSheet: Identifiable {
    case coach(CoachEntryPoint)
    case secondary(SecondaryDestination)

    var id: String {
        switch self {
        case .coach(let context): "coach-\(context.rawValue)"
        case .secondary(let dest): "secondary-\(dest.id)"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: RunSmartTab = AppRouter.initialTab()
    @Published var activeSheet: RunSmartSheet?
    @Published var flexWeekLaunch: FlexWeekLaunchContext?
    @Published var plannedWorkout: WorkoutSummary?
    @Published var plannedRoute: RouteSuggestion?
    @Published var isTabBarHidden = false

    private static func initialTab() -> RunSmartTab {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-INITIAL_TAB"),
           args.indices.contains(idx + 1),
           let tab = RunSmartTab.allCases.first(where: { tab in
               tab.rawValue.caseInsensitiveCompare(args[idx + 1]) == .orderedSame
           }) {
            return tab
        }

        if let tabName = ProcessInfo.processInfo.environment["RUNSMART_INITIAL_TAB"],
           let tab = RunSmartTab.allCases.first(where: { tab in
               tab.rawValue.caseInsensitiveCompare(tabName) == .orderedSame
           }) {
            return tab
        }
#endif
        return .today
    }

    func openCoach(context: CoachEntryPoint) {
        activeSheet = .coach(context)
    }

    func openCoach(context: String) {
        openCoach(context: CoachEntryPoint(label: context))
    }

    func open(_ destination: SecondaryDestination) {
        activeSheet = .secondary(destination)
    }

    func openFlexWeek(
        preselectedReason: FlexWeekReason? = nil,
        entryPoint: FlexWeekEntryPoint = .planPill
    ) {
        activeSheet = nil
        flexWeekLaunch = FlexWeekLaunchContext(
            preselectedReason: preselectedReason,
            entryPoint: entryPoint
        )
    }

    func dismissFlexWeek() {
        flexWeekLaunch = nil
    }

    func dismissPostRunSummaryIfNeeded() {
        guard case .secondary(.postRunSummary) = activeSheet else { return }
        activeSheet = nil
    }

    func clearRunContext() {
        plannedWorkout = nil
        plannedRoute = nil
    }

    func startRun(with workout: WorkoutSummary? = nil, route: RouteSuggestion? = nil) {
        RunSmartHaptics.medium()
        plannedWorkout = workout
        plannedRoute = route
        activeSheet = nil
        selectedTab = .run
    }

    func openNotificationDestination(_ destination: RunSmartNotificationDestination) {
        activeSheet = nil
        switch destination {
        case .today:
            selectedTab = .today
        case .plan:
            selectedTab = .plan
        case .report:
            selectedTab = .report
        }
    }
}

#if DEBUG
enum RunSmartRecordingMode {
    static var isOnboardingReplayEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-RUNSMART_RECORD_ONBOARDING")
            || env["RUNSMART_RECORD_ONBOARDING"] == "1"
    }

    /// QA-only: skip the post-onboarding aha-moments carousel and land directly on Today,
    /// so a HealthKit-connected simulator run reaches the Today tab without fighting the
    /// aha-moments/first-run-activation sheet flow. Only takes effect alongside onboarding replay.
    static var isSkipAhaMomentsEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-RUNSMART_SKIP_AHA_MOMENTS")
            || env["RUNSMART_SKIP_AHA_MOMENTS"] == "1"
    }

    static var onboardingProfile: OnboardingProfile {
        OnboardingProfile(
            displayName: "Alex Morgan",
            goal: "First 5K",
            experience: "Getting started",
            age: 29,
            averageWeeklyDistanceKm: 0,
            trainingDataSource: nil,
            trainingDataUpdatedAt: nil,
            weeklyRunDays: 3,
            preferredDays: ["Mon", "Wed", "Sat"],
            units: "Metric",
            coachingTone: "Motivating",
            notificationsEnabled: true,
            planAdjustmentConfirmationsEnabled: true
        )
    }
}
#endif

struct RunSmartLiteAppShell: View {
    @StateObject private var router = AppRouter()
    @StateObject private var session = SupabaseSession()
    @StateObject private var recorder = RunRecorder()
    @StateObject private var planGeneration = PlanGenerationStore()
    @State private var didPresentMorningCheckin = false
    @State private var isShowingLaunch = !RunSmartDemoMode.isEnabled
    @State private var planNotice: RunSmartPlanNotice?
    @State private var planNoticeDismissTask: Task<Void, Never>?
    @State private var pendingOnboardingCompletion: OnboardingProfile?
    @State private var recordingOnboardingFinished = false
    @State private var firstRunActivation: FirstRunActivationContext?
    private let services: any RunSmartServiceProviding = RunSmartDemoMode.services

    var body: some View {
        ZStack {
            RunSmartBackground(context: RunSmartBackgroundContext(tab: router.selectedTab))

            #if DEBUG
            if RunSmartRecordingMode.isOnboardingReplayEnabled {
                recordingOnboardingContent
            } else if RunSmartDemoMode.isEnabled {
                tabbedContent
                    .onAppear {
                        openGate4ScreenshotDestinationIfNeeded()
                    }
            } else if session.isLoading {
                RunSmartLaunchView()
            } else if !session.isAuthenticated {
                SignInView()
                    .environmentObject(session)
            } else if !session.hasCompletedOnboarding {
                onboardingContent
            } else {
                tabbedContent
            }
            #else
            if RunSmartDemoMode.isEnabled {
                tabbedContent
            } else if session.isLoading {
                RunSmartLaunchView()
            } else if !session.isAuthenticated {
                SignInView()
                    .environmentObject(session)
            } else if !session.hasCompletedOnboarding {
                onboardingContent
            } else {
                tabbedContent
            }
            #endif

            if isShowingLaunch {
                RunSmartLaunchView()
                    .transition(.opacity)
                    .zIndex(10)
            }

            if let planNotice {
                VStack {
                    RunSmartPlanNoticeBanner(notice: planNotice)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(9)
            }
        }
        .environmentObject(router)
        .environmentObject(session)
        .environmentObject(recorder)
        .environmentObject(planGeneration)
        .environment(\.runSmartServices, services)
        .environment(\.runRecorder, recorder)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanGenerationStatusDidChange)) { notification in
            guard let status = notification.object as? RunSmartPlanGenerationStatus else { return }
            showPlanGenerationNotice(status)
        }
        .task {
            guard !RunSmartDemoMode.isEnabled else { return }
            setupAnalyticsIfNeeded()
            PushService.shared.configureNavigation { destination in
                router.openNotificationDestination(destination)
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.32)) {
                isShowingLaunch = false
            }
        }
        .onChange(of: router.selectedTab) { _, newTab in
            guard !RunSmartDemoMode.isEnabled else { return }
            Analytics.trackTabViewed(tabName: newTab.rawValue)
        }
        .onChange(of: session.isAuthenticated) { _, isAuth in
            guard !RunSmartDemoMode.isEnabled else { return }
            if isAuth, let userId = session.currentUserID {
                Analytics.identifyUser(userId: userId.uuidString)
            } else if !isAuth {
                Analytics.resetUser()
            }
        }
        .task(id: session.hasCompletedOnboarding) {
            guard !RunSmartDemoMode.isEnabled else { return }
            guard session.isAuthenticated, session.hasCompletedOnboarding else { return }
            await refreshReturnLoopReminders()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanDidChange)) { _ in
            guard !RunSmartDemoMode.isEnabled else { return }
            Task { await refreshReturnLoopReminders() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            guard !RunSmartDemoMode.isEnabled else { return }
            Task { await refreshReturnLoopReminders() }
        }
        .task(id: session.hasCompletedOnboarding) {
            guard !RunSmartDemoMode.isEnabled else { return }
            guard session.isAuthenticated, session.hasCompletedOnboarding, !didPresentMorningCheckin else { return }
            didPresentMorningCheckin = true
            try? await Task.sleep(nanoseconds: 650_000_000)
            if router.activeSheet == nil, await services.shouldPresentManualMorningCheckin() {
                router.open(.morningCheckin)
            }
        }
        .sheet(item: $router.activeSheet) { sheet in
            switch sheet {
            case .coach(let context):
                CoachFlowView(entryPoint: context)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(router)
                    .environmentObject(session)
                    .environmentObject(recorder)
                    .environment(\.runSmartServices, services)
                    .environment(\.runRecorder, recorder)
            case .secondary(let destination):
                SecondaryFlowView(destination: destination)
                    .presentationDetents(destination == .goalWizard ? [.large] : [.medium, .large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(router)
                    .environmentObject(session)
                    .environmentObject(recorder)
                    .environment(\.runSmartServices, services)
                    .environment(\.runRecorder, recorder)
            }
        }
        .fullScreenCover(item: $router.flexWeekLaunch) { launch in
            FlexWeekEntryView(launch: launch) {
                router.dismissFlexWeek()
            }
            .environmentObject(router)
            .environmentObject(session)
            .environmentObject(recorder)
            .environment(\.runSmartServices, services)
            .environment(\.runRecorder, recorder)
        }
        .sheet(item: $firstRunActivation) { context in
            FirstRunActivationSheet(
                workout: context.workout,
                onStartNow: { handleFirstRunStartNow(context.workout) },
                onRemindMe: { handleFirstRunRemindMe(context.workout) }
            )
            .interactiveDismissDisabled()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .environmentObject(router)
            .environmentObject(session)
        }
    }

    @ViewBuilder
    private var onboardingContent: some View {
        if let pendingProfile = pendingOnboardingCompletion {
            OnboardingAhaMomentsContainer(profile: pendingProfile) {
                let profile = pendingProfile
                pendingOnboardingCompletion = nil
                Task {
                    await session.completeOnboarding(profile)
                    let request = TrainingGoalRequest.onboardingDefault(from: profile)
                    let saved = await services.saveTrainingGoal(request)
                    await presentFirstRunActivationIfNeeded(planSaved: saved)
                }
            }
            .environmentObject(session)
        } else {
            OnboardingView(initialProfile: session.onboardingProfile) { profile in
                pendingOnboardingCompletion = profile
            }
            .environmentObject(session)
        }
    }

    #if DEBUG
    @ViewBuilder
    private var recordingOnboardingContent: some View {
        if recordingOnboardingFinished {
            tabbedContent
        } else if let pendingProfile = pendingOnboardingCompletion {
            if RunSmartRecordingMode.isSkipAhaMomentsEnabled {
                Color.clear
                    .onAppear {
                        pendingOnboardingCompletion = nil
                        recordingOnboardingFinished = true
                        router.selectedTab = .today
                    }
            } else {
                OnboardingAhaMomentsContainer(profile: pendingProfile) {
                    pendingOnboardingCompletion = nil
                    recordingOnboardingFinished = true
                    router.selectedTab = .plan
                }
                .environmentObject(session)
            }
        } else {
            OnboardingView(initialProfile: RunSmartRecordingMode.onboardingProfile) { profile in
                pendingOnboardingCompletion = profile
            }
            .environmentObject(session)
        }
    }
    #endif

    private var tabbedContent: some View {
        tabContent
            .safeAreaPadding(.bottom, router.isTabBarHidden ? 0 : CustomTabBar.contentAvoidancePadding)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !router.isTabBarHidden {
                    CustomTabBar(selectedTab: $router.selectedTab)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: router.isTabBarHidden)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch router.selectedTab {
        case .today:   TodayTabView()
        case .plan:    PlanTabView()
        case .run:     RunTabView()
        case .report:  ReportTabView()
        case .profile: ProfileTabView()
        }
    }

    private func showPlanGenerationNotice(_ status: RunSmartPlanGenerationStatus) {
        let notice = RunSmartPlanNotice(status: status)
        planNoticeDismissTask?.cancel()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            planNotice = notice
        }

        planNoticeDismissTask = Task {
            try? await Task.sleep(nanoseconds: status.displayNanoseconds)
            await MainActor.run {
                guard planNotice == notice else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    planNotice = nil
                }
            }
        }
    }

    private func refreshReturnLoopReminders() async {
        guard session.isAuthenticated, session.hasCompletedOnboarding else { return }
        async let workoutsTask = services.nextWorkouts(limit: 8)
        async let runsTask = services.recentRuns()
        async let recoveryTask = services.recoverySnapshot()
        let (workouts, runs, recovery) = await (workoutsTask, runsTask, recoveryTask)
        await PushService.shared.scheduleReturnLoopReminders(
            profile: session.onboardingProfile,
            workouts: workouts,
            recentRuns: runs,
            recovery: recovery
        )
    }

    private func presentFirstRunActivationIfNeeded(planSaved: Bool) async {
        guard planSaved else { return }
        // saveTrainingGoal kicks off async plan generation; workouts are not queryable until it finishes.
        guard let firstWorkout = await firstRunnableWorkoutAfterPlanGeneration() else { return }
        await MainActor.run {
            firstRunActivation = FirstRunActivationContext(workout: firstWorkout)
        }
    }

    private func firstRunnableWorkoutAfterPlanGeneration(timeoutSeconds: TimeInterval = 45) async -> WorkoutSummary? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return nil }
            let workouts = await services.nextWorkouts(limit: 5)
            if let workout = workouts.first(where: { PlanPresentationModels.isWorkout($0) && !$0.isComplete })
                ?? workouts.first(where: { PlanPresentationModels.isWorkout($0) }) {
                return workout
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }

    private func handleFirstRunStartNow(_ workout: WorkoutSummary) {
        Analytics.trackFirstRunCTATapped(action: "start_now", workoutType: workout.kind.rawValue)
        Analytics.trackPlanRunCTATapped(
            source: "onboarding_first_run",
            workoutType: workout.kind.rawValue,
            scheduledToday: Calendar.current.isDateInToday(workout.scheduledDate),
            hasPriorRuns: false
        )
        firstRunActivation = nil
        router.startRun(with: workout)
    }

    private func handleFirstRunRemindMe(_ workout: WorkoutSummary) {
        Analytics.trackFirstRunCTATapped(action: "remind_me", workoutType: workout.kind.rawValue)
        session.setNotificationsEnabled(true)
        firstRunActivation = nil
        router.selectedTab = .today
        Task {
            let scheduled = await PushService.shared.scheduleFirstRunReminder(workout: workout)
            if scheduled {
                Analytics.trackFirstRunReminderScheduled(
                    source: "onboarding_first_run",
                    workoutType: workout.kind.rawValue
                )
            }
            await refreshReturnLoopReminders()
        }
    }

#if DEBUG
    private func openGate4ScreenshotDestinationIfNeeded() {
        guard RunSmartDemoMode.isEnabled, let destination = RunSmartGate4ScreenshotMode.initialSecondaryDestination else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            router.open(destination)
        }
    }
#endif

    private func setupAnalyticsIfNeeded() {
        guard !RunSmartDemoMode.isEnabled else { return }
        guard let token = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
              !token.isEmpty,
              let host = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String
        else { return }
        Analytics.setup(projectToken: token, host: host)
        Analytics.trackAppLaunched()
    }
}

struct RunSmartPlanNotice: Equatable {
    let id = UUID()
    let status: RunSmartPlanGenerationStatus
    let title: String
    let message: String
    let symbol: String
    let tint: Color

    init(status: RunSmartPlanGenerationStatus) {
        self.status = status
        switch status {
        case .generating:
            title = "Generating Training Plan"
            message = "Coach is building a new plan from your updated training data."
            symbol = "sparkles"
            tint = .accentRecovery
        case .amended:
            title = "Training Plan Amended"
            message = "Your updated plan is ready. Today and Plan are refreshing."
            symbol = "checkmark.seal.fill"
            tint = .accentSuccess
        case .failed:
            title = "Plan Update Delayed"
            // Don't send a first-time user to a Profile-buried screen they have
            // never seen — Today and Plan now carry their own inline retry
            // (WP-43 S1 / audit §4 Risk 1).
            message = "Your details are saved. Tap Try again on Today or Plan to rebuild your plan."
            symbol = "exclamationmark.triangle.fill"
            tint = .accentHeart
        }
    }

    static func == (lhs: RunSmartPlanNotice, rhs: RunSmartPlanNotice) -> Bool {
        lhs.id == rhs.id
    }
}

private extension RunSmartPlanGenerationStatus {
    var displayNanoseconds: UInt64 {
        switch self {
        case .generating: 4_500_000_000
        case .amended, .failed: 5_500_000_000
        }
    }
}

private struct RunSmartPlanNoticeBanner: View {
    var notice: RunSmartPlanNotice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.black)
                .frame(width: 36, height: 36)
                .background(notice.tint, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.bodyMD.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(notice.tint.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: notice.tint.opacity(0.18), radius: 20, x: 0, y: 10)
        .accessibilityElement(children: .combine)
    }
}
