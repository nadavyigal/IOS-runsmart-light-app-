import Combine
import Foundation

// Coach Experience v2, story C7.14. UX spec A.5 (T5 states), A.6 (copy), G13 (athlete toggles).

/// Every string on both settings screens. Fixed by the spec; names go through `BidiText.fill`.
nonisolated enum NotificationSettingsCopy {
    static let title = "Notifications"

    // A.6, T5.
    static let coachSection = "Notify me when"
    static let coachRunFinished = "An athlete finishes a run"
    static let coachPainFlag = "An athlete flags pain or something off"
    static let coachEveningSummary = "Evening summary at 20:00"

    // G13 athlete toggles. [ASSUMPTION copy, Sally light review] The section header is not in the spec.
    static let athleteSection = "Notify me about"
    static let athleteCoachNote = "Notes from {Coach}"
    static let athletePlanUpdates = "Plan updates"
    static let athleteBroadcasts = "Messages from {Coach}"

    static let quietSection = "Quiet hours"
    static let quietFrom = "From"
    static let quietTo = "To"
    static let quietFooter = "Pushes during quiet hours arrive when quiet hours end."
    static let quietSave = "Save quiet hours"
    /// [ASSUMPTION] v1.3 C7.14 AC5.
    static let quietEqualError = "Quiet hours need different start and end times"

    static let saveFailed = "Couldn't save. Try again"
    static let loadFailed = "Couldn't load your notification settings."
    static let tryAgain = "Try again"

    static let permissionDenied = "Notifications are off for RunSmart. Turn them on in Settings."
    static let openSettings = "Open Settings"
    static let turnOn = "Turn on notifications"

    static func label(for kind: NotificationPrefKind, coachName: String?) -> String {
        let name = coachName ?? "your coach"
        switch kind {
        case .coachRunFinished: return coachRunFinished
        case .coachPainFlag: return coachPainFlag
        case .coachEveningSummary: return coachEveningSummary
        case .athleteCoachNote: return BidiText.fill(athleteCoachNote, ["Coach": name])
        case .athletePlanUpdates: return athletePlanUpdates
        case .athleteBroadcasts: return BidiText.fill(athleteBroadcasts, ["Coach": name])
        }
    }

    static func sectionTitle(for audience: NotificationSettingsAudience) -> String {
        switch audience {
        case .coach: coachSection
        case .athlete: athleteSection
        }
    }

    /// "Quiet hours from" for VoiceOver on a time picker row. The picker adds the time as its value.
    static func quietAccessibility(_ label: String) -> String {
        "Quiet hours \(label.lowercased())"
    }
}

