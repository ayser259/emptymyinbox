//
//  OnboardingView.swift
//  ProjectJade
//
//  Simple welcome screen (optional - can be skipped)
//

import SwiftUI
import ProjectJadeShared

struct OnboardingView: View {
    @EnvironmentObject private var appearanceSettings: AppearanceSettingsStore

    var body: some View {
        VStack(spacing: AppTheme.spacingXLarge) {
            Spacer()
            
            BrandedLogoView(size: 80)
            
            Text("Welcome to \(appearanceSettings.resolvedDisplayName)")
                .font(AppTheme.title)
                .primaryText()
            
            Text("Manage your Gmail inbox and reach inbox zero")
                .font(AppTheme.body)
                .secondaryText()
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingMedium)
            
            Spacer()
            
            Text("Get Started")
                .font(AppTheme.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppTheme.accent)
                .cornerRadius(AppTheme.cornerRadiusMedium)
                .padding(.horizontal, AppTheme.spacingMedium)
            
            Spacer()
        }
        .padding(AppTheme.spacingXLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .primaryBackground()
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AuthManager())
}

