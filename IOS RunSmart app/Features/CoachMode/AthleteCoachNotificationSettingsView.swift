import SwiftUI

/// My coach → "Notifications" (C7.14 AC2, G13). Toggles for notes, plan updates and messages from the
/// coach, plus quiet hours. `MyCoachView` offers it only to a linked v2 athlete; a solo athlete has no
/// coach and so no such screen (AC7). With Coach v2 off it renders nothing and calls no server function.
struct AthleteCoachNotificationSettingsView: View {
    @EnvironmentObject private var coachV2Gate: CoachV2Gate
    @StateObject private var model: NotificationSettingsModel
    @Environment(\.dismiss) private var dismiss

    init(coachName: String) {
        _model = StateObject(wrappedValue: NotificationSettingsModel(audience: .athlete(coachName: coachName)))
    }

    /// Fixture and test entry: a model with a fake store.
    init(model: NotificationSettingsModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NotificationSettingsScreen(model: model, v2Enabled: coachV2Gate.isEnabled) { dismiss() }
    }
}
