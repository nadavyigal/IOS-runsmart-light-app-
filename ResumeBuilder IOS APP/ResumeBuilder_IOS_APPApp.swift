import SwiftUI

@main
struct ResumeBuilder_IOS_APPApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    appState.bootstrap()
                }
                .onOpenURL { url in
                    appState.handleIncomingURL(url)
                }
        }
    }
}