/// State of one settings screen. With Coach v2 off it holds nothing and calls nothing.
@MainActor
final class NotificationSettingsModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    /// The one save in flight. Its toggles show the requested value until the server answers.
    enum Pending: Equatable {
        case toggle(NotificationPrefKind, Bool)
        case quietHours
    }

    let audience: NotificationSettingsAudience

    @Published private(set) var loadState: LoadState = .idle
    /// The last row the server confirmed. Toggles revert to it on failure.
    @Published private(set) var prefs: NotificationPrefs?
    /// Nil until the first system read.
    @Published private(set) var permission: NotificationPermissionStatus?
    @Published private(set) var pending: Pending?
    @Published private(set) var saveFailed = false
    @Published private(set) var isTurningOn = false
    @Published var quietFrom: QuietTime = .defaultStart
    @Published var quietTo: QuietTime = .defaultEnd

    private let store: any NotificationPrefsStore
    private let permissionFlow: any NotificationPermissionFlow
    private let analytics: () -> any AnalyticsTracking
    private let timeZoneIdentifier: () -> String
    private var v2Enabled = false

    init(
        audience: NotificationSettingsAudience,
        store: any NotificationPrefsStore = SupabaseNotificationPrefsStore(),
        permissionFlow: any NotificationPermissionFlow = SystemNotificationPermissionFlow(),
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared },
        timeZoneIdentifier: @escaping () -> String = { TimeZone.current.identifier }
    ) {
        self.audience = audience
        self.store = store
        self.permissionFlow = permissionFlow
        self.analytics = analytics
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    nonisolated deinit {}

    // MARK: Derived

    var isSaving: Bool { pending != nil }
    var controlsDisabled: Bool { isSaving || loadState != .loaded }
    var coachName: String? {
        if case .athlete(let name) = audience { return name }
        return nil
    }

    func isOn(_ kind: NotificationPrefKind) -> Bool {
        if case .toggle(let pendingKind, let value)? = pending, pendingKind == kind { return value }
        return prefs?.isOn(kind) ?? true
    }

    func isSavingToggle(_ kind: NotificationPrefKind) -> Bool {
        if case .toggle(let pendingKind, _)? = pending { return pendingKind == kind }
        return false
    }

    /// AC5: the same time twice is never saved.
    var quietHoursError: String? {
        quietFrom == quietTo ? NotificationSettingsCopy.quietEqualError : nil
    }

    var canSaveQuietHours: Bool {
        guard let prefs, loadState == .loaded, !isSaving, quietFrom != quietTo else { return false }
        return quietFrom != prefs.quietStart || quietTo != prefs.quietEnd
    }

    // MARK: Load

    /// Call from the screen's `.task(id:)`. `v2Enabled == false` clears the screen and makes no call.
    func load(v2Enabled enabled: Bool) async {
        v2Enabled = enabled
        guard enabled else {
            reset()
            return
        }
        // One read per screen. A loaded screen keeps its state; "Try again" runs from `.failed`.
        guard loadState == .idle || loadState == .failed else { return }
        loadState = .loading
        saveFailed = false
        let status = await permissionFlow.status()
        guard v2Enabled else { return }
        permission = status
        do {
            let row = try await store.load(timeZone: timeZoneIdentifier())
            guard v2Enabled else { return }
            apply(row)
            loadState = .loaded
        } catch {
            guard v2Enabled else { return }
            if !(error is CancellationError) { print("[NotificationSettings] load failed:", error) }
            loadState = prefs == nil ? .failed : .loaded
        }
    }

    /// Back from system Settings: the user may have changed the permission there.
    func refreshPermission() async {
        guard v2Enabled else { return }
        let status = await permissionFlow.status()
        guard v2Enabled else { return }
        permission = status
    }

    // MARK: Save

    func setToggle(_ kind: NotificationPrefKind, to enabled: Bool) async {
        guard v2Enabled, loadState == .loaded, !isSaving, prefs?.isOn(kind) != enabled else { return }
        pending = .toggle(kind, enabled)
        saveFailed = false
        do {
            let row = try await store.update(.toggle(kind, enabled))
            guard v2Enabled else { return }
            apply(row, keepingQuietDraft: true)
            CoachV2Analytics.track(.notificationPrefChanged(kind: kind, enabled: enabled), to: analytics())
        } catch {
            guard v2Enabled else { return }
            if !(error is CancellationError) { print("[NotificationSettings] save failed:", error) }
            // The toggle reverts: `isOn` falls back to the last confirmed row.
            saveFailed = true
        }
        if v2Enabled { pending = nil }
    }

    func saveQuietHours() async {
        guard v2Enabled, canSaveQuietHours else { return }
        pending = .quietHours
        saveFailed = false
        do {
            apply(try await store.update(.quietHours(start: quietFrom, end: quietTo)))
        } catch {
            guard v2Enabled else { return }
            if !(error is CancellationError) { print("[NotificationSettings] quiet hours save failed:", error) }
            // The chosen times stay in the pickers so Save can run again.
            saveFailed = true
        }
        if v2Enabled { pending = nil }
    }

    // MARK: Permission

    /// "Turn on notifications": the T6/P10 flow, never the raw system prompt.
    func turnOnNotifications() async {
        guard v2Enabled, !isTurningOn, permission == .notDetermined else { return }
        isTurningOn = true
        let status = await permissionFlow.turnOn(for: audience)
        guard v2Enabled else { return }
        permission = status
        isTurningOn = false
    }

    // MARK: Internals

    private func apply(_ row: NotificationPrefs, keepingQuietDraft: Bool = false) {
        prefs = row
        if !keepingQuietDraft {
            quietFrom = row.quietStart
            quietTo = row.quietEnd
        }
    }

    private func reset() {
        loadState = .idle
        prefs = nil
        permission = nil
        pending = nil
        saveFailed = false
        isTurningOn = false
    }
}
