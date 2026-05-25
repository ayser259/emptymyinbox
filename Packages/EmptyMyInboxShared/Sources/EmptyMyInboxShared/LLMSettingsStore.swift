import Foundation
import Security

/// Confirms a provider API key is stored without exposing key material.
public struct LLMAPIKeyStatus: Sendable {
    public let addedAt: Date

    public init(addedAt: Date) {
        self.addedAt = addedAt
    }
}

public struct LLMKeychainOperationResult {
    public let success: Bool
    public let status: OSStatus
    public let message: String
    public let keyValue: String?
    
    public init(success: Bool, status: OSStatus, message: String, keyValue: String?) {
        self.success = success
        self.status = status
        self.message = message
        self.keyValue = keyValue
    }
}

public actor LLMSettingsStore {
    public static let shared = LLMSettingsStore()

    private let settingsFileName: String
    private let keychainService: String
    private let keychainAccount: String
    private let apiKeyAddedAtKey: String
    private let apiKeyMaskKey: String
    private let userDefaults: UserDefaults

    private var settings: LLMSettings = .default
    private var didLoad = false

    public init(
        settingsFileName: String = "llm_settings.json",
        keychainService: String = "com.emptyMyInbox.llm",
        keychainAccount: String = "openai_api_key",
        userDefaults: UserDefaults = .standard,
        metadataNamespace: String = "default"
    ) {
        self.settingsFileName = settingsFileName
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.userDefaults = userDefaults
        self.apiKeyAddedAtKey = "\(metadataNamespace).llm_api_key_added_at"
        self.apiKeyMaskKey = "\(metadataNamespace).llm_api_key_mask"
    }

    public func currentSettings() async -> LLMSettings {
        await ensureLoaded()
        return validatedSettings(settings)
    }

    public func updateSettings(_ newSettings: LLMSettings) async {
        await ensureLoaded()
        settings = validatedSettings(newSettings)
        await persistSettings()
    }

    public func hasAPIKey() -> Bool {
        let read = readAPIKeyResult()
        return read.success && !(read.keyValue?.isEmpty ?? true)
    }

    public func getAPIKey() -> String? {
        readAPIKeyResult().keyValue
    }

    public func saveAPIKey(_ apiKey: String) -> Bool {
        saveAPIKeyResult(apiKey).success
    }

    public func saveAPIKeyResult(_ apiKey: String) -> LLMKeychainOperationResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LLMKeychainOperationResult(
                success: false,
                status: errSecParam,
                message: "API key cannot be empty.",
                keyValue: nil
            )
        }
        let write = writeSecret(trimmed)
        if write.success {
            userDefaults.set(Date(), forKey: apiKeyAddedAtKey)
            userDefaults.set(maskedKey(from: trimmed), forKey: apiKeyMaskKey)
            NotificationCenter.default.post(name: .llmAPIKeyChanged, object: nil)
        }
        return write
    }

    public func setAPIKey(_ apiKey: String) {
        _ = saveAPIKey(apiKey)
    }

    public func clearAPIKey() {
        _ = clearAPIKeyResult()
    }

    public func clearAPIKeyResult() -> LLMKeychainOperationResult {
        let delete = deleteSecret()
        userDefaults.removeObject(forKey: apiKeyAddedAtKey)
        userDefaults.removeObject(forKey: apiKeyMaskKey)
        NotificationCenter.default.post(name: .llmAPIKeyChanged, object: nil)
        return delete
    }

    public func apiKeyStatus() -> LLMAPIKeyStatus? {
        let read = readAPIKeyResult()
        guard read.success, let keyValue = read.keyValue, !keyValue.isEmpty else {
            return nil
        }

        if let addedAt = userDefaults.object(forKey: apiKeyAddedAtKey) as? Date {
            return LLMAPIKeyStatus(addedAt: addedAt)
        }

        // Self-heal metadata if key exists but added-at was missing.
        let repairedDate = Date()
        userDefaults.set(maskedKey(from: keyValue), forKey: apiKeyMaskKey)
        userDefaults.set(repairedDate, forKey: apiKeyAddedAtKey)
        return LLMAPIKeyStatus(addedAt: repairedDate)
    }

    public func invalidateAfterExternalFileChange() {
        didLoad = false
    }

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        if let loaded = await loadSettingsFromDisk() {
            settings = validatedSettings(loaded)
        }
    }

    private func loadSettingsFromDisk() async -> LLMSettings? {
        let url = appSupportURL().appendingPathComponent(settingsFileName)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(LLMSettings.self, from: data)
    }

    private func persistSettings() async {
        let url = appSupportURL().appendingPathComponent(settingsFileName)
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: url, options: .atomic)
        } catch {
            logError("Failed to persist LLM settings: \(error)", category: "Settings")
        }
    }

    private func appSupportURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("emptyMyInbox", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func readAPIKeyResult() -> LLMKeychainOperationResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return LLMKeychainOperationResult(
                success: false,
                status: status,
                message: message(for: status, operation: "read"),
                keyValue: nil
            )
        }
        let key = String(data: data, encoding: .utf8)
        return LLMKeychainOperationResult(
            success: true,
            status: status,
            message: "API key is available.",
            keyValue: key
        )
    }

    private func writeSecret(_ value: String) -> LLMKeychainOperationResult {
        guard let data = value.data(using: .utf8) else {
            return LLMKeychainOperationResult(
                success: false,
                status: errSecParam,
                message: "Unable to encode API key.",
                keyValue: nil
            )
        }
        _ = deleteSecret()
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logError("Failed to save LLM API key. OSStatus: \(status)", category: "Settings")
        }
        return LLMKeychainOperationResult(
            success: status == errSecSuccess,
            status: status,
            message: message(for: status, operation: "save"),
            keyValue: nil
        )
    }

    private func deleteSecret() -> LLMKeychainOperationResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logWarning("Failed to delete LLM API key. OSStatus: \(status)", category: "Settings")
        }
        return LLMKeychainOperationResult(
            success: status == errSecSuccess || status == errSecItemNotFound,
            status: status,
            message: message(for: status, operation: "delete"),
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

    private func validatedSettings(_ candidate: LLMSettings) -> LLMSettings {
        let defaults = LLMModelCatalog.defaults(for: candidate.provider)
        let defaultCandidate = canonicalModel(candidate.defaultModel, provider: candidate.provider)
        let initialPassCandidate = canonicalModel(candidate.initialPassModel, provider: candidate.provider)
        let proCandidate = canonicalModel(candidate.proModel, provider: candidate.provider)
        let briefCandidate = canonicalModel(candidate.briefModel, provider: candidate.provider)
        let storiesCandidate = canonicalModel(candidate.storiesModel, provider: candidate.provider)
        let quickReplyCandidate = canonicalModel(candidate.quickReplyModel, provider: candidate.provider)

        let defaultModel = LLMModelCatalog.contains(defaultCandidate, provider: candidate.provider) ? defaultCandidate : defaults.defaultModel
        let initialPassModel = LLMModelCatalog.contains(initialPassCandidate, provider: candidate.provider) ? initialPassCandidate : defaults.initialPassModel
        let proModel = LLMModelCatalog.contains(proCandidate, provider: candidate.provider) ? proCandidate : defaults.proModel
        let briefModel = LLMModelCatalog.contains(briefCandidate, provider: candidate.provider) ? briefCandidate : initialPassModel
        let storiesModel = LLMModelCatalog.contains(storiesCandidate, provider: candidate.provider) ? storiesCandidate : initialPassModel
        let quickReplyModel = LLMModelCatalog.contains(quickReplyCandidate, provider: candidate.provider) ? quickReplyCandidate : defaultModel
        return LLMSettings(
            provider: candidate.provider,
            defaultModel: defaultModel,
            initialPassModel: initialPassModel,
            proModel: proModel,
            briefModel: briefModel,
            storiesModel: storiesModel,
            quickReplyModel: quickReplyModel,
            useProModelForDeepAnalysis: candidate.useProModelForDeepAnalysis,
            requestTimeoutSeconds: candidate.requestTimeoutSeconds,
            maxRetries: candidate.maxRetries
        )
    }

    private func canonicalModel(_ model: String, provider: LLMProvider) -> String {
        switch provider {
        case .openAI:
            return model
        case .claude:
            switch model {
            case "claude-haiku-4-5-20251001":
                return "claude-haiku-4-5"
            case "claude-3-5-haiku-latest":
                return "claude-haiku-4-5"
            case "claude-3-5-sonnet-latest":
                return "claude-sonnet-4-6"
            case "claude-3-5-haiku-20241022":
                return "claude-haiku-4-5"
            case "claude-3-5-sonnet-20241022":
                return "claude-sonnet-4-6"
            default:
                return model
            }
        }
    }

    private func message(for status: OSStatus, operation: String) -> String {
        switch status {
        case errSecSuccess:
            switch operation {
            case "save":
                return "API key saved successfully."
            case "delete":
                return "API key deleted successfully."
            case "read":
                return "API key is available."
            default:
                return "Operation succeeded."
            }
        case errSecItemNotFound:
            return operation == "read" ? "No API key is stored." : "API key was already removed."
        case errSecInteractionNotAllowed:
            return "Keychain access is currently unavailable. Unlock device and try again."
        case errSecAuthFailed:
            return "Authentication failed while accessing secure storage."
        case errSecParam:
            return "Invalid API key parameters."
        default:
            return "Keychain \(operation) failed (OSStatus: \(status))."
        }
    }
}

public extension Notification.Name {
    public static let llmAPIKeyChanged = Notification.Name("LLMAPIKeyChanged")
}
