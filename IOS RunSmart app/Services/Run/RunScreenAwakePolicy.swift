#if canImport(UIKit)
import UIKit

/// Keeps the display awake while a run is actively recording (WP-38 S14a).
enum RunScreenAwakePolicy {
    static func setRecordingActive(_ isActive: Bool) {
        UIApplication.shared.isIdleTimerDisabled = isActive
    }
}
#endif
