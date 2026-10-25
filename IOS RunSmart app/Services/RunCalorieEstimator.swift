import Foundation

/// Net active energy for level running, using the horizontal term of the ACSM
/// running equation: 0.2 mL O₂/kg/m × 5 kcal/L = 1 kcal/kg/km. Resting energy
/// and GPS elevation are excluded; this is an estimate, not a measured value.
enum RunCalorieEstimator {
    nonisolated static func activeKilocalories(distanceMeters: Double, weightKg: Double?) -> Double? {
        guard distanceMeters.isFinite, distanceMeters >= 0,
              let weightKg, weightKg.isFinite, weightKg > 0 else { return nil }
        let energy = distanceMeters / 1_000 * weightKg
        return energy.isFinite ? energy : nil
    }
}
