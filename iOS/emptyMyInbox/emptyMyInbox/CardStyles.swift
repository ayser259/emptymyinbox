//
//  CardStyles.swift
//  emptyMyInbox
//
//  Custom card and list item styles following the app theme
//

import SwiftUI

// MARK: - Card Style Modifier

struct CardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat
    
    init(cornerRadius: CGFloat = AppTheme.cornerRadiusMedium, padding: CGFloat = AppTheme.spacingMedium) {
        self.cornerRadius = cornerRadius
        self.padding = padding
    }
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.secondaryBackground)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - List Item Style Modifier

struct ListItemStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, AppTheme.spacingUnit)
            .padding(.horizontal, AppTheme.spacingMedium)
            .background(AppTheme.secondaryBackground)
    }
}

// MARK: - Elevated Card Style

struct ElevatedCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.spacingMedium)
            .background(AppTheme.secondaryBackground)
            .cornerRadius(AppTheme.cornerRadiusMedium)
            .appShadow(AppTheme.shadow)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply card styling with optional corner radius and padding
    func cardStyle(cornerRadius: CGFloat = AppTheme.cornerRadiusMedium, padding: CGFloat = AppTheme.spacingMedium) -> some View {
        self.modifier(CardStyle(cornerRadius: cornerRadius, padding: padding))
    }
    
    /// Apply list item styling
    func listItemStyle() -> some View {
        self.modifier(ListItemStyle())
    }
    
    /// Apply elevated card styling with shadow
    func elevatedCardStyle() -> some View {
        self.modifier(ElevatedCardStyle())
    }
}







