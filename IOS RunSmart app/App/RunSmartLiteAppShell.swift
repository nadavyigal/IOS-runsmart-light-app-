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
    @State private var planNotice: RunSmartPlanNotice?
    @State private var planNoticeDismissTask: Task<Void, Never>?
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
                    case .report:  ReportTabView()
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
