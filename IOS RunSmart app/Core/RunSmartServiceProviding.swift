import Foundation
import SwiftUI

protocol RunSmartServiceProviding: TodayProviding, PlanProviding, CoachChatting, ProfileProviding, RunLogging, RouteProviding, DeviceSyncing, HealthSyncing {}

extension MockRunSmartServices: RunSmartServiceProviding {}

private struct RunSmartServicesKey: EnvironmentKey {
    static let defaultValue: any RunSmartServiceProviding = SupabaseRunSmartServices.shared
}

extension EnvironmentValues {
    var runSmartServices: any RunSmartServiceProviding {
        get { self[RunSmartServicesKey.self] }
        set { self[RunSmartServicesKey.self] = newValue }
    }
}

private struct RunRecorderKey: EnvironmentKey {
    static let defaultValue = RunRecorder()
}

extension EnvironmentValues {
    var runRecorder: RunRecorder {
        get { self[RunRecorderKey.self] }
        set { self[RunRecorderKey.self] = newValue }
    }
}
