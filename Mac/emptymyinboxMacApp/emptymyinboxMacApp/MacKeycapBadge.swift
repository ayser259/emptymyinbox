//
//  MacKeycapBadge.swift
//  emptymyinboxMacApp
//

import SwiftUI

/// Small monospace keycap label (Catch Up / reply composer style).
struct MacKeycapBadge: View {
    let text: String
    var prominent: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(foreground.opacity(0.28), lineWidth: 0.5)
            )
    }

    private var foreground: Color {
        prominent ? Color.black.opacity(0.65) : MacAppTheme.secondaryText
    }

    private var background: Color {
        prominent ? Color.black.opacity(0.08) : Color.white.opacity(0.06)
    }
}
