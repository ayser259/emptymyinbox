//
//  AuthManager.swift
//  emptyMyInbox
//
//  Authentication state manager
//

import Foundation
import SwiftUI

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    
    private let apiService = APIService.shared
    
    init() {
        // Check if user is already authenticated
        checkAuthStatus()
    }
    
    func checkAuthStatus() {
        if apiService.hasAccessToken {
            Task {
                await loadUser()
            }
        }
    }
    
    @MainActor
    func loadUser() async {
        do {
            let user = try await apiService.getUser()
            self.currentUser = user
            self.isAuthenticated = true
        } catch {
            // Token might be invalid, clear it
            apiService.clearTokens()
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }
    
    @MainActor
    func login(username: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let response = try await apiService.login(username: username, password: password)
        self.currentUser = response.user
        self.isAuthenticated = true
    }
    
    @MainActor
    func register(_ data: RegisterRequest) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let response = try await apiService.register(data)
        self.currentUser = response.user
        self.isAuthenticated = true
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
    }
    
    @MainActor
    func updateProfile(state: String?, zipCode: String?) async throws {
        let user = try await apiService.updateProfile(state: state, zipCode: zipCode)
        self.currentUser = user
    }
}

