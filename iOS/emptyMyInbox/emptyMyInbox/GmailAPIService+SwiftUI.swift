//
//  GmailAPIService+SwiftUI.swift
//  emptyMyInbox
//
//  SwiftUI integration helpers for GmailAPIService
//

import SwiftUI
import GoogleSignIn

#if canImport(UIKit)
import UIKit
#endif

extension GmailAPIService {
    /// SwiftUI-friendly sign-in method
    @MainActor
    func signInWithSwiftUI() async throws -> GmailAccount {
        #if canImport(UIKit)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw GmailAPIError.configurationError
        }
        
        return try await signIn(presentingViewController: rootViewController)
        #else
        throw GmailAPIError.configurationError
        #endif
    }
}

// MARK: - View Helper

struct GoogleSignInButton: View {
    let action: () async throws -> Void
    @State private var isSigningIn = false
    
    var body: some View {
        Button(action: {
            Task {
                isSigningIn = true
                do {
                    try await action()
                } catch {
                    logError("Sign in failed: \(error)", category: "Auth")
                }
                isSigningIn = false
            }
        }) {
            HStack {
                if isSigningIn {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "envelope.fill")
                }
                Text("Sign in with Google")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .disabled(isSigningIn)
    }
}

