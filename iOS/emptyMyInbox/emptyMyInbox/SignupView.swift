//
//  SignupView.swift
//  emptyMyInbox
//
//  Signup view with backend integration
//

import SwiftUI

struct SignupView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: AppTheme.spacingLarge) {
                    Text("Create Account")
                        .font(AppTheme.title)
                        .primaryText()
                        .padding(.top, AppTheme.spacingLarge)
                    
                    Text("Sign up to start managing your inbox")
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
                        HStack(spacing: AppTheme.spacingMedium) {
                            TextField("First Name", text: $firstName)
                                .textFieldStyle(CustomTextFieldStyle())
                            
                            TextField("Last Name", text: $lastName)
                                .textFieldStyle(CustomTextFieldStyle())
                        }
                        
                        TextField("Username *", text: $username)
                            .textFieldStyle(CustomTextFieldStyle())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        
                        TextField("Email", text: $email)
                            .textFieldStyle(CustomTextFieldStyle())
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                        
                        SecureField("Password *", text: $password)
                            .textFieldStyle(CustomTextFieldStyle())
                        
                        SecureField("Confirm Password *", text: $passwordConfirm)
                            .textFieldStyle(CustomTextFieldStyle())
                    }
                    .padding(.horizontal, AppTheme.spacingMedium)
                    
                    Button {
                        Task {
                            await handleSignup()
                        }
                    } label: {
                        if authManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primaryText))
                        } else {
                            Text("Sign Up")
                        }
                    }
                    .primaryButton()
                    .disabled(authManager.isLoading || !isFormValid)
                    .padding(.horizontal, AppTheme.spacingMedium)
                }
                .padding(AppTheme.spacingXLarge)
            }
            .primaryBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .textButton()
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !username.isEmpty &&
        !password.isEmpty &&
        password == passwordConfirm &&
        password.count >= 8
    }
    
    private func handleSignup() async {
        errorMessage = ""
        
        guard password == passwordConfirm else {
            errorMessage = "Passwords do not match"
            return
        }
        
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters long"
            return
        }
        
        let registerData = RegisterRequest(
            username: username,
            email: email.isEmpty ? nil : email,
            password: password,
            password_confirm: passwordConfirm,
            first_name: firstName.isEmpty ? nil : firstName,
            last_name: lastName.isEmpty ? nil : lastName,
            state: nil,
            zip_code: nil
        )
        
        do {
            try await authManager.register(registerData)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SignupView()
        .environmentObject(AuthManager())
}

