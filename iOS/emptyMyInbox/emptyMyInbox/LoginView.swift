//
//  LoginView.swift
//  emptyMyInbox
//
//  Login view with backend integration
//

import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var showSignup = false
    
    var body: some View {
        VStack(spacing: AppTheme.spacingLarge) {
            // Logo
            LogoView(size: 80)
            
            Text("Welcome Back")
                .font(AppTheme.title)
                .primaryText()
            
            Text("Sign in to continue to Empty My Inbox")
                .font(AppTheme.body)
                .secondaryText()
                .multilineTextAlignment(.center)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(AppTheme.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal, AppTheme.spacingMedium)
            }
            
            VStack(spacing: AppTheme.spacingMedium) {
                TextField("Username", text: $username)
                    .textFieldStyle(CustomTextFieldStyle())
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                
                SecureField("Password", text: $password)
                    .textFieldStyle(CustomTextFieldStyle())
            }
            .padding(.horizontal, AppTheme.spacingMedium)
            
            Button {
                Task {
                    await handleLogin()
                }
            } label: {
                if authManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primaryText))
                } else {
                    Text("Sign In")
                }
            }
            .primaryButton()
            .disabled(authManager.isLoading || username.isEmpty || password.isEmpty)
            .padding(.horizontal, AppTheme.spacingMedium)
            
            HStack {
                Text("Don't have an account?")
                    .font(AppTheme.body)
                    .secondaryText()
                
                Button("Sign up") {
                    showSignup = true
                }
                .textButton()
            }
        }
        .padding(AppTheme.spacingXLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .primaryBackground()
        .sheet(isPresented: $showSignup) {
            SignupView()
                .environmentObject(authManager)
        }
    }
    
    private func handleLogin() async {
        errorMessage = ""
        do {
            try await authManager.login(username: username, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(AppTheme.spacingMedium)
            .background(AppTheme.secondaryBackground)
            .cornerRadius(AppTheme.cornerRadiusMedium)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .primaryText()
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

