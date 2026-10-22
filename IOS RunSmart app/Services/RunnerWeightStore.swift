import Foundation
import Combine

/// Weight stays on device. Apple Health is read only after an explicit request
/// from the runner; an unavailable Health value falls back to their manual weight.
@MainActor
final class RunnerWeightStore: ObservableObject {
    static let shared = RunnerWeightStore()

    @Published private(set) var manualWeightKg: Double?
    @Published private(set) var healthWeightKg: Double?
    @Published private(set) var isReadingHealth = false
    private let defaults: UserDefaults
    private let manualKey = "runCalories.manualWeightKg"
    private let healthEnabledKey = "runCalories.healthWeightEnabled"
    private let setupOfferedKey = "runCalories.weightSetupOffered"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: manualKey)
        manualWeightKg = Self.validWeight(saved)
    }

    var weightKg: Double? { healthWeightKg ?? manualWeightKg }
    var shouldOfferWeightSetup: Bool {
        weightKg == nil && !defaults.bool(forKey: setupOfferedKey)
    }

    func markWeightSetupOffered() {
        defaults.set(true, forKey: setupOfferedKey)
    }

    var sourceLabel: String? {
        if healthWeightKg != nil { return "Apple Health" }
        if manualWeightKg != nil { return "Your weight" }
        return nil
    }

    @discardableResult
    func setManualWeightKg(_ value: Double) -> Bool {
        guard let value = Self.validWeight(value) else { return false }
        manualWeightKg = value
        defaults.set(value, forKey: manualKey)
        return true
    }

    func clearManualWeight() {
        manualWeightKg = nil
        defaults.removeObject(forKey: manualKey)
    }

    func updateHealthWeight(_ value: Double?) {
        healthWeightKg = value.flatMap(Self.validWeight)
    }

    func requestHealthWeight() async {
        guard !isReadingHealth else { return }
        isReadingHealth = true
        defaults.set(true, forKey: healthEnabledKey)
        updateHealthWeight(await HealthKitSyncService().readBodyMassKg(requestPermission: true))
        isReadingHealth = false
    }

    /// No system prompt. Call when preparing a run to refresh a previously enabled source.
    func refreshHealthWeightIfEnabled() async {
        guard defaults.bool(forKey: healthEnabledKey), !isReadingHealth else { return }
        isReadingHealth = true
        updateHealthWeight(await HealthKitSyncService().readBodyMassKg(requestPermission: false))
        isReadingHealth = false
    }

    func stopUsingHealthWeight() {
        defaults.set(false, forKey: healthEnabledKey)
        healthWeightKg = nil
    }

    private static func validWeight(_ value: Double) -> Double? {
        value.isFinite && value > 0 && value <= 1_000 ? value : nil
    }
}
