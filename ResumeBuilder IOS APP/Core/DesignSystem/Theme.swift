import SwiftUI

// MARK: - Resumely Brand Palette
// Source: design-assets/Brand_Reference.png
// Primary bg:    #050814  →  r:0.020  g:0.031  b:0.078
// Card bg:       #0D1224  →  r:0.051  g:0.071  b:0.141
// Accent violet: #6C63FF  →  r:0.424  g:0.388  b:1.000
// Accent blue:   #4EA8FF  →  r:0.306  g:0.659  b:1.000
// Accent cyan:   #40E0D0  →  r:0.251  g:0.878  b:0.816

enum Theme {

    // MARK: Backgrounds
    /// Near-black deep navy — primary app background
    static let bgPrimary   = Color(red: 0.020, green: 0.031, blue: 0.078)
    /// Dark card surface
    static let bgCard      = Color(red: 0.051, green: 0.071, blue: 0.141)
    /// Light surface — forms, sheets (system-adaptive)
    static let canvas      = Color(uiColor: .systemBackground)

    // MARK: Accents
    /// Blue-violet — buttons, highlights, progress rings
    static let accent      = Color(red: 0.424, green: 0.388, blue: 1.000)
    /// Bright blue — secondary highlights, links, score badges
    static let accentBlue  = Color(red: 0.306, green: 0.659, blue: 1.000)
    /// Cyan — optional tertiary accent, export/success states
    static let accentCyan  = Color(red: 0.251, green: 0.878, blue: 0.816)

    // MARK: Text
    static let textPrimary    = Color.white
    static let textSecondary  = Color.white.opacity(0.65)
    static let textTertiary   = Color.white.opacity(0.40)

    // MARK: Semantic
    /// Legacy alias — maps to bgPrimary for backward compatibility
    static let primary     = bgPrimary

    // MARK: Gradients
    static let brandGradient = LinearGradient(
        colors: [accent, accentBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let bgGradient = LinearGradient(
        colors: [bgPrimary, bgCard],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Corner Radii
    static let radiusCard:   CGFloat = 16
    static let radiusButton: CGFloat = 12
    static let radiusBadge:  CGFloat = 10
}
