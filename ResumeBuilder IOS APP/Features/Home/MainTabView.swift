import SwiftUI

struct MainTabView: View {
    @State private var selection: ResumlyTab = .score

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content — all views stay alive to preserve state
            Group {
                ScoreView(viewModel: ScoreViewModel())
                    .opacity(selection == .score ? 1 : 0)
                    .allowsHitTesting(selection == .score)

                TailorView(viewModel: TailorViewModel())
                    .opacity(selection == .tailor ? 1 : 0)
                    .allowsHitTesting(selection == .tailor)

                DesignHubView()
                    .opacity(selection == .design ? 1 : 0)
                    .allowsHitTesting(selection == .design)

                ApplicationsListView(viewModel: ApplicationsViewModel())
                    .opacity(selection == .track ? 1 : 0)
                    .allowsHitTesting(selection == .track)

                ProfileView()
                    .opacity(selection == .profile ? 1 : 0)
                    .allowsHitTesting(selection == .profile)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom floating tab bar
            ResumlyTabBar(selection: $selection)
        }
        .ignoresSafeArea(edges: .bottom)
        .tint(Theme.accent)
    }
}
