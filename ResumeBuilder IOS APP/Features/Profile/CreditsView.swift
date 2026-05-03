import SwiftUI

struct CreditsView: View {
    @Environment(AppState.self) private var appState
    @State private var transactions: [CreditTransaction] = []

    var body: some View {
        List {
            Section("Balance") {
                Text("\(appState.creditsBalance) credits")
                    .font(.title3.bold())
            }

            Section("Recent Activity") {
                ForEach(transactions) { transaction in
                    HStack {
                        Text(transaction.reason)
                        Spacer()
                        Text(transaction.delta >= 0 ? "+\(transaction.delta)" : "\(transaction.delta)")
                            .foregroundStyle(transaction.delta >= 0 ? .green : .secondary)
                    }
                }
            }
        }
        .task {
            await appState.refreshCredits()
            await loadTransactions()
        }
        .navigationTitle("Credits")
    }

    @MainActor
    private func loadTransactions() async {
        guard let token = appState.session?.accessToken else { return }
        do {
            let response: CreditsResponse = try await appState.apiClient.get(endpoint: .credits, token: token)
            transactions = response.transactions
        } catch {
            transactions = []
        }
    }
}
