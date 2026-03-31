//
//  ContextAccentPalette.swift
//  EmptyMyInboxShared
//

import SwiftUI

/// Preset accent colors for contexts (right-click / settings). Values are `#RRGGBB`.
public enum ContextAccentPalette {
    public struct NamedColor: Sendable, Identifiable, Equatable, Hashable {
        public var id: String { name }
        public let name: String
        public let hex: String

        public init(name: String, hex: String) {
            self.name = name
            self.hex = hex
        }
    }

    /// Default grey for unspecified / no accent.
    public static let defaultGreyHex = "#9E9E9E"

    public static let presets: [NamedColor] = [
        NamedColor(name: "Dark Grey", hex: "#424242"),
        NamedColor(name: "Dark Red", hex: "#B71C1C"),
        NamedColor(name: "Dark Orange", hex: "#E65100"),
        NamedColor(name: "Dark Yellow", hex: "#F9A825"),
        NamedColor(name: "Dark Green", hex: "#2E7D32"),
        NamedColor(name: "Dark Blue", hex: "#1565C0"),
        NamedColor(name: "Dark Indigo", hex: "#283593"),
        NamedColor(name: "Dark Violet", hex: "#6A1B9A"),
        NamedColor(name: "Light Grey", hex: "#BDBDBD"),
        NamedColor(name: "Light Red", hex: "#EF9A9A"),
        NamedColor(name: "Light Orange", hex: "#FFCC80"),
        NamedColor(name: "Light Yellow", hex: "#FFF59D"),
        NamedColor(name: "Light Green", hex: "#A5D6A7"),
        NamedColor(name: "Light Blue", hex: "#90CAF9"),
        NamedColor(name: "Light Indigo", hex: "#9FA8DA"),
        NamedColor(name: "Light Violet", hex: "#CE93D8")
    ]

    /// Normalize user hex input to `#RRGGBB` or nil if invalid.
    public static func normalizeHex(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let hex = t.hasPrefix("#") ? String(t.dropFirst()) : t
        guard hex.count == 6 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard hex.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return "#" + hex.uppercased()
    }
}
