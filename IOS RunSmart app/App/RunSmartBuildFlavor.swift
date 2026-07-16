import Foundation

enum RunSmartAppVariant: Equatable {
    case production
    case adaptivePreview

    init(infoDictionary: [String: Any]) {
        let value = (infoDictionary["RUNSMART_APP_VARIANT"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = value == "adaptive" ? .adaptivePreview : .production
    }
}

enum RunSmartBuildFlavor {
    static var current: RunSmartAppVariant {
        RunSmartAppVariant(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    static var isAdaptivePreview: Bool {
        current == .adaptivePreview
    }

    static func requiresLocalDemoIsolation(for variant: RunSmartAppVariant) -> Bool {
        variant == .adaptivePreview
    }
}
