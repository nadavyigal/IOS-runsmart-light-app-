import SwiftUI

extension Font {
    static let displayXL = Font.system(size: 56, weight: .black, design: .rounded)
    static let displayLG = Font.system(size: 42, weight: .bold, design: .default)
    static let displayMD = Font.system(size: 34, weight: .bold, design: .default)

    static let headingLG = Font.system(size: 24, weight: .semibold, design: .default)
    static let headingMD = Font.system(size: 20, weight: .semibold, design: .default)

    static let bodyLG = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyMD = Font.system(size: 15, weight: .regular, design: .default)

    static let labelLG = Font.system(size: 13, weight: .heavy, design: .default)
    static let labelSM = Font.system(size: 11, weight: .bold, design: .default)

    static let metric = Font.system(size: 28, weight: .semibold, design: .monospaced)
    static let metricLG = Font.system(size: 42, weight: .semibold, design: .monospaced)
    static let metricSM = Font.system(size: 17, weight: .medium, design: .monospaced)
    static let metricXS = Font.system(size: 12, weight: .medium, design: .monospaced)

    static let buttonLabel = Font.system(size: 16, weight: .bold, design: .default)
}

extension View {
    func displayTightTracking(_ value: CGFloat = -1.68) -> some View {
        tracking(value)
    }

    func runSmartSectionLabelTracking(_ value: CGFloat = 1.5) -> some View {
        tracking(value)
    }
}
