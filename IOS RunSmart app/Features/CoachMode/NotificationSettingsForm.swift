import SwiftUI
import UIKit

// Coach Experience v2, story C7.14. The body both settings screens share (UX spec A.5, A.6, G13).

/// Toggles, quiet hours and the permission line. Holds no data of its own: read `model`.
struct NotificationSettingsContent: View {
    @ObservedObject var model: NotificationSettingsModel
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            permissionCard
            switch model.loadState {
            case .idle, .loading:
                ProgressView()
                    .tint(Color.accentPrimary)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .accessibilityLabel("Loading notification settings")
            case .failed:
                loadFailure
            case .loaded:
                togglesCard
                quietHoursCard
            }
            if model.saveFailed {
                Text(NotificationSettingsCopy.saveFailed)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentAmber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("notification-settings-save-failed")
            }
        }
    }

    // MARK: Permission

    @ViewBuilder
    private var permissionCard: some View {
        switch model.permission {
        case .denied?:
            ContentCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(NotificationSettingsCopy.permissionDenied)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(NotificationSettingsCopy.openSettings, action: onOpenSettings)
                        .buttonStyle(NeonButtonStyle())
                        .accessibilityIdentifier("notification-settings-open-settings")
                }
            }
        case .notDetermined?:
            Button {
                Task { await model.turnOnNotifications() }
            } label: {
                HStack(spacing: 8) {
                    if model.isTurningOn { ProgressView() }
                    Text(NotificationSettingsCopy.turnOn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(model.isTurningOn)
            .accessibilityIdentifier("notification-settings-turn-on")
        case .granted?, nil:
            EmptyView()
        }
    }

    // MARK: Toggles

    private var togglesCard: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(NotificationSettingsCopy.sectionTitle(for: model.audience))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(model.audience.kinds, id: \.self) { kind in
                    toggleRow(kind)
                }
            }
        }
    }

    private func toggleRow(_ kind: NotificationPrefKind) -> some View {
        let label = NotificationSettingsCopy.label(for: kind, coachName: model.coachName)
        return Toggle(isOn: Binding(
            get: { model.isOn(kind) },
            set: { value in Task { await model.setToggle(kind, to: value) } }
        )) {
            HStack(spacing: 8) {
                Text(verbatim: label)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.isSavingToggle(kind) {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
        }
        .tint(Color.accentPrimary)
        .disabled(model.controlsDisabled)
        .frame(minHeight: 44)
        .accessibilityLabel(label)
        .accessibilityHint(model.isSavingToggle(kind) ? "Saving" : "")
        .accessibilityIdentifier("notification-toggle-\(kind.rawValue)")
    }

    // MARK: Quiet hours

    private var quietHoursCard: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(NotificationSettingsCopy.quietSection)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                timeRow(NotificationSettingsCopy.quietFrom, time: $model.quietFrom)
                timeRow(NotificationSettingsCopy.quietTo, time: $model.quietTo)

                if let error = model.quietHoursError {
                    Text(error)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentAmber)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("notification-quiet-error")
                }

                Text(NotificationSettingsCopy.quietFooter)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await model.saveQuietHours() }
                } label: {
                    HStack(spacing: 8) {
                        if model.pending == .quietHours { ProgressView() }
                        Text(NotificationSettingsCopy.quietSave)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(!model.canSaveQuietHours)
                .accessibilityIdentifier("notification-quiet-save")
            }
        }
    }

    /// A 24-hour picker ("21:30", the house style). The value is a fixed UTC instant, so a daylight saving
    /// change on the device never moves the chosen time.
    private func timeRow(_ title: String, time: Binding<QuietTime>) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: { Date(timeIntervalSince1970: TimeInterval(time.wrappedValue.minutes * 60)) },
                set: { date in
                    let minutes = Int((date.timeIntervalSince1970 / 60).rounded())
                    time.wrappedValue = QuietTime(hour: 0, minute: minutes)
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .font(.body)
        .foregroundStyle(Color.textPrimary)
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .gmt)
        .environment(\.locale, Locale(identifier: "en_GB"))
        .disabled(model.controlsDisabled)
        .frame(minHeight: 44)
        .accessibilityLabel(NotificationSettingsCopy.quietAccessibility(title))
        .accessibilityIdentifier("notification-quiet-\(title.lowercased())")
    }

    // MARK: Load failure

    private var loadFailure: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(NotificationSettingsCopy.loadFailed)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(NotificationSettingsCopy.tryAgain) {
                    Task { await model.load(v2Enabled: true) }
                }
                .buttonStyle(NeonButtonStyle())
            }
        }
    }
}

/// One settings screen in its own navigation stack: title, Done, the system-Settings link and the
/// foreground permission re-read. `v2Enabled == false` renders nothing and calls nothing.
struct NotificationSettingsScreen: View {
    @ObservedObject var model: NotificationSettingsModel
    let v2Enabled: Bool
    var onDone: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if v2Enabled {
                NavigationStack {
                    ScrollView {
                        NotificationSettingsContent(model: model, onOpenSettings: Self.openSystemSettings)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                    }
                    .background(Color.surfaceBase)
                    .navigationTitle(NotificationSettingsCopy.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: onDone)
                        }
                    }
                }
            }
        }
        .task(id: v2Enabled) { await model.load(v2Enabled: v2Enabled) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshPermission() } }
        }
    }

    private static func openSystemSettings() {
        let urlString = UIApplication.openNotificationSettingsURLString
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
