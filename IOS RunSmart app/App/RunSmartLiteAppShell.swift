import SwiftUI
import Combine

enum RunSmartSheet: Identifiable {
    case coach(String)
    case secondary(SecondaryDestination)

    var id: String {
        switch self {
        case .coach(let context): "coach-\(context)"
        case .secondary(let dest): "secondary-\(dest.id)"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: RunSmartTab = AppRouter.initialTab()
    @Published var activeSheet: RunSmartSheet?
    @Published var plannedWorkout: WorkoutSummary?

    private static func initialTab() -> RunSmartTab {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-INITIAL_TAB"),
           args.indices.contains(idx + 1),
           let tab = RunSmartTab(rawValue: args[idx + 1]) {
            return tab
        }
#endif
        return .today
    }

    func openCoach(context: String) {
        activeSheet = .coach(context)
    }

    func open(_ destination: SecondaryDestination) {
        activeSheet = .secondary(destination)
    }

    func startRun(with workout: WorkoutSummary? = nil) {
        RunSmartHaptics.medium()
        plannedWorkout = workout
        activeSheet = nil
        selectedTab = .run
    }
}

struct RunSmartLiteAppShell: View {
    @StateObject private var router = AppRouter()
    @StateObject private var session = SupabaseSession()
    @StateObject private var recorder = RunRecorder()
    @State private var didPresentMorningCheckin = false
    @State private var isShowingLaunch = true
    private let services = SupabaseRunSmartServices.shared

    var body: some View {
        ZStack {
            RunSmartBackground(context: RunSmartBackgroundContext(tab: router.selectedTab))

            if session.isLoading {
                RunSmartLaunchView()
            } else if !session.isAuthenticated {
                SignInView()
                    .environmentObject(session)
            } else if !session.hasCompletedOnboarding {
                OnboardingView(initialProfile: session.onboardingProfile) { profile in
                    Task { await session.completeOnboarding(profile) }
                }
                .environmentObject(session)
            } else {
                Group {
                    switch router.selectedTab {
                    case .today:   TodayTabView()
                    case .plan:    PlanTabView()
                    case .run:     RunTabView()
                    case .profile: ProfileTabView()
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    CustomTabBar(selectedTab: $router.selectedTab)
                }
            }

            if isShowingLaunch {
                RunSmartLaunchView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environmentObject(router)
        .environmentObject(session)
        .environmentObject(recorder)
        .environment(\.runSmartServices, services)
        .environment(\.runRecorder, recorder)
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.32)) {
                isShowingLaunch = false
            }
        }
        .task(id: session.hasCompletedOnboarding) {
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
                CoachFlowView(context: context)
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
    }
}
