import Foundation

enum ExternalURLs {
    /// Country-neutral App Store URL; opens the installed App Store on iPhone.
    static let appStore = URL(string: "https://apps.apple.com/app/id6768297840")!
    /// Coach Mode invite links are `{inviteBase}/join/{CODE}`. Story 1.4 makes this host open the app.
    static let inviteBase = URL(string: "https://www.runsmart-ai.com")!
    static let marketing = URL(string: "https://www.runsmart-ai.com")!
    static let support = URL(string: "https://www.runsmart-ai.com/support")!
    static let privacy = URL(string: "https://www.runsmart-ai.com/privacy")!
    static let terms = URL(string: "https://www.runsmart-ai.com/terms")!
    static let accountDeletion = URL(string: "https://www.runsmart-ai.com/account-deletion")!
}
