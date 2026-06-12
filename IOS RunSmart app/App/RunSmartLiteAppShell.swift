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

enum RunSmartScreenshotMode {
    static var isEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-RUNSMART_SCREENSHOT_MODE")
        || ProcessInfo.processInfo.environment["RUNSMART_SCREENSHOT_MODE"] == "1"
#else
        false
#endif
    }

    static var services: any RunSmartServiceProviding {
#if DEBUG
        isEnabled ? MockRunSmartServices() : SupabaseRunSmartServices.shared
#else
        SupabaseRunSmartServices.shared
#endif
    }
}

struct RunSmartLiteAppShell: View {
    @StateObject private var router = AppRouter()
    @StateObject private var session = SupabaseSession()
    @StateObject private var recorder = RunRecorder()
    @State private var didPresentMorningCheckin = false
    @State private var isShowingLaunch = !RunSmartScreenshotMode.isEnabled
    @State private var planNotice: RunSmartPlanNotice?
    @State private var planNoticeDismissTask: Task<Void, Never>?
    @State private var pendingOnboardingCompletion: OnboardingProfile?
    private let services: any RunSmartServiceProviding = RunSmartScreenshotMode.services

    var body: some View {
        ZStack {
            RunSmartBackground(context: RunSmartBackgroundContext(tab: router.selectedTab))

            if RunSmartScreenshotMode.isEnabled {
                tabContent
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        CustomTabBar(selectedTab: $router.selectedTab)
                    }
            } else if session.isLoading {
                RunSmartLaunchView()
            } else if !session.isAuthenticated {
                SignInView()
                    .environmentObject(session)
            } else if !session.hasCompletedOnboarding {
                if let pendingProfile = pendingOnboardingCompletion {
                    OnboardingAhaMomentsContainer(profile: pendingProfile) {
                        let profile = pendingProfile
                        pendingOnboardingCompletion = nil
                        Task {
                            await session.completeOnboarding(profile)
                            let request = TrainingGoalRequest(
                                displayName: profile.displayName,
                                goal: profile.goal.isEmpty ? "build a running habit" : profile.goal,
                                experience: profile.experience.isEmpty ? "beginner" : profile.experience,
                                age: profile.age,
                                averageWeeklyDistanceKm: profile.averageWeeklyDistanceKm,
                                trainingDataSource: profile.trainingDataSource,
                                weeklyRunDays: profile.weeklyRunDays > 0 ? profile.weeklyRunDays : 3,
                                preferredDays: profile.preferredDays.isEmpty ? ["Mon", "Wed", "Sat"] : profile.preferredDays,
                                coachingTone: profile.coachingTone.isEmpty ? "Motivating" : profile.coachingTone,
                                targetDate: Date().addingTimeInterval(21 * 24 * 3600)
                            )
                            _ = await services.saveTrainingGoal(request)
                        }
                    }
                    .environmentObject(session)
                } else {
                    OnboardingView(initialProfile: session.onboardingProfile) { profile in
                        pendingOnboardingCompletion = profile
                    }
                    .environmentObject(session)
                }
            } else {
                tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    CustomTabBar(selectedTab: $router.selectedTab)
                }
            }

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
        .environment(\.runSmartServices, services)
        .environment(\.runRecorder, recorder)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanGenerationStatusDidChange)) { notification in
            guard let status = notification.object as? RunSmartPlanGenerationStatus else { return }
            showPlanGenerationNotice(status)
        }
        .task {
            guard !RunSmartScreenshotMode.isEnabled else { return }
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
            Analytics.trackTabViewed(tabName: newTab.rawValue)
        }
        .onChange(of: session.isAuthenticated) { _, isAuth in
            if isAuth, let userId = session.currentUserID {
                Analytics.identifyUser(userId: userId.uuidString)
            } else if !isAuth {
                Analytics.resetUser()
            }
        }
        .task(id: session.hasCompletedOnboarding) {
            guard !RunSmartScreenshotMode.isEnabled else { return }
            guard session.isAuthenticated, session.hasCompletedOnboarding else { return }
            await refreshReturnLoopReminders()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartPlanDidChange)) { _ in
            guard !RunSmartScreenshotMode.isEnabled else { return }
            Task { await refreshReturnLoopReminders() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .runSmartRunsDidChange)) { _ in
            guard !RunSmartScreenshotMode.isEnabled else { return }
            Task { await refreshReturnLoopReminders() }
        }
        .task(id: session.hasCompletedOnboarding) {
            guard !RunSmartScreenshotMode.isEnabled else { return }
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

    private func setupAnalyticsIfNeeded() {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
              !token.isEmpty,
              let host = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String
        else { return }
        Analytics.setup(projectToken: token, host: host)
        Analytics.trackAppLaunched()
    }
}

private struct RunSmartPlanNotice: Equatable {
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
            message = "Training data was saved. Open Training Data to retry the plan update."
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
