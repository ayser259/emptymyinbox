import Foundation
import Security

/// Keychain-backed API key storage for third-party providers (Gemini, Claude).
public actor GeminiAPIKeyStore {
    public static let shared = GeminiAPIKeyStore()

    private let keychainService = "com.emptymyinbox.gemini"
    private let keychainAccount = "api_key"
    private let userDefaults: UserDefaults
    private let apiKeyAddedAtKey = "gemini_api_key_added_at"
    private let apiKeyMaskKey = "gemini_api_key_mask"

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveAPIKeyResult(_ apiKey: String) -> LLMKeychainOperationResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LLMKeychainOperationResult(success: false, status: errSecParam, message: "API key cannot be empty.", keyValue: nil)
        }
        let write = writeSecret(trimmed)
        if write.success {
            userDefaults.set(Date(), forKey: apiKeyAddedAtKey)
            userDefaults.set(maskedKey(from: trimmed), forKey: apiKeyMaskKey)
            NotificationCenter.default.post(name: .geminiAPIKeyChanged, object: nil)
        }
        return write
    }

    public func clearAPIKeyResult() -> LLMKeychainOperationResult {
        let delete = deleteSecret()
        userDefaults.removeObject(forKey: apiKeyAddedAtKey)
        userDefaults.removeObject(forKey: apiKeyMaskKey)
        NotificationCenter.default.post(name: .geminiAPIKeyChanged, object: nil)
        return delete
    }

    public func apiKeyStatus() -> LLMAPIKeyStatus? {
        let read = readAPIKeyResult()
        guard read.success, let keyValue = read.keyValue, !keyValue.isEmpty else { return nil }

        if let addedAt = userDefaults.object(forKey: apiKeyAddedAtKey) as? Date {
            return LLMAPIKeyStatus(addedAt: addedAt)
        }
        let repairedDate = Date()
        userDefaults.set(maskedKey(from: keyValue), forKey: apiKeyMaskKey)
        userDefaults.set(repairedDate, forKey: apiKeyAddedAtKey)
        return LLMAPIKeyStatus(addedAt: repairedDate)
    }

    public func readAPIKeyResult() -> LLMKeychainOperationResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return LLMKeychainOperationResult(success: false, status: status, message: keyMessage(for: status, operation: "read"), keyValue: nil)
        }
        let key = String(data: data, encoding: .utf8)
        return LLMKeychainOperationResult(success: true, status: status, message: "API key is available.", keyValue: key)
    }

    public func hasAPIKey() -> Bool {
        let read = readAPIKeyResult()
        return read.success && !(read.keyValue?.isEmpty ?? true)
    }

    private func writeSecret(_ value: String) -> LLMKeychainOperationResult {
        guard let data = value.data(using: .utf8) else {
            return LLMKeychainOperationResult(success: false, status: errSecParam, message: "Unable to encode API key.", keyValue: nil)
        }
        _ = deleteSecret()
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return LLMKeychainOperationResult(success: status == errSecSuccess, status: status, message: keyMessage(for: status, operation: "save"), keyValue: nil)
    }

    private func deleteSecret() -> LLMKeychainOperationResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return LLMKeychainOperationResult(
            success: status == errSecSuccess || status == errSecItemNotFound,
            status: status,
            message: keyMessage(for: status, operation: "delete"),
            keyValue: nil
        )
    }

    private func maskedKey(from value: String) -> String {
        guard value.count > 12 else {
            let safeSuffix = String(value.suffix(2))
            return "••••••••\(safeSuffix)"
        }
        let prefix = String(value.prefix(6))
        let suffix = String(value.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }

    private func keyMessage(for status: OSStatus, operation: String) -> String {
        switch status {
        case errSecSuccess:
            return operation == "read" ? "API key is available." : "Operation succeeded."
        case errSecItemNotFound:
            return operation == "read" ? "No API key is stored." : "API key was already removed."
        case errSecInteractionNotAllowed:
            return "Keychain access is currently unavailable."
        default:
            return "Keychain \(operation) failed (OSStatus: \(status))."
        }
    }
}

