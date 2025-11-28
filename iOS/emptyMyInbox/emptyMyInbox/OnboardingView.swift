//
//  OnboardingView.swift
//  emptyMyInbox
//
//  Simple welcome screen (optional - can be skipped)
//

import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: AppTheme.spacingXLarge) {
            Spacer()
            
            LogoView(size: 80)
            
            Text("Welcome to Empty My Inbox")
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

