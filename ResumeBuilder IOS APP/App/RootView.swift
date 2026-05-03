import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView(viewModel: OnboardingViewModel(appState: appState))
            }
        }
        .task {
            if appState.isAuthenticated {
                await appState.refreshCredits()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
