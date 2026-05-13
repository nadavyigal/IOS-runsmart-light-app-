import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum RunSmartMotion {
    static let cardSpring = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let tabSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)
    static let gentlePulse = Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)
    static let counterEase = Animation.easeOut(duration: 0.55)
}

enum RunSmartHaptics {
    static func light() {
        impact(.light)
    }

    static func medium() {
        impact(.medium)
    }

    static func success() {
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
    }

    private static func impact(_ style: HapticStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style.uiKitStyle).impactOccurred()
#endif
    }
}

enum HapticStyle {
    case light
    case medium

#if canImport(UIKit)
    var uiKitStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .medium: return .medium
        }
    }
#endif
}

struct RunSmartPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    var scale: CGFloat = 1.02

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : RunSmartMotion.gentlePulse, value: isPulsing)
            .onAppear {
                guard !reduceMotion else { return }
                isPulsing = true
            }
    }
}

struct RunSmartStaggeredAppearModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    var index: Int

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 20)
            .onAppear {
                let delay = reduceMotion ? 0 : Double(index) * 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(RunSmartMotion.cardSpring) {
                        isVisible = true
                    }
                }
            }
    }
}

extension View {
    func runSmartPulse(scale: CGFloat = 1.02) -> some View {
        modifier(RunSmartPulseModifier(scale: scale))
    }

    func runSmartStaggeredAppear(index: Int) -> some View {
        modifier(RunSmartStaggeredAppearModifier(index: index))
    }
}
