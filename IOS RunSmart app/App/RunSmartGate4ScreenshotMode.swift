#if DEBUG
import Foundation

/// DEBUG-only helpers for Gate 4 Garmin UX screenshots in Simulator (`-RUNSMART_DEMO_MODE`).
enum RunSmartGate4ScreenshotMode {
    static var garminDisconnected: Bool {
        ProcessInfo.processInfo.arguments.contains("-GATE4_GARMIN_DISCONNECTED")
            || ProcessInfo.processInfo.environment["RUNSMART_GARMIN_DISCONNECTED"] == "1"
    }

    static var initialSecondaryDestination: SecondaryDestination? {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-OPEN_SECONDARY"), args.indices.contains(idx + 1) {
            return parse(args[idx + 1])
        }
        if let raw = ProcessInfo.processInfo.environment["RUNSMART_OPEN_SECONDARY"] {
            return parse(raw)
        }
        return nil
    }

    private static func parse(_ raw: String) -> SecondaryDestination? {
        switch raw {
        case "connectedService:Garmin Connect", "garminConnect":
            return .connectedService("Garmin Connect")
        case "recoveryDashboard", "recovery":
            return .recoveryDashboard
        case "wellnessTrends":
            return .wellnessTrends
        case "addActivity":
            return .addActivity
        case "routeCreator":
            return .routeCreator
        case "routeSelector":
            return .routeSelector
        default:
            return nil
        }
    }
}
#endif
