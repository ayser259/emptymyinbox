//
//  ButtonStyles.swift
//  emptyMyInbox
//
//  Custom button styles following the app theme
//

import SwiftUI

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.headline)
            .foregroundColor(AppTheme.primaryText)
            .padding(.horizontal, AppTheme.spacingMedium)
            .padding(.vertical, AppTheme.spacingUnit)
            .background(
                configuration.isPressed
                    ? AppTheme.accentPressed
                    : AppTheme.accent
            )
            .cornerRadius(AppTheme.cornerRadiusMedium)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.headline)
            .foregroundColor(AppTheme.accent)
            .padding(.horizontal, AppTheme.spacingMedium)
            .padding(.vertical, AppTheme.spacingUnit)
            .background(
                configuration.isPressed
                    ? AppTheme.accentMuted
                    : AppTheme.secondaryBackground
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.accent, lineWidth: 1.5)
            )
            .cornerRadius(AppTheme.cornerRadiusMedium)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Text Button Style

struct TextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.headline)
            .foregroundColor(
                configuration.isPressed
                    ? AppTheme.accentPressed
                    : AppTheme.accent
            )
            .padding(.horizontal, AppTheme.spacingUnit)
            .padding(.vertical, AppTheme.spacingSmall)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Icon Button Style

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(
                configuration.isPressed
                    ? AppTheme.accentPressed
                    : AppTheme.accent
            )
            .padding(AppTheme.spacingUnit)
            .background(
                configuration.isPressed
                    ? AppTheme.accentMuted
                    : Color.clear
            )
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extension for Easy Application

extension View {
    func primaryButton() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
    }
    
    func secondaryButton() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }
    
    func textButton() -> some View {
        self.buttonStyle(TextButtonStyle())
    }
    
    func iconButton() -> some View {
        self.buttonStyle(IconButtonStyle())
    }
}





