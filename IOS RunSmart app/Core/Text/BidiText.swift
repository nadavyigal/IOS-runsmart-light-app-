import Foundation
import SwiftUI

/// Mixed-direction text helpers (Coach Experience v2, C7.15, folded into C7.3).
///
/// The pilot UI is English, but coaches and athletes write in Hebrew too. Rules
/// (v1.3 section 3.9):
/// - Free text (notes, replies, flag notes) renders in its own paragraph direction,
///   taken from its first strong character.
/// - `{Coach}` / `{Athlete}` placeholders are filled with names wrapped in
///   FSI ... PDI (U+2068 ... U+2069), so a Hebrew name never reorders the English
///   punctuation around it.
/// - Length limits count Unicode code points, the unit of Postgres `char_length`, so a
///   text the app accepts is never rejected by a server `check`.
/// - Truncation never splits a grapheme cluster (emoji, flags, combining marks).
nonisolated enum BidiText {
    static let firstStrongIsolate: Character = "\u{2068}"
    static let popDirectionalIsolate: Character = "\u{2069}"

    /// Wraps `text` in FSI ... PDI. Isolates already inside are kept as they are.
    static func isolate(_ text: String) -> String {
        "\(firstStrongIsolate)\(text)\(popDirectionalIsolate)"
    }

    /// Replaces each `{Key}` in `template` with its value, isolated. Unknown keys stay.
    /// Never concatenate names into copy; fill a template with this instead.
    static func fill(_ template: String, _ values: [String: String]) -> String {
        values.reduce(template) { result, pair in
            result.replacingOccurrences(of: "{\(pair.key)}", with: isolate(pair.value))
        }
    }

    /// The paragraph direction of free text: from the first strong character, like the
    /// Unicode bidi algorithm's P2/P3. Nil when the text has no strong character
    /// (digits, emoji, punctuation only): the caller keeps the surrounding direction.
    static func paragraphDirection(_ text: String) -> LayoutDirection? {
        for scalar in text.unicodeScalars {
            if isRightToLeft(scalar) { return .rightToLeft }
            if isLeftToRight(scalar) { return .leftToRight }
        }
        return nil
    }

    /// Server-equivalent length: Postgres `char_length` counts code points.
    static func serverLength(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    /// True when `text` fits a server `char_length(...) <= limit` check.
    static func fits(_ text: String, limit: Int) -> Bool {
        serverLength(text) <= limit
    }

    /// Cuts `text` to at most `limit` code points without splitting a grapheme cluster.
    /// Appends "…" when it cut, and the ellipsis counts toward the limit.
    static func truncate(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard serverLength(text) > limit else { return text }
        let budget = limit - 1
        var kept = ""
        var used = 0
        for character in text {
            let size = character.unicodeScalars.count
            if used + size > budget { break }
            kept.append(character)
            used += size
        }
        return kept + "…"
    }

    // Strong right-to-left: Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Mandaic,
    // and their presentation forms. Explicit RLM / RLE / RLO / RLI count too.
    private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF:
            return true
        case 0x200F, 0x202B, 0x202E, 0x2067:
            return true
        default:
            return false
        }
    }

    // Strong left-to-right: letters outside the right-to-left blocks. Digits, emoji and
    // punctuation are weak or neutral, so they never decide the direction.
    private static func isLeftToRight(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 0x200E || scalar.value == 0x202A || scalar.value == 0x202D || scalar.value == 0x2066 {
            return true
        }
        return scalar.properties.isAlphabetic && !isRightToLeft(scalar)
    }
}

extension View {
    /// Lays out free text in its own paragraph direction, aligned to its leading edge.
    /// Text without a strong character keeps the surrounding direction.
    func naturalTextDirection(_ text: String) -> some View {
        modifier(NaturalTextDirection(direction: BidiText.paragraphDirection(text)))
    }
}

private struct NaturalTextDirection: ViewModifier {
    @Environment(\.layoutDirection) private var inherited
    let direction: LayoutDirection?

    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.leading)
            .environment(\.layoutDirection, direction ?? inherited)
    }
}
