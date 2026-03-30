//
//  VaultErrors.swift
//  EmptyMyInboxShared
//

import Foundation

public enum VaultError: Error, Sendable, Equatable, LocalizedError {
    case notConfigured
    case invalidPath(String)
    case encodingFailed
    case decodingFailed
    case ioFailed(String)
    case bookmarkResolveFailed
    case securityScopeDenied
    case driveNotAuthorized
    case driveAPIFailed(Int, String)
    case noGoogleAccount
    case syncInProgress
    case actionItemNotFound(String)
    case vaultNotFound
    case cannotOpenDriveVault

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "No vault is configured."
        case .invalidPath(let p): return "Invalid vault path: \(p)"
        case .encodingFailed: return "Failed to encode vault data."
        case .decodingFailed: return "Failed to decode vault data."
        case .ioFailed(let m): return m
        case .bookmarkResolveFailed: return "Could not open the saved folder bookmark."
        case .securityScopeDenied: return "Could not access the selected folder."
        case .driveNotAuthorized: return "Google Drive access was not granted."
        case .driveAPIFailed(let code, let body): return "Drive API error (\(code)): \(body)"
        case .noGoogleAccount: return "Sign in with Google first to use a Drive vault."
        case .syncInProgress: return "Vault sync is already running."
        case .actionItemNotFound(let id): return "Action item not found: \(id)"
        case .vaultNotFound: return "That vault folder was not found on this device."
        case .cannotOpenDriveVault: return "This Google Drive vault is missing folder or account info. Sync once while signed in, or recreate the vault."
        }
    }
}
