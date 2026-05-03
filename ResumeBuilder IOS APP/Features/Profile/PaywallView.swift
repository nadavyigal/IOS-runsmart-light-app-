import SwiftUI

struct PaywallView: View {
    var body: some View {
        List {
            Section("Credit Packs") {
                Label("100 credits", systemImage: "creditcard")
                Label("500 credits", systemImage: "creditcard")
                Label("2500 credits", systemImage: "creditcard")
            }

            Section {
                Text("StoreKit wiring is scaffolded and intentionally left minimal in this pass.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Get Credits")
    }
}
