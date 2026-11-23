import UIKit
@preconcurrency import UserNotifications

/// C7.10: the app had no delegate before. It exists for two things only:
/// - the APNs device-token callbacks, handed to `RemotePushRegistrar`;
/// - setting the notification-center delegate before launch finishes, so a tap that cold-launches
///   the app reaches `PushService` (Apple requires the delegate by the end of launch).
final class RunSmartAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushService.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await RemotePushRegistrar.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        RemotePushRegistrar.shared.didFailToRegister(error)
    }
}
