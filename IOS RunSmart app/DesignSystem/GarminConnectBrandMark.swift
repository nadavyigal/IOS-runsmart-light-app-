import SwiftUI

/// Official Garmin Connect app tile for authentication / connection surfaces (GCDP screens 01-03).
/// Garmin's brand guidelines prohibit altering the official mark (no reshaping, recoloring, or
/// cropping) -- render at native shape only, no clipShape.
enum GarminConnectBrandMark {
    static func tile(size: CGFloat = 34) -> some View {
        Image("GarminConnectTile")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Garmin Connect")
    }

    static func headerTile(height: CGFloat = 58) -> some View {
        Image("GarminConnectTile")
            .resizable()
            .scaledToFit()
            .frame(width: height, height: height)
            .accessibilityLabel("Garmin Connect")
    }
}
