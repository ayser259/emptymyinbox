//
//  MacRootTabBar.swift
//  emptymyinboxMacApp
//

import SwiftUI

/// Primary window tabs with inline ⌘1–⌘3 keycaps (replaces toolbar segmented picker).
struct MacRootTabBar: View {
    @Binding var selection: MacRootTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MacRootTab.allCases) { tab in
                MacRootTabSegment(
                    tab: tab,
                    isSelected: selection == tab
                ) {
                    selection = tab
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Primary navigation")
    }
}

private struct MacRootTabSegment: View {
    let tab: MacRootTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                MacKeycapBadge(text: tab.shortcutDisplay, prominent: isSelected)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(tab.keyboardShortcutKey, modifiers: .command)
        .onHover { isHovered = $0 }
        .help("\(tab.title) (\(tab.shortcutDisplay))")
        .accessibilityLabel("\(tab.title), \(tab.shortcutDisplay)")
    }

    private var foreground: Color {
        if isSelected { return .black }
        return isHovered ? MacAppTheme.primaryText : MacAppTheme.secondaryText
    }

    private var background: Color {
        if isSelected { return MacAppTheme.accent }
        return isHovered ? Color.white.opacity(0.08) : .clear
    }
}
