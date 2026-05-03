import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Text(appState.session?.email ?? "Signed in")
                    Button(role: .destructive) {
                        appState.signOut()
                    } label: {
                        Text("Sign Out")
                    }
                }

                Section("Resume") {
                    Text("Master resume preview will appear here.")
                        .foregroundStyle(.secondary)
                }

                Section("Credits") {
                    NavigationLink("View Credits") {
                        CreditsView()
                    }

                    Button("Buy Credits") {
                        showPaywall = true
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showPaywall) {
                NavigationStack {
                    PaywallView()
                }
            }
        }
    }
}
