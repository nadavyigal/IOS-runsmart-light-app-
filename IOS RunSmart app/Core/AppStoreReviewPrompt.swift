import StoreKit
import UIKit

enum AppStoreReviewPrompt {
    private static let promptedKey = "runsmart.appStoreReview.promptedAfterFirstRun"

    @MainActor
    static func requestAfterFirstRunIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: promptedKey) else { return }
        defaults.set(true, forKey: promptedKey)

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        SKStoreReviewController.requestReview(in: scene)
    }
}
