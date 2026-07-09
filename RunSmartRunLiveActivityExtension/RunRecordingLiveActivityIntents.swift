import AppIntents
import Foundation

struct PauseRunLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Run"
    static var description = IntentDescription("Toggles pause during a RunSmart recording.")

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .runSmartLiveActivityPauseResume, object: nil)
        return .result()
    }
}

struct FinishRunLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish Run"
    static var description = IntentDescription("Opens RunSmart to finish and save the current run.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .runSmartLiveActivityFinish, object: nil)
        return .result()
    }
}
