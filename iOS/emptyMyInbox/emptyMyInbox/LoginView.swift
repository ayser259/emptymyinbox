//
//  LoginView.swift
//  emptyMyInbox
//
//  Login view with Google Sign-In
//

import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: AppTheme.spacingLarge) {
            // Logo
            LogoView(size: 80)
            
            Text("Welcome to Empty My Inbox")
                .font(AppTheme.title)
                .primaryText()
            
            Text("Sign in with your Google account to get started")
                .font(AppTheme.body)
                .secondaryText()
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacingMedium)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(AppTheme.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal, AppTheme.spacingMedium)
            }
            
            Button {
                Task {
                    await handleSignIn()
                }
            } label: {
                HStack {
                if authManager.isLoading {
                    ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                        Image(systemName: "envelope.fill")
                        Text("Sign in with Google")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .primaryButton()
            .disabled(authManager.isLoading)
            .padding(.horizontal, AppTheme.spacingMedium)
            .padding(.top, AppTheme.spacingLarge)
        }
        .padding(AppTheme.spacingXLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .primaryBackground()
    }
    
    private func handleSignIn() async {
        errorMessage = ""
        do {
            try await authManager.signInWithGoogle()
        } catch {
            await MainActor.run {
            errorMessage = error.localizedDescription
        }
    }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

