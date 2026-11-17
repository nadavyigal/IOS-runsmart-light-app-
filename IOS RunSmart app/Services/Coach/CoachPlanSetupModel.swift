import Combine
import Foundation

/// Coach tab gate for Plan Mode (C2), Group Plan Settings (C3) and the invite (C4).
/// Plan Mode stays unlocked until `set_plan_mode` succeeds. The invite stays hidden
/// until a mode is saved and, for a Group Plan, settings are saved.
@MainActor
final class CoachPlanSetupModel: ObservableObject {
    @Published private(set) var didLoad = false
    @Published private(set) var loadFailed = false
    @Published private(set) var mode: CoachPlanMode?
    @Published var pendingMode: CoachPlanMode?
    @Published private(set) var groupPlan: GroupPlanSettings?
    @Published var isEditingSettings = false
    @Published private(set) var choiceError: String?
    @Published private(set) var isSavingChoice = false
    @Published private(set) var settingsError: String?
    @Published private(set) var savedMessage: String?
    @Published private(set) var isSavingSettings = false

    private let repository: any CoachPlanRepository

    init(repository: any CoachPlanRepository) {
        self.repository = repository
    }

    var canChangeMode: Bool { mode == nil }
    var showsLockedMode: Bool { didLoad && mode != nil }
    var lockedCaption: String { GroupPlanRules.lockedCaption }

    /// Hard gate: no code, link, or share until this is true.
    var showsInvite: Bool {
        guard didLoad, let mode else { return false }
        switch mode {
        case .individual: return true
        case .group: return groupPlan != nil
        }
    }

    var showsGroupForm: Bool {
        mode == .group && (groupPlan == nil || isEditingSettings)
    }

    var showsGroupMenu: Bool {
        mode == .group && groupPlan != nil
    }

    func load() async {
        loadFailed = false
        do {
            let setup = try await repository.loadPlanSetup()
            guard !Task.isCancelled else { return }
            mode = setup.mode
            groupPlan = setup.groupPlan
            didLoad = true
        } catch is CancellationError {
            return
        } catch {
            print("[CoachPlanSetup] load failed:", error)
            loadFailed = true
        }
    }

    func confirmChoice() async {
        guard canChangeMode, let pendingMode, !isSavingChoice else { return }
        isSavingChoice = true
        choiceError = nil
        do {
            try await repository.setPlanMode(pendingMode)
            mode = pendingMode
            if pendingMode == .group { isEditingSettings = true }
        } catch is CancellationError {
            return
        } catch {
            print("[CoachPlanSetup] set_plan_mode failed:", error)
            choiceError = GroupPlanRules.choiceFailedMessage
        }
        isSavingChoice = false
    }

    func saveSettings(_ settings: GroupPlanSettings, today: Date = Date(), calendar: Calendar = .current) async {
        if let notice = GroupPlanRules.dateNotice(
            raceDate: settings.raceDate,
            targetDistance: settings.targetDistance,
            today: today,
            calendar: calendar
        ), notice.blocksSave {
            return
        }
        guard !isSavingSettings else { return }
        isSavingSettings = true
        settingsError = nil
        do {
            try await repository.saveGroupPlan(settings)
            groupPlan = settings
            savedMessage = GroupPlanRules.savedMessage
            isEditingSettings = false
        } catch is CancellationError {
            return
        } catch {
            print("[CoachPlanSetup] save_group_plan_settings failed:", error)
            settingsError = GroupPlanRules.settingsFailedMessage
        }
        isSavingSettings = false
    }

    func openGroupSettings() {
        guard showsGroupMenu else { return }
        savedMessage = nil
        settingsError = nil
        isEditingSettings = true
    }
}
