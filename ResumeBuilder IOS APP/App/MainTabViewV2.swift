import SwiftUI

struct MainTabViewV2: View {
    @State private var selectedTab: ResumlyTab = .score

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keep tabs alive so the shell feels instant while RunSmart data models are connected.
            Group {
                TodayView()
                    .opacity(selectedTab == .score ? 1 : 0)
                    .allowsHitTesting(selectedTab == .score)

                PlanView()
                    .opacity(selectedTab == .tailor ? 1 : 0)
                    .allowsHitTesting(selectedTab == .tailor)

                RunView()
                    .opacity(selectedTab == .design ? 1 : 0)
                    .allowsHitTesting(selectedTab == .design)

                ReportView()
                    .opacity(selectedTab == .track ? 1 : 0)
                    .allowsHitTesting(selectedTab == .track)

                ProfileViewV2()
                    .opacity(selectedTab == .profile ? 1 : 0)
                    .allowsHitTesting(selectedTab == .profile)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ResumlyTabBar(selection: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .tint(Theme.accent)
    }
}

#Preview {
    MainTabViewV2()
        .environment(AppState())
}
