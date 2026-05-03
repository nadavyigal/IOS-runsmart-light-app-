import Foundation

struct ReceiptVerifier {
    private let apiClient = APIClient()

    func verifyPurchase(productID: String, transactionID: String, token: String) async throws {
        _ = try await apiClient.postJSON(
            endpoint: .iapVerify,
            body: [
                "productId": productID,
                "appleTransactionId": transactionID,
            ],
            token: token
        ) as TailorResponse
    }
}
