import SwiftUI

enum RunSmartSheet: Identifiable {
    case coach(String)
    case secondary(String)

    var id: String {
        switch self {
        case .coach(let context): "coach-\(context)"
        case .secondary(let title): "secondary-\(title)"
        }
    }
}

struct RunSmartLiteAppShell: View {
    @State private var selectedTab: RunSmartTab = .today
    @State private var activeSheet: RunSmartSheet?
    private let services = MockRunSmartServices()

    var body: some View {
        ZStack(alignment: .bottom) {
            RunSmartBackground()

            Group {
                switch selectedTab {
                case .today:
                    TodayTabView(
                        services: services,
                        openCoach: { activeSheet = .coach("Today") },
                        openSecondary: { activeSheet = .secondary($0) },
                        startRun: { selectedTab = .run }
                    )
                case .plan:
                    PlanTabView(
                        services: services,
                        openCoach: { activeSheet = .coach("Plan") },
                        openSecondary: { activeSheet = .secondary($0) }
                    )
                case .run:
                    RunTabView(
                        services: services,
                        openCoach: { activeSheet = .coach("Run") },
                        openSecondary: { activeSheet = .secondary($0) }
                    )
                case .profile:
                    ProfileTabView(
                        services: services,
                        openCoach: { activeSheet = .coach("Profile") },
                        openSecondary: { activeSheet = .secondary($0) }
                    )
                }
            }
            .safeAreaPadding(.bottom, 94)

            CustomTabBar(selectedTab: $selectedTab)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .coach(let context):
                CoachFlowView(context: context)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .secondary(let title):
                SecondaryFlowView(title: title)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
