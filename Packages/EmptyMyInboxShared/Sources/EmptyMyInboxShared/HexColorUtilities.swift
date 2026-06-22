import Foundation
import SwiftUI

/// Validates and normalizes user-entered hex color strings.
public enum HexColorUtilities {
    public static let hexPattern = #"^#?[0-9A-Fa-f]{3}([0-9A-Fa-f]{3})?([0-9A-Fa-f]{2})?$"#

    /// Returns a normalized 6-digit hex string with `#` prefix, or `nil` if invalid.
    public static func normalizedHex(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let regex = try? NSRegularExpression(pattern: hexPattern),
              regex.firstMatch(in: trimmed, range: range) != nil else {
            return nil
        }

        var hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        switch hex.count {
        case 3:
            hex = hex.map { String(repeating: $0, count: 2) }.joined()
        case 8:
            hex = String(hex.prefix(6))
        case 6:
            break
        default:
            return nil
        }

        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#\(hex.uppercased())"
    }

    public static func isValid(_ input: String) -> Bool {
        normalizedHex(input) != nil
    }

    public static func color(from input: String, fallback: Color = .black) -> Color {
        guard let normalized = normalizedHex(input) else { return fallback }
        return Color(hex: normalized)
    }
}
