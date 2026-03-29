//
//  MacTheme.swift
//  emptymyinboxMacApp
//
//  Matches iOS Theme.swift so the Mac app shares the same look (dark + gold accent).
//

import SwiftUI

enum MacAppTheme {
    static let primaryBackground = Color.black
    static let secondaryBackground = Color(hex: "#0a0a0a")
    static let primaryText = Color.white
    static let secondaryText = Color(hex: "#e0e0e0")
    static let accent = Color(hex: "#f6ac0a")
    static let cornerRadiusSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 16
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (r, g, b, a) = (int >> 24, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension View {
    func macPrimaryBackground() -> some View {
        background(MacAppTheme.primaryBackground)
    }
}
