import SwiftUI

/// Official Garmin Connect app tile for authentication / connection surfaces (GCDP screens 01–03).
enum GarminConnectBrandMark {
    static func tile(size: CGFloat = 34, cornerRadius: CGFloat = 8) -> some View {
        Image("GarminConnectTile")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel("Garmin Connect")
    }

    static func headerTile(height: CGFloat = 58) -> some View {
        Image("GarminConnectTile")
            .resizable()
            .scaledToFit()
            .frame(width: height, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("Garmin Connect")
    }
}
