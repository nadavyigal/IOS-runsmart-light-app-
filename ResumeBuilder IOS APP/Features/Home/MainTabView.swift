import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ScoreView(viewModel: ScoreViewModel())
                .tabItem {
                    Label("Score", systemImage: "gauge.medium")
                }

            TailorView(viewModel: TailorViewModel())
                .tabItem {
                    Label("Tailor", systemImage: "wand.and.stars")
                }

            ApplicationsListView(viewModel: ApplicationsViewModel())
                .tabItem {
                    Label("Track", systemImage: "tray.full")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
