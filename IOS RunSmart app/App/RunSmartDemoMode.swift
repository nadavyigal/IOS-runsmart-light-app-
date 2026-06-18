import Foundation

enum RunSmartDemoMode {
    /// DEBUG-only simulator/demo recording mode.
    ///
    /// This must never become active in Release/TestFlight/App Store builds. It
    /// intentionally bypasses Apple Account, Sign in with Apple, Supabase auth,
    /// Garmin auth, HealthKit, production analytics, and destructive backend work.
    static var isEnabled: Bool {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        let env = ProcessInfo.processInfo.environment
        return args.contains("-RUNSMART_DEMO_MODE")
            || args.contains("-RUNSMART_SCREENSHOT_MODE")
            || env["DEMO_MODE"]?.lowercased() == "true"
            || env["DEMO_MODE"] == "1"
            || env["RUNSMART_DEMO_MODE"]?.lowercased() == "true"
            || env["RUNSMART_DEMO_MODE"] == "1"
            || env["RUNSMART_SCREENSHOT_MODE"] == "1"
#else
        return false
#endif
    }

    static var services: any RunSmartServiceProviding {
#if DEBUG
        isEnabled ? DemoRunSmartServices() : SupabaseRunSmartServices.shared
#else
        SupabaseRunSmartServices.shared
#endif
    }

#if DEBUG
    static let userID = UUID(uuidString: "D3B43D62-9D04-4F3F-9D8C-6E3C650A7B81")!
    static let email = "demo@runsmart.local"
    static let memberSince = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 28))
#endif
}