public actor ClaudeAPIKeyStore {
    public static let shared = ClaudeAPIKeyStore()

    private let keychainService = "com.emptymyinbox.claude"
    private let keychainAccount = "api_key"
    private let userDefaults: UserDefaults
    private let apiKeyAddedAtKey = "claude_api_key_added_at"
    private let apiKeyMaskKey = "claude_api_key_mask"

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveAPIKeyResult(_ apiKey: String) -> LLMKeychainOperationResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LLMKeychainOperationResult(success: false, status: errSecParam, message: "API key cannot be empty.", keyValue: nil)
        }
        let write = writeSecret(trimmed)
        if write.success {
            userDefaults.set(Date(), forKey: apiKeyAddedAtKey)
            userDefaults.set(maskedKey(from: trimmed), forKey: apiKeyMaskKey)
            NotificationCenter.default.post(name: .claudeAPIKeyChanged, object: nil)
        }
        return write
    }

    public func clearAPIKeyResult() -> LLMKeychainOperationResult {
        let delete = deleteSecret()
        userDefaults.removeObject(forKey: apiKeyAddedAtKey)
        userDefaults.removeObject(forKey: apiKeyMaskKey)
        NotificationCenter.default.post(name: .claudeAPIKeyChanged, object: nil)
        return delete
    }

    public func apiKeyStatus() -> LLMAPIKeyStatus? {
        let read = readAPIKeyResult()
        guard read.success, let keyValue = read.keyValue, !keyValue.isEmpty else { return nil }

        if let addedAt = userDefaults.object(forKey: apiKeyAddedAtKey) as? Date {
            return LLMAPIKeyStatus(addedAt: addedAt)
        }
        let repairedDate = Date()
        userDefaults.set(maskedKey(from: keyValue), forKey: apiKeyMaskKey)
        userDefaults.set(repairedDate, forKey: apiKeyAddedAtKey)
        return LLMAPIKeyStatus(addedAt: repairedDate)
    }

    public func readAPIKeyResult() -> LLMKeychainOperationResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return LLMKeychainOperationResult(success: false, status: status, message: keyMessage(for: status, operation: "read"), keyValue: nil)
        }
        let key = String(data: data, encoding: .utf8)
        return LLMKeychainOperationResult(success: true, status: status, message: "API key is available.", keyValue: key)
    }

    public func hasAPIKey() -> Bool {
        let read = readAPIKeyResult()
        return read.success && !(read.keyValue?.isEmpty ?? true)
    }

    private func writeSecret(_ value: String) -> LLMKeychainOperationResult {
        guard let data = value.data(using: .utf8) else {
            return LLMKeychainOperationResult(success: false, status: errSecParam, message: "Unable to encode API key.", keyValue: nil)
        }
        _ = deleteSecret()
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return LLMKeychainOperationResult(success: status == errSecSuccess, status: status, message: keyMessage(for: status, operation: "save"), keyValue: nil)
    }

    private func deleteSecret() -> LLMKeychainOperationResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return LLMKeychainOperationResult(
            success: status == errSecSuccess || status == errSecItemNotFound,
            status: status,
            message: keyMessage(for: status, operation: "delete"),
            keyValue: nil
        )
    }

    private func maskedKey(from value: String) -> String {
        guard value.count > 12 else {
            let safeSuffix = String(value.suffix(2))
            return "••••••••\(safeSuffix)"
        }
        let prefix = String(value.prefix(6))
        let suffix = String(value.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }

    private func keyMessage(for status: OSStatus, operation: String) -> String {
        switch status {
        case errSecSuccess:
            return operation == "read" ? "API key is available." : "Operation succeeded."
        case errSecItemNotFound:
            return operation == "read" ? "No API key is stored." : "API key was already removed."
        case errSecInteractionNotAllowed:
            return "Keychain access is currently unavailable."
        default:
            return "Keychain \(operation) failed (OSStatus: \(status))."
        }
    }
}

public extension Notification.Name {
    static let geminiAPIKeyChanged = Notification.Name("GeminiAPIKeyChanged")
    static let claudeAPIKeyChanged = Notification.Name("ClaudeAPIKeyChanged")
}
