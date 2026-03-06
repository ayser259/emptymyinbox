import Foundation
import Security

struct LLMAPIKeyStatus {
    let maskedKey: String
    let addedAt: Date
}

struct LLMKeychainOperationResult {
    let success: Bool
    let status: OSStatus
    let message: String
    let keyValue: String?
}

actor LLMSettingsStore {
    static let shared = LLMSettingsStore()

    private let settingsFileName: String
    private let keychainService: String
    private let keychainAccount: String
    private let apiKeyAddedAtKey: String
    private let apiKeyMaskKey: String
    private let userDefaults: UserDefaults

    private var settings: LLMSettings = .default
    private var didLoad = false

    private let supportedModels: Set<String> = ["gpt-4o-mini", "gpt-4.1-mini", "gpt-4.1", "gpt-4o"]

    init(
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

    func currentSettings() async -> LLMSettings {
        await ensureLoaded()
        return validatedSettings(settings)
    }

    func updateSettings(_ newSettings: LLMSettings) async {
        await ensureLoaded()
        settings = validatedSettings(newSettings)
        await persistSettings()
    }

    func hasAPIKey() -> Bool {
        let read = readAPIKeyResult()
        return read.success && !(read.keyValue?.isEmpty ?? true)
    }

    func getAPIKey() -> String? {
        readAPIKeyResult().keyValue
    }

    func saveAPIKey(_ apiKey: String) -> Bool {
        saveAPIKeyResult(apiKey).success
    }

    func saveAPIKeyResult(_ apiKey: String) -> LLMKeychainOperationResult {
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

    func setAPIKey(_ apiKey: String) {
        _ = saveAPIKey(apiKey)
    }

    func clearAPIKey() {
        _ = clearAPIKeyResult()
    }

    func clearAPIKeyResult() -> LLMKeychainOperationResult {
        let delete = deleteSecret()
        userDefaults.removeObject(forKey: apiKeyAddedAtKey)
        userDefaults.removeObject(forKey: apiKeyMaskKey)
        NotificationCenter.default.post(name: .llmAPIKeyChanged, object: nil)
        return delete
    }

    func apiKeyStatus() -> LLMAPIKeyStatus? {
        let read = readAPIKeyResult()
        guard read.success, let keyValue = read.keyValue, !keyValue.isEmpty else {
            return nil
        }

        if let mask = userDefaults.string(forKey: apiKeyMaskKey),
           let addedAt = userDefaults.object(forKey: apiKeyAddedAtKey) as? Date {
            return LLMAPIKeyStatus(maskedKey: mask, addedAt: addedAt)
        }

        // Self-heal metadata if key exists but status metadata was missing.
        let repairedMask = maskedKey(from: keyValue)
        let repairedDate = Date()
        userDefaults.set(repairedMask, forKey: apiKeyMaskKey)
        userDefaults.set(repairedDate, forKey: apiKeyAddedAtKey)
        return LLMAPIKeyStatus(maskedKey: repairedMask, addedAt: repairedDate)
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

    func readAPIKeyResult() -> LLMKeychainOperationResult {
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
        let defaultSettings = LLMSettings.default
        let defaultModel = supportedModels.contains(candidate.defaultModel) ? candidate.defaultModel : defaultSettings.defaultModel
        let initialPassModel = supportedModels.contains(candidate.initialPassModel) ? candidate.initialPassModel : defaultSettings.initialPassModel
        let proModel = supportedModels.contains(candidate.proModel) ? candidate.proModel : defaultSettings.proModel
        return LLMSettings(
            defaultModel: defaultModel,
            initialPassModel: initialPassModel,
            proModel: proModel,
            useProModelForDeepAnalysis: candidate.useProModelForDeepAnalysis,
            requestTimeoutSeconds: candidate.requestTimeoutSeconds,
            maxRetries: candidate.maxRetries
        )
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

extension Notification.Name {
    static let llmAPIKeyChanged = Notification.Name("LLMAPIKeyChanged")
}
