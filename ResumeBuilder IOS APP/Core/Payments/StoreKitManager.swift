import Foundation
import Observation

@Observable
@MainActor
final class StoreKitManager {
    var availableProductIDs: [String] = ["credits_basic", "credits_saver", "credits_super"]

    func loadProducts() async {
        // StoreKit 2 fetch placeholder for MVP scaffolding.
    }

    func purchase(productID: String) async throws -> String {
        // Return a placeholder transaction id. Wire with StoreKit Transaction verification.
        return "tx_\(productID)_\(UUID().uuidString)"
    }
}
