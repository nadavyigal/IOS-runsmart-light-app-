import SwiftUI

/// T5. Coach tab → ⋯ → "Notifications" (C7.14 AC1). Shown as a sheet from `CoachTabView`.
/// With Coach v2 off it renders nothing and calls no server function.
struct CoachNotificationSettingsView: View {
    @EnvironmentObject private var coachV2Gate: CoachV2Gate
    @StateObject private var model: NotificationSettingsModel
    @Environment(\.dismiss) private var dismiss

    init() {
        _model = StateObject(wrappedValue: NotificationSettingsModel(audience: .coach))
    }

    /// Fixture and test entry: a model with a fake store.
    init(model: NotificationSettingsModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NotificationSettingsScreen(model: model, v2Enabled: coachV2Gate.isEnabled) { dismiss() }
    }
}
