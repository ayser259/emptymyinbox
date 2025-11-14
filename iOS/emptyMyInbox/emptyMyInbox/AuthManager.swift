//
//  AuthManager.swift
//  emptyMyInbox
//
//  Authentication state manager
//

import Foundation
import SwiftUI

class AuthManager: ObservableObject {
    enum SessionState: Equatable {
        case checking
        case authenticated
        case needsLogin
        case offline(message: String?)
    }
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var sessionState: SessionState = .checking
    
    private let apiService = APIService.shared
    
    init() {
        // Check if user is already authenticated
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        if apiService.hasAccessToken {
            sessionState = .checking
            Task {
                await loadUser()
            }
        } else {
            sessionState = .needsLogin
        }
    }
    
    @MainActor
    func loadUser() async {
        sessionState = .checking
        do {
            let user = try await apiService.getUser()
            self.currentUser = user
            self.isAuthenticated = true
            self.sessionState = .authenticated
        } catch let urlError as URLError where urlError.code == .timedOut || urlError.code == .notConnectedToInternet {
            // Don't clear tokens, allow offline fallback
            self.sessionState = .offline(message: urlError.localizedDescription)
        } catch let apiError as APIError {
            if case .unauthorized = apiError {
                apiService.clearTokens()
                self.isAuthenticated = false
                self.currentUser = nil
                self.sessionState = .needsLogin
            } else {
                self.sessionState = .offline(message: apiError.localizedDescription)
            }
        } catch {
            self.sessionState = .offline(message: error.localizedDescription)
        }
    }
    
    @MainActor
    func login(username: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let response = try await apiService.login(username: username, password: password)
        self.currentUser = response.user
        self.isAuthenticated = true
        self.sessionState = .authenticated
    }
    
    @MainActor
    func register(_ data: RegisterRequest) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let response = try await apiService.register(data)
        self.currentUser = response.user
        self.isAuthenticated = true
        self.sessionState = .authenticated
    }
    
    @MainActor
    func logout() async {
        do {
            try await apiService.logout()
        } catch {
            // Even if logout fails, clear local state
        }
        self.isAuthenticated = false
        self.currentUser = nil
        self.sessionState = .needsLogin
    }
    
    @MainActor
    func updateProfile(state: String?, zipCode: String?) async throws {
        let user = try await apiService.updateProfile(state: state, zipCode: zipCode)
        self.currentUser = user
    }
}

