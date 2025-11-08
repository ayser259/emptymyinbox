//
//  OnboardingView.swift
//  emptyMyInbox
//
//  Onboarding flow for profile completion
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var state = ""
    @State private var zipCode = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: AppTheme.spacingXLarge) {
            Spacer()
            
            Text("Complete Your Profile")
                .font(AppTheme.title)
                .primaryText()
            
            Text("Help us personalize your experience")
                .font(AppTheme.body)
                .secondaryText()
                .multilineTextAlignment(.center)
            
            VStack(spacing: AppTheme.spacingMedium) {
                // State Picker
                Menu {
                    ForEach(USStates.states, id: \.self) { stateName in
                        Button(stateName) {
                            state = stateName
                        }
                    }
                } label: {
                    HStack {
                        Text(state.isEmpty ? "Select State" : state)
                            .foregroundColor(state.isEmpty ? AppTheme.secondaryText : AppTheme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(AppTheme.secondaryText)
                            .font(.system(size: 12))
                    }
                    .padding(AppTheme.spacingMedium)
                    .background(AppTheme.secondaryBackground)
                    .cornerRadius(AppTheme.cornerRadiusMedium)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
                
                TextField("Zip Code", text: $zipCode)
                    .textFieldStyle(CustomTextFieldStyle())
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal, AppTheme.spacingMedium)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(AppTheme.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal, AppTheme.spacingMedium)
            }
            
            Button {
                Task {
                    await handleSave()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.primaryText))
                } else {
                    Text("Continue")
                }
            }
            .primaryButton()
            .disabled(isLoading)
            .padding(.horizontal, AppTheme.spacingMedium)
            
            Button("Skip for now") {
                // User can skip - the app will show dashboard
                // We'll mark onboarding as complete by setting empty strings
                Task {
                    await handleSkip()
                }
            }
            .textButton()
            
            Spacer()
        }
        .padding(AppTheme.spacingXLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .primaryBackground()
    }
    
    private func handleSave() async {
        errorMessage = ""
        isLoading = true
        
        do {
            try await authManager.updateProfile(
                state: state.isEmpty ? nil : state,
                zipCode: zipCode.isEmpty ? nil : zipCode
            )
            // Onboarding complete, will navigate to dashboard automatically
            // The app will detect the profile is complete and show dashboard
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func handleSkip() async {
        // Skip onboarding - set empty values so app knows onboarding was shown
        // This allows the user to proceed to dashboard
        do {
            try await authManager.updateProfile(state: "", zipCode: "")
        } catch {
            // If skip fails, user can still proceed
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AuthManager())
}

