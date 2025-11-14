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
    @State private var handleURL: URL?
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            rootView
            .environmentObject(authManager)
            .preferredColorScheme(.dark) // Force dark mode
            .background(AppTheme.primaryBackground)
            .task {
                // Load user on app start
                await authManager.loadUser()
            }
            .onOpenURL { url in
                handleURL = url
                handleIncomingURL(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    NotificationCenter.default.post(name: .appShouldRefreshData, object: nil)
                }
            }
            .onChange(of: authManager.sessionState) { _, newState in
                if newState == .authenticated {
                    NotificationCenter.default.post(name: .appShouldRefreshData, object: nil)
                }
            }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        // Handle OAuth callback
        if url.scheme == "emptymyinbox" {
            if url.host == "account_connected" || url.query?.contains("account_connected=true") == true {
                // Post notification to refresh accounts
                NotificationCenter.default.post(name: NSNotification.Name("AccountConnected"), object: nil)
            }
        }
    }
    
    @ViewBuilder
    private var rootView: some View {
        switch authManager.sessionState {
        case .checking:
            SplashView()
        case .authenticated:
            mainAppView
        case .offline(let message):
            mainAppView
                .overlay(alignment: .top) {
                    OfflineBanner(message: message) {
                        Task {
                            await authManager.loadUser()
                        }
                    }
                }
        case .needsLogin:
            LoginView()
        }
    }
    
    @ViewBuilder
    private var mainAppView: some View {
        // Check if user needs onboarding
        let state = authManager.currentUser?.state ?? ""
        let zipCode = authManager.currentUser?.zip_code ?? ""
        let needsOnboarding = state.isEmpty && zipCode.isEmpty
        
        if needsOnboarding {
            OnboardingView()
        } else {
            DashboardView()
        }
    }
}

extension Notification.Name {
    static let appShouldRefreshData = Notification.Name("AppShouldRefreshData")
}

struct SplashView: View {
    var body: some View {
        ZStack {
            AppTheme.primaryBackground.ignoresSafeArea()
            VStack(spacing: AppTheme.spacingMedium) {
                LogoView(size: 64)
                Text("Loading your inbox…")
                    .font(AppTheme.body)
                    .primaryText()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
            }
        }
    }
}

struct OfflineBanner: View {
    var message: String?
    var retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.spacingSmall) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundColor(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Working offline")
                        .font(AppTheme.subheadline)
                        .primaryText()
                    if let message = message {
                        Text(message)
                            .font(AppTheme.caption)
                            .secondaryText()
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Retry") {
                    retryAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .padding(AppTheme.spacingMedium)
            .background(AppTheme.secondaryBackground.opacity(0.95))
            Divider()
                .background(AppTheme.accent.opacity(0.5))
        }
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
    }
}
