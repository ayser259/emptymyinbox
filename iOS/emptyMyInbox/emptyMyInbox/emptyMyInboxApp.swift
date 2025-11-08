//
//  emptyMyInboxApp.swift
//  emptyMyInbox
//
//  Created by Ayser Choudhury on 11/7/25.
//

import SwiftUI

@main
struct emptyMyInboxApp: App {
    @StateObject private var authManager = AuthManager()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    // Check if user needs onboarding
                    // Show onboarding if both state and zip_code are nil or empty
                    let state = authManager.currentUser?.state ?? ""
                    let zipCode = authManager.currentUser?.zip_code ?? ""
                    let needsOnboarding = state.isEmpty && zipCode.isEmpty
                    
                    if needsOnboarding {
                        OnboardingView()
                    } else {
                        DashboardView()
                    }
                } else {
                    LoginView()
                }
            }
            .environmentObject(authManager)
            .preferredColorScheme(.dark) // Force dark mode
            .background(AppTheme.primaryBackground)
            .task {
                // Load user on app start
                await authManager.loadUser()
            }
        }
    }
}
