//
//  Theme.swift
//  emptyMyInbox
//
//  Theme and styling system for the app
//

import SwiftUI

/// App-wide theme configuration
struct AppTheme {
    // MARK: - Colors
    
    /// Primary background color (black)
    static let primaryBackground = Color.black
    
    /// Secondary background color (slightly lighter black for contrast)
    static let secondaryBackground = Color(hex: "#0a0a0a")
    
    /// Primary text color (white)
    static let primaryText = Color.white
    
    /// Secondary text color (slightly muted white)
    static let secondaryText = Color(hex: "#e0e0e0")
    
    /// Accent color for highlights, buttons, and interactive elements
    static let accent = Color(hex: "#f6ac0aff")
    
    /// Accent color with reduced opacity for subtle highlights
    static let accentMuted = Color(hex: "#f6ac0aff").opacity(0.3)
    
    /// Accent color for pressed states
    static let accentPressed = Color(hex: "#d99a08")
    
    // MARK: - Spacing
    
    /// Standard spacing unit (8pt)
    static let spacingUnit: CGFloat = 8
    
    /// Small spacing (4pt)
    static let spacingSmall: CGFloat = 4
    
    /// Medium spacing (16pt)
    static let spacingMedium: CGFloat = 16
    
    /// Large spacing (24pt)
    static let spacingLarge: CGFloat = 24
    
    /// Extra large spacing (32pt)
    static let spacingXLarge: CGFloat = 32
    
    // MARK: - Corner Radius
    
    /// Small corner radius (8pt)
    static let cornerRadiusSmall: CGFloat = 8
    
    /// Medium corner radius (12pt)
    static let cornerRadiusMedium: CGFloat = 12
    
    /// Large corner radius (16pt)
    static let cornerRadiusLarge: CGFloat = 16
    
    // MARK: - Typography
    
    /// Large title font style
    static let largeTitle: Font = .system(size: 34, weight: .bold, design: .default)
    
    /// Title font style
    static let title: Font = .system(size: 28, weight: .bold, design: .default)
    
    /// Title 2 font style
    static let title2: Font = .system(size: 22, weight: .bold, design: .default)
    
    /// Title 3 font style
    static let title3: Font = .system(size: 20, weight: .semibold, design: .default)
    
    /// Headline font style
    static let headline: Font = .system(size: 17, weight: .semibold, design: .default)
    
    /// Body font style
    static let body: Font = .system(size: 17, weight: .regular, design: .default)
    
    /// Callout font style
    static let callout: Font = .system(size: 16, weight: .regular, design: .default)
    
    /// Subheadline font style
    static let subheadline: Font = .system(size: 15, weight: .regular, design: .default)
    
    /// Footnote font style
    static let footnote: Font = .system(size: 13, weight: .regular, design: .default)
    
    /// Caption font style
    static let caption: Font = .system(size: 12, weight: .regular, design: .default)
    
    // MARK: - Shadows
    
    /// Standard shadow for elevated elements
    static let shadow: ShadowStyle = .init(
        color: .black.opacity(0.3),
        radius: 8,
        x: 0,
        y: 4
    )
    
    /// Light shadow for subtle elevation
    static let shadowLight: ShadowStyle = .init(
        color: .black.opacity(0.2),
        radius: 4,
        x: 0,
        y: 2
    )
}

// MARK: - Shadow Style Helper

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension View {
    func appShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    /// Initialize Color from hex string
    /// - Parameter hex: Hex color string (e.g., "#f6ac0aff" for RGBA or "#f6ac0a" for RGB)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // RGBA (32-bit) - Red, Green, Blue, Alpha
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

// MARK: - View Modifiers

extension View {
    /// Apply primary background color
    func primaryBackground() -> some View {
        self.background(AppTheme.primaryBackground)
    }
    
    /// Apply secondary background color
    func secondaryBackground() -> some View {
        self.background(AppTheme.secondaryBackground)
    }
    
    /// Apply primary text color
    func primaryText() -> some View {
        self.foregroundColor(AppTheme.primaryText)
    }
    
    /// Apply secondary text color
    func secondaryText() -> some View {
        self.foregroundColor(AppTheme.secondaryText)
    }
    
    /// Apply accent color
    func accentColor() -> some View {
        self.foregroundColor(AppTheme.accent)
    }
}

