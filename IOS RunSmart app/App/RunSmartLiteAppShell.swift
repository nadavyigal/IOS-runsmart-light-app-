import SwiftUI
import Combine
import Network

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
    private let coachModeEnabled: Bool

    init(coachModeEnabled: Bool = RunSmartFeatures.coachModeEnabled) {
        self.coachModeEnabled = coachModeEnabled
        if !coachModeEnabled, selectedTab == .coach { selectedTab = .today }
    }

    func shouldHandleAuthCallback(_ url: URL) -> Bool {
        !RunSmartFeatures.isCoachInviteURL(url)
    }
    @Published var activeSheet: RunSmartSheet?
    @Published var flexWeekLaunch: FlexWeekLaunchContext?
    @Published var plannedWorkout: WorkoutSummary?
    @Published var plannedRoute: RouteSuggestion?
    @Published var isTabBarHidden = false
    /// Set when Finish is tapped on the Live Activity; the Run tab answers with its finish sheet.
    @Published var liveActivityFinishRequested = false
    /// Set by the finished Live Activity's "View debrief" link; the Run tab opens that run's
    /// report unless its post-run summary is still on screen.
    @Published var pendingDebriefRunStartedAt: Date?
    /// Set to open Plan on the week that contains this date (Story 3.2: a week note from My coach).
    @Published var planFocusDate: Date?

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
        guard coachModeEnabled || !destination.requiresCoachMode else { return }
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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = AppRouter()
    @StateObject private var session = SupabaseSession()
    @StateObject private var recorder = RunRecorder()
    @StateObject private var runLiveActivity = RunLiveActivityCoordinator()
    @StateObject private var planGeneration = PlanGenerationStore()
    @StateObject private var guestJourney = GuestJourneyStore()
    @StateObject private var coachMode = CoachModeStore()
    @StateObject private var coachAthletes = CoachAthleteListModel()
    /// C7.0: `coachV2Enabled`, the server kill switch and the capability report.
    @StateObject private var coachV2Gate = CoachV2Gate()
    @StateObject private var coachLinks = CoachLinkStore(publishesAssistantContext: true)
    @StateObject private var athleteFeedback = AthleteFeedbackStore()
    /// Story 3.3: the one gate every coach element on Today and the Plan reads.
    @StateObject private var coachPresence = CoachPresence()
    @State private var didPresentMorningCheckin = false
    @State private var isShowingLaunch = !RunSmartDemoMode.isEnabled
    @State private var planNotice: RunSmartPlanNotice?
    @State private var planNoticeDismissTask: Task<Void, Never>?
    @State private var pendingOnboardingCompletion: OnboardingProfile?
    @State private var recordingOnboardingFinished = false
    @State private var firstRunActivation: FirstRunActivationContext?
    @State private var isAnalyticsReady = false
    @State private var isShowingGuestAuthentication = false
    private let activationFirstFrameTracker = ActivationFirstFrameTracker.shared
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
                signedOutContent
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
                signedOutContent
            } else if !session.hasCompletedOnboarding {
                onboardingContent
            } else {
                tabbedContent
            }
            #endif

            // C7.0 hooks live in their own view so this body's modifier chain stays type-checkable.
            CoachV2GateHooks(gate: coachV2Gate, athletes: coachAthletes, userID: coachRoleCheckUserID)
            // C7.3: effort and note sharing follow the gate, the link and the consent.
            AthleteRunSharingHooks(gate: coachV2Gate, links: coachLinks, userID: coachRoleCheckUserID, services: services)

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
        .environmentObject(coachMode)
        .environmentObject(coachLinks)
        .environmentObject(athleteFeedback)
        .environmentObject(coachPresence)
        // C7.8: Today's P9 notice reads `coachV2Enabled` from the gate.
        .environmentObject(coachV2Gate)
        .environment(\.coachAssistantActive, assistantContext.linkActive)
        .environment(\.coachAssistantName, assistantContext.coachDisplayName)
        .environment(\.runSmartServices, services)
        .environment(\.runRecorder, recorder)
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            openIncomingURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            openIncomingURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanGenerationStatusDidChange)) { notification in
            guard let status = notification.object as? RunSmartPlanGenerationStatus else { return }
            showPlanGenerationNotice(status)
        }
        .task {
            coachPresence.bind(to: coachLinks)
            runLiveActivity.bind(recorder: recorder, router: router)
            RunSmartWidgetSnapshotWriter.shared.bind(recorder: recorder)
            guard !RunSmartDemoMode.isEnabled else { return }
            // An unfinished run from a killed session is answered on the Run tab, so
            // land there on launch or the prompt would wait for a manual tab switch.
            if recorder.pendingRecovery != nil {
                router.selectedTab = .run
            }
            isAnalyticsReady = setupAnalyticsIfNeeded()
            Task { await StravaUploadCoordinator.shared.retryPending() }
            Task { await (services as? SupabaseRunSmartServices)?.retryPendingWorkoutCompletions() }
            PushService.shared.configureNavigation { destination in
                router.openNotificationDestination(destination)
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.32)) {
                isShowingLaunch = false
            }
        }
        .task(id: activationFirstFrameTrackingKey) {
            guard isAnalyticsReady, resolvedActivationFirstFrameScreen != nil else { return }
            // `isShowingLaunch` flips at the start of the opacity transition.
            // Wait for that 0.32-second dismissal to finish so this event names
            // the first product frame the person can actually see.
            do {
                try await Task.sleep(nanoseconds: 320_000_000)
            } catch {
                return
            }
            guard isAnalyticsReady,
                  !isShowingLaunch,
                  let screen = resolvedActivationFirstFrameScreen
            else { return }
            activationFirstFrameTracker.screenRendered(screen)
        }
        .task(id: coachRoleCheckUserID) {
            guard !RunSmartDemoMode.isEnabled else { return }
            await coachMode.refresh(userID: coachRoleCheckUserID)
        }
        .task(id: coachRoleCheckUserID) {
            guard !RunSmartDemoMode.isEnabled else { return }
            if let userID = coachRoleCheckUserID {
                coachLinks.beginSession(userID: userID)
                athleteFeedback.beginSession(userID: userID)
                // Feedback loads alongside the link refresh, never behind a slow route upload.
                async let feedbackLoad: Void = athleteFeedback.load()
                await coachLinks.refresh(userID: userID)
                await (services as? SupabaseRunSmartServices)?.retryCoachRoutes(coachLinks: coachLinks)
                await feedbackLoad
            } else {
                coachLinks.clear()
                athleteFeedback.beginSession(userID: nil)
            }
        }
        .task(id: coachRoleCheckUserID) {
            guard RunSmartFeatures.coachModeEnabled, let userID = coachRoleCheckUserID,
                  !RunSmartDemoMode.isEnabled else { return }
            for await path in NWPathMonitor() where path.status == .satisfied {
                guard !Task.isCancelled else { return }
                if CoachRouteOutbox.shared.choices.contains(where: { $0.key.ownerID == userID && $0.value.needsSync }) {
                    if coachLinks.activeLink(for: userID) == nil {
                        await coachLinks.refresh(userID: userID)
                    }
                    await (services as? SupabaseRunSmartServices)?.retryCoachRoutes(coachLinks: coachLinks)
                }
            }
        }
        .onChange(of: coachRoleCheckUserID) { _, userID in
            coachAthletes.reset(for: userID)
        }
        .onChange(of: coachMode.isCoach) { _, isCoach in
            if !isCoach { coachAthletes.reset(for: nil) }
            // A tab that stops existing (sign-out, unflagged coach) must not stay selected.
            if (!isCoach || !RunSmartFeatures.coachModeEnabled), router.selectedTab == .coach {
                router.selectedTab = .today
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Strava: finish uploads that failed or were still processing. Quiet, no UI.
            guard phase == .active, !RunSmartDemoMode.isEnabled else { return }
            if RunSmartFeatures.coachModeEnabled {
                Task { await coachMode.refresh(userID: coachRoleCheckUserID) }
            }
            if let userID = coachRoleCheckUserID {
                Task { await athleteFeedback.load() }
                Task {
                    await coachLinks.refresh(userID: userID)
                    await (services as? SupabaseRunSmartServices)?.retryCoachRoutes(coachLinks: coachLinks)
                }
            }
            Task { await StravaUploadCoordinator.shared.retryPending() }
            Task { await (services as? SupabaseRunSmartServices)?.retryPendingWorkoutCompletions() }
        }
        .onChange(of: router.selectedTab) { _, newTab in
            guard !RunSmartDemoMode.isEnabled else { return }
            // Register before tracking so the tab_viewed event itself, and every
            // autocaptured event that follows, carries the screen (WP-63).
            Analytics.registerCurrentScreen(Analytics.screenName(for: newTab))
            Analytics.trackTabViewed(tabName: newTab.rawValue)
        }
        .onChange(of: session.isAuthenticated) { _, isAuth in
            if !isAuth { RunSmartWidgetSnapshotWriter.shared.clear() }
            guard !RunSmartDemoMode.isEnabled else { return }
            // Strava tokens belong to one RunSmart user: drop them if a different runner signed in.
            StravaConnectionService.shared.reconcileOwnership()
            if isAuth, let userId = session.currentUserID {
                Analytics.identifyUser(userId: userId.uuidString)
                if guestJourney.state.isActive,
                   !guestJourney.state.didTrackAuthenticatedUpgrade {
                    guestJourney.markAuthenticatedUpgradeTracked()
                    Analytics.trackGuestAuthenticatedUpgrade()
                }
                isShowingGuestAuthentication = false
                if session.hasCompletedOnboarding {
                    guestJourney.clear()
                    resumeCoachJoinIfReady()
                }
            } else if !isAuth {
                Analytics.resetUser()
                isShowingGuestAuthentication = false
            }
        }
        .onChange(of: session.hasCompletedOnboarding) { _, isComplete in
            guard session.isAuthenticated, isComplete else { return }
            if guestJourney.state.isActive { guestJourney.clear() }
            resumeCoachJoinIfReady()
        }
        .onChange(of: session.isLoading) { _, isLoading in
            guard !isLoading else { return }
            resumeCoachJoinIfReady()
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
                    .environment(\.coachAssistantActive, assistantContext.linkActive)
                    .environment(\.coachAssistantName, assistantContext.coachDisplayName)
                    .environment(\.runSmartServices, services)
                    .environment(\.runRecorder, recorder)
            case .secondary(let destination):
                SecondaryFlowView(destination: destination)
                    .presentationDetents(fullHeightSecondaryDestinations.contains(destination) ? [.large] : [.medium, .large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(router)
                    .environmentObject(session)
                    .environmentObject(coachLinks)
                    .environmentObject(athleteFeedback)
                    .environmentObject(coachPresence)
                    .environmentObject(recorder)
                    .environment(\.coachAssistantActive, assistantContext.linkActive)
                    .environment(\.coachAssistantName, assistantContext.coachDisplayName)
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
            .environment(\.coachAssistantActive, assistantContext.linkActive)
            .environment(\.coachAssistantName, assistantContext.coachDisplayName)
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
    private var signedOutContent: some View {
        if RunSmartFeatureFlags.guestModeEnabled,
           guestJourney.state.isActive,
           !isShowingGuestAuthentication {
            GuestValueFlowView(
                journey: guestJourney,
                onExitGuest: {
                    isShowingGuestAuthentication = true
                },
                onRequestAuthentication: {
                    isShowingGuestAuthentication = true
                }
            )
        } else {
            let isReturningFromGuest = RunSmartFeatureFlags.guestModeEnabled
                && guestJourney.state.isActive
                && isShowingGuestAuthentication
            SignInView(
                onContinueAsGuest: RunSmartFeatureFlags.guestModeEnabled && !isReturningFromGuest ? {
                    guestJourney.start()
                    isShowingGuestAuthentication = false
                } : nil,
                onBackToGuest: isReturningFromGuest ? {
                        isShowingGuestAuthentication = false
                } : nil,
                backToGuestLabel: guestJourney.state.hasSeenPreview
                    ? "Back to preview"
                    : "Back to guest setup",
                guestReturnMessage: SignInView.guestReturnMessage(
                    hasSeenPreview: guestJourney.state.hasSeenPreview
                ),
                onJoinCoach: RunSmartFeatures.coachModeEnabled ? {
                    coachLinks.draftCode = ""
                    coachLinks.resumeJoinAfterSignIn = true
                } : nil
            )
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
            OnboardingView(
                initialProfile: onboardingInitialProfile,
                initialStep: onboardingInitialStep
            ) { profile in
                pendingOnboardingCompletion = profile
            }
            .environmentObject(session)
        }
    }

    private var onboardingInitialProfile: OnboardingProfile {
        guard guestJourney.state.isActive, guestJourney.state.hasSeenPreview else {
            return session.onboardingProfile
        }
        var profile = guestJourney.state.upgradeProfile
        if profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.displayName = session.onboardingProfile.displayName
        }
        return profile
    }

    private var onboardingInitialStep: Int {
        guard guestJourney.state.isActive else { return 0 }
        return guestJourney.state.authenticatedOnboardingStartStep
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
                    CustomTabBar(
                        selectedTab: $router.selectedTab,
                        tabs: RunSmartTab.visibleTabs(
                            isCoach: coachMode.isCoach,
                            coachModeEnabled: RunSmartFeatures.coachModeEnabled
                        ),
                        // Unread coach feedback, only while linked. It clears by reading, never by a timer.
                        badges: [.today: athleteFeedback.unreadCount(link: coachLinks.currentLink)]
                    )
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
        case .coach:
            if coachMode.isCoach, let ownerID = coachRoleCheckUserID {
                CoachTabView(ownerID: ownerID, athletes: coachAthletes)
                    .id(ownerID)
            } else {
                TodayTabView()
            }
        case .profile: ProfileTabView()
        }
    }

    /// Universal links and custom URLs. An invite link never falls through to auth.
    /// Coach Mode off does not open the join screen.
    private func openIncomingURL(_ url: URL) {
        // Live Activity and widget taps: runsmart://run/live, /debrief, /start.
        if RunSmartRunDeepLink.isRunLink(url) {
            router.selectedTab = .run
            router.pendingDebriefRunStartedAt = RunSmartRunDeepLink.debriefRunStartedAt(url)
            return
        }
        let canOpenJoinNow = !session.isLoading && session.isAuthenticated && session.hasCompletedOnboarding
        let consumed = coachLinks.receiveInviteLink(
            url,
            coachModeEnabled: RunSmartFeatures.coachModeEnabled,
            canOpenJoinNow: canOpenJoinNow
        )
        if consumed {
            if canOpenJoinNow, coachLinks.pendingInvite != nil {
                router.open(.joinCoach)
            }
            return
        }
        guard router.shouldHandleAuthCallback(url) else { return }
        Task { await session.handleAuthCallback(url) }
    }

    /// The signed-in user whose coach role to check; nil when signed out or guest.
    private func resumeCoachJoinIfReady() {
        guard RunSmartFeatures.coachModeEnabled else { return }
        if coachLinks.consumeJoinIntent(isAuthenticated: session.isAuthenticated,
                                        onboardingComplete: session.hasCompletedOnboarding) {
            router.open(.joinCoach)
        }
    }

    private var assistantContext: CoachContext {
        CoachContextSource.shared.context(for: coachRoleCheckUserID)
    }

    private var coachRoleCheckUserID: UUID? {
        RunSmartFeatures.coachModeEnabled && session.isAuthenticated ? session.currentUserID : nil
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
        let started = Date()
        let deadline = started.addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled { return nil }
            let workouts = await services.nextWorkouts(limit: 5)
            if let workout = workouts.first(where: { PlanPresentationModels.isWorkout($0) && !$0.isComplete })
                ?? workouts.first(where: { PlanPresentationModels.isWorkout($0) }) {
                return workout
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        // WP-45: the event existed but had no call site; this poll is where the
        // WP-43 S1 report said it belongs — generation produced no runnable
        // workout inside the activation window.
        Analytics.trackPlanGenerationTimedOut(durationMs: Int(Date().timeIntervalSince(started) * 1000))
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

    /// Destinations that need the full sheet height: the goal wizard's stepper
    /// flow, and the route screens, whose map-card lists sat below the fold at
    /// the medium detent (route-feature QA, 2026-07-23).
    private var fullHeightSecondaryDestinations: Set<SecondaryDestination> {
        [.goalWizard, .routeCreator, .routeSelector, .joinCoach]
    }

#if DEBUG
    private func openGate4ScreenshotDestinationIfNeeded() {
        guard RunSmartDemoMode.isEnabled, let destination = RunSmartGate4ScreenshotMode.initialSecondaryDestination else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            router.open(destination)
        }
    }
#endif

    private func setupAnalyticsIfNeeded() -> Bool {
        guard !RunSmartDemoMode.isEnabled else { return false }
        guard let credentials = Analytics.startupCredentials() else { return false }
        Analytics.setup(projectToken: credentials.projectToken, host: credentials.host)
        // Between setup and the first event, deliberately. Registering earlier is
        // a no-op because `Analytics.shared` is still the null service until
        // `setup` runs; registering later would leave `app_launched` — the
        // session-starting event — without the screen it began on.
        Analytics.registerCurrentScreen(Analytics.screenName(for: router.selectedTab))
        Analytics.trackAppLaunched()
        return true
    }

    private var resolvedActivationFirstFrameScreen: ActivationFirstFrameScreen? {
        guard !RunSmartDemoMode.isEnabled else { return nil }
        return ActivationFirstFrameScreen.resolved(
            isLaunchOverlayVisible: isShowingLaunch,
            isLoading: session.isLoading,
            isAuthenticated: session.isAuthenticated,
            hasCompletedOnboarding: session.hasCompletedOnboarding,
            isGuestJourneyActive: RunSmartFeatureFlags.guestModeEnabled
                && guestJourney.state.isActive
                && !isShowingGuestAuthentication
        )
    }

    private var activationFirstFrameTrackingKey: String {
        "\(isAnalyticsReady)-\(isShowingLaunch)-\(resolvedActivationFirstFrameScreen?.rawValue ?? "loading")"
    }
}

/// C7.0: syncs the v2 gate on sign-in, sign-out and every foreground (flags, then one
/// capability report), and passes its state to the coach roster. Renders nothing.
private struct CoachV2GateHooks: View {
    @ObservedObject var gate: CoachV2Gate
    let athletes: CoachAthleteListModel
    let userID: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: userID) {
                guard !RunSmartDemoMode.isEnabled else { return }
                await gate.sync(userID: userID)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !RunSmartDemoMode.isEnabled, RunSmartFeatures.coachModeEnabled else { return }
                Task { await gate.sync(userID: userID) }
            }
            .onChange(of: gate.state) { _, state in
                Task { await athletes.applyCoachV2(state) }
            }
    }
}

/// C7.3: refreshes effort and note sharing on sign-in, when the v2 gate or the coach link
/// changes, and on every foreground. With v2 off it makes no call.
private struct AthleteRunSharingHooks: View {
    @ObservedObject var gate: CoachV2Gate
    @ObservedObject var links: CoachLinkStore
    let userID: UUID?
    let services: any RunSmartServiceProviding
    @Environment(\.scenePhase) private var scenePhase

    private var key: String {
        "\(userID?.uuidString ?? "-").\(gate.isEnabled).\(links.currentLink?.id.uuidString ?? "-")"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: key) { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .coachConsentV2Acked)) { _ in
                Task { await refresh() }
            }
    }

    private func refresh() async {
        guard !RunSmartDemoMode.isEnabled, RunSmartFeatures.coachModeEnabled else { return }
        let link = links.currentLink
        await (services as? SupabaseRunSmartServices)?.refreshRunSharing(
            v2Enabled: gate.isEnabled, linkID: link?.id, coachName: link?.coachName
        )
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
