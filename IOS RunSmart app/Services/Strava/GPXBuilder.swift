import Foundation

/// Builds the GPX file sent to Strava. One `<trkseg>` per continuous stretch, so a pause is a gap
/// and not a straight line. Times are UTC ISO 8601; elevation is written only when it was recorded.
nonisolated enum GPXBuilder {
    static func gpx(name: String, startedAt: Date, segments: [[StravaTrackPoint]]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")

        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="RunSmart" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "  <metadata>",
            "    <name>\(escape(name))</name>",
            "    <time>\(formatter.string(from: startedAt))</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(escape(name))</name>",
            "    <type>running</type>"
        ]
        for segment in segments where !segment.isEmpty {
            lines.append("    <trkseg>")
            for point in segment {
                var element = "      <trkpt lat=\"\(coordinate(point.latitude))\" lon=\"\(coordinate(point.longitude))\">"
                if let elevation = point.elevation, elevation.isFinite {
                    element += "<ele>\(String(format: "%.1f", locale: posix, elevation))</ele>"
                }
                element += "<time>\(formatter.string(from: point.time))</time></trkpt>"
                lines.append(element)
            }
            lines.append("    </trkseg>")
        }
        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func gpx(for draft: StravaActivityDraft) -> String {
        gpx(name: draft.name, startedAt: draft.startedAt, segments: draft.segments)
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.7f", locale: posix, value)
    }

    /// Escapes the five XML special characters and drops characters XML 1.0 cannot hold.
    static func escape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\t", "\n", "\r": result.unicodeScalars.append(" ")
            default:
                let value = scalar.value
                let allowed = value >= 0x20 && value != 0x7F && !(0xD800...0xDFFF).contains(value) && value != 0xFFFE && value != 0xFFFF
                if allowed { result.unicodeScalars.append(scalar) }
            }
        }
        return result
    }
}
