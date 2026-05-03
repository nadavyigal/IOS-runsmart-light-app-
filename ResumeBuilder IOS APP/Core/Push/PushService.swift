import Foundation
import UserNotifications

@MainActor
final class PushService: NSObject {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }
}
