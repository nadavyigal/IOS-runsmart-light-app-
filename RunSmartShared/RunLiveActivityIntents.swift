import AppIntents
import Foundation

/// What a Live Activity button asks the app to do.
enum RunLiveActivityAction: Equatable {
    case pauseResume
    case finish
}

/// Hands Live Activity button taps to the app.
///
/// `LiveActivityIntent` runs in the app's process, so these intent types live in
/// `RunSmartShared` and compile into the app as well as the widget extension. The app shell
/// sets `handler` at launch; in the extension it stays nil and a tap does nothing.
@MainActor
final class RunLiveActivityActionRouter {
    static let shared = RunLiveActivityActionRouter()
    var handler: ((RunLiveActivityAction) -> Void)?

    func send(_ action: RunLiveActivityAction) {
        handler?(action)
    }
}

struct PauseRunLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Run"
    static var description = IntentDescription("Toggles pause during a RunSmart recording.")

    @MainActor
    func perform() async throws -> some IntentResult {
        RunLiveActivityActionRouter.shared.send(.pauseResume)
        return .result()
    }
}

struct FinishRunLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish Run"
    static var description = IntentDescription("Opens RunSmart to finish and save the current run.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        RunLiveActivityActionRouter.shared.send(.finish)
        return .result()
    }
}
