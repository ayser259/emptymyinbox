//
//  EmailActionSynchronizer.swift
//  emptyMyInbox
//
//  Handles background synchronization of email side-effect actions,
//  supporting offline queuing and retry behaviour.
//

import Foundation
import SQLite3

public actor EmailActionSynchronizer {
    public static let shared = EmailActionSynchronizer()
    private nonisolated static let sqliteMigrationKey = "EmailActionSynchronizerSQLiteOutboxV1"
    
    public struct PendingAction: Codable, Identifiable {
        public enum Kind: String, Codable {
            case star
            case unstar
            case markRead
            case markUnread
        }
        
        public let id: UUID
        public let emailId: Int
        public let gmailId: String
        public let accountEmail: String
        public let kind: Kind
        public let createdAt: Date
        public var attemptCount: Int
        public var nextRetryAt: Date
        public var lastError: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case emailId
            case gmailId
            case accountEmail
            case kind
            case createdAt
            case attemptCount
            case nextRetryAt
            case lastError
        }
        
        public init(emailId: Int, gmailId: String, accountEmail: String, kind: Kind, createdAt: Date = Date()) {
            self.id = UUID()
            self.emailId = emailId
            self.gmailId = gmailId
            self.accountEmail = accountEmail
            self.kind = kind
            self.createdAt = createdAt
            self.attemptCount = 0
            self.nextRetryAt = createdAt
            self.lastError = nil
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            emailId = try container.decode(Int.self, forKey: .emailId)
            gmailId = try container.decode(String.self, forKey: .gmailId)
            accountEmail = try container.decode(String.self, forKey: .accountEmail)
            kind = try container.decode(Kind.self, forKey: .kind)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
            nextRetryAt = try container.decodeIfPresent(Date.self, forKey: .nextRetryAt) ?? createdAt
            lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        }
    }
    
    protocol ActionStore {
        func loadAll() -> [PendingAction]
        func upsert(_ action: PendingAction)
        func remove(id: UUID)
        func removeAll()
    }
    
    final class JSONActionStore: ActionStore {
        private let url: URL
        
        init(url: URL) {
            self.url = url
        }
        
        func loadAll() -> [PendingAction] {
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([PendingAction].self, from: data)) ?? []
        }
        
        func upsert(_ action: PendingAction) {
            var actions = loadAll().filter { $0.id != action.id }
            actions.append(action)
            save(actions)
        }
        
        func remove(id: UUID) {
            let actions = loadAll().filter { $0.id != id }
            save(actions)
        }
        
        func removeAll() {
            save([])
        }
        
        private func save(_ actions: [PendingAction]) {
            do {
                let data = try JSONEncoder().encode(actions)
                try data.write(to: url, options: .atomic)
            } catch {
                logError("JSONActionStore save error: \(error)", category: "Email")
            }
        }
    }
    
    final class SQLiteActionStore: ActionStore {
        private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        private var db: OpaquePointer?
        private let dbURL: URL
        
        init(dbURL: URL) {
            self.dbURL = dbURL
            openDatabase()
            createSchemaIfNeeded()
        }
        
        deinit {
            sqlite3_close(db)
        }
        
        func loadAll() -> [PendingAction] {
            var results: [PendingAction] = []
            let sql = "SELECT payload_json FROM action_outbox ORDER BY created_at ASC;"
            var statement: OpaquePointer?
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return []
            }
            defer { sqlite3_finalize(statement) }
            
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let cString = sqlite3_column_text(statement, 0) else { continue }
                let json = String(cString: cString)
                guard let data = json.data(using: .utf8),
                      let action = try? JSONDecoder().decode(PendingAction.self, from: data) else {
                    continue
                }
                results.append(action)
            }
            
            return results
        }
        
        func upsert(_ action: PendingAction) {
            let domain = Self.domain(for: action.kind)
            guard let data = try? JSONEncoder().encode(action),
                  let payload = String(data: data, encoding: .utf8) else {
                return
            }
            
            let sql = """
            INSERT INTO action_outbox(
                id, account_email, gmail_id, domain, kind, created_at, next_retry_at, payload_json
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_email, gmail_id, domain) DO UPDATE SET
                id = excluded.id,
                kind = excluded.kind,
                created_at = excluded.created_at,
                next_retry_at = excluded.next_retry_at,
                payload_json = excluded.payload_json;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, (action.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, (action.accountEmail as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, (action.gmailId as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, (domain as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, (action.kind.rawValue as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 6, action.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, action.nextRetryAt.timeIntervalSince1970)
            sqlite3_bind_text(statement, 8, (payload as NSString).utf8String, -1, SQLITE_TRANSIENT)
            
            _ = sqlite3_step(statement)
        }
        
        func remove(id: UUID) {
            let sql = "DELETE FROM action_outbox WHERE id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_text(statement, 1, (id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
            _ = sqlite3_step(statement)
        }
        
        func removeAll() {
            _ = sqlite3_exec(db, "DELETE FROM action_outbox;", nil, nil, nil)
        }
        
        private static func domain(for kind: PendingAction.Kind) -> String {
            switch kind {
            case .star, .unstar:
                return "star"
            case .markRead, .markUnread:
                return "read"
            }
        }
        
        private func openDatabase() {
            if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
                logError("SQLiteActionStore open failed", category: "Email")
            }
        }
        
        private func createSchemaIfNeeded() {
            let schema = """
            CREATE TABLE IF NOT EXISTS action_outbox(
                id TEXT PRIMARY KEY,
                account_email TEXT NOT NULL,
                gmail_id TEXT NOT NULL,
                domain TEXT NOT NULL,
                kind TEXT NOT NULL,
                created_at REAL NOT NULL,
                next_retry_at REAL NOT NULL,
                payload_json TEXT NOT NULL
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_action_outbox_domain
                ON action_outbox(account_email, gmail_id, domain);
            CREATE INDEX IF NOT EXISTS idx_action_outbox_next_retry
                ON action_outbox(next_retry_at);
            """
            _ = sqlite3_exec(db, schema, nil, nil, nil)
        }
    }
    
    private let queueFileURL: URL
    private let queueSQLiteURL: URL
    private let jsonStore: JSONActionStore
    private let actionStore: ActionStore
    
    private var pendingActions: [PendingAction] = []
    private var isProcessing = false
    private var testingDisableProcessing = false
    private let minimumRetryDelayNanoseconds: UInt64 = 2 * 1_000_000_000
    
    private init() {
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let actionDirectory = directory.appendingPathComponent("EmailCache", isDirectory: true)
        
        if !fileManager.fileExists(atPath: actionDirectory.path) {
            try? fileManager.createDirectory(at: actionDirectory, withIntermediateDirectories: true)
        }
        
        queueFileURL = actionDirectory.appendingPathComponent("pending_actions.json")
        queueSQLiteURL = actionDirectory.appendingPathComponent("pending_actions.sqlite")
        jsonStore = JSONActionStore(url: queueFileURL)
        actionStore = SQLiteActionStore(dbURL: queueSQLiteURL)
        
        migrateFromJSONIfNeeded()
        pendingActions = actionStore.loadAll()
        if !pendingActions.isEmpty {
            Task {
                await self.scheduleProcessingIfNeeded()
            }
        }
    }
    
    public func enqueueStar(emailId: Int, gmailId: String, accountEmail: String, shouldStar: Bool) {
        let kind: PendingAction.Kind = shouldStar ? .star : .unstar
        enqueue(PendingAction(emailId: emailId, gmailId: gmailId, accountEmail: accountEmail, kind: kind))
    }
    
    public func enqueueMarkRead(emailId: Int, gmailId: String, accountEmail: String) {
        enqueue(PendingAction(emailId: emailId, gmailId: gmailId, accountEmail: accountEmail, kind: .markRead))
    }
    
    public func enqueueMarkUnread(emailId: Int, gmailId: String, accountEmail: String) {
        enqueue(PendingAction(emailId: emailId, gmailId: gmailId, accountEmail: accountEmail, kind: .markUnread))
    }
    
    public func resumePendingActions() {
        scheduleProcessingIfNeeded()
    }
    
    // MARK: - Private Helpers
    
    private func enqueue(_ action: PendingAction) {
        // Keep only the latest intent per email for each action domain.
        pendingActions.removeAll { existing in
            guard existing.gmailId == action.gmailId, existing.accountEmail == action.accountEmail else {
                return false
            }
            let isStarDomain = Set([PendingAction.Kind.star, .unstar]).contains(existing.kind) &&
                Set([PendingAction.Kind.star, .unstar]).contains(action.kind)
            let isReadDomain = Set([PendingAction.Kind.markRead, .markUnread]).contains(existing.kind) &&
                Set([PendingAction.Kind.markRead, .markUnread]).contains(action.kind)
            return isStarDomain || isReadDomain
        }
        pendingActions.append(action)
        actionStore.upsert(action)
        Telemetry.counter("action_queue.enqueued")
        Telemetry.event("action_queue.depth", metadata: ["count": "\(pendingActions.count)"])
        if !testingDisableProcessing {
            scheduleProcessingIfNeeded()
        }
    }
    
    private func scheduleProcessingIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            await self.processQueue()
        }
    }
    
    private func processQueue() async {
        defer { isProcessing = false }
        
        while !pendingActions.isEmpty {
            let now = Date()
            
            guard let readyIndex = pendingActions.firstIndex(where: { $0.nextRetryAt <= now }) else {
                let nextRetry = pendingActions.map(\.nextRetryAt).min() ?? now
                let waitSeconds = max(0.5, min(5.0, nextRetry.timeIntervalSince(now)))
                try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                continue
            }
            
            var action = pendingActions.remove(at: readyIndex)
            
            do {
                try await perform(action)
                actionStore.remove(id: action.id)
                Telemetry.counter("action_queue.processed")
                Telemetry.event("action_queue.depth", metadata: ["count": "\(pendingActions.count)"])
            } catch {
                logError("EmailActionSynchronizer failed to process action \(action.id): \(error)", category: "Email")
                let (shouldRetry, reason) = classifyRetry(for: error)
                
                if shouldRetry {
                    action.attemptCount += 1
                    action.lastError = reason
                    let delay = retryDelaySeconds(forAttempt: action.attemptCount)
                    action.nextRetryAt = Date().addingTimeInterval(delay)
                    pendingActions.append(action)
                    Telemetry.counter("action_queue.retry_scheduled")
                } else {
                    logWarning("EmailActionSynchronizer dropping action \(action.id): \(reason)", category: "Email")
                    Telemetry.counter("action_queue.dropped")
                }
                Telemetry.event("action_queue.depth", metadata: ["count": "\(pendingActions.count)"])
                
                actionStore.upsert(action)
                try? await Task.sleep(nanoseconds: minimumRetryDelayNanoseconds)
            }
        }
    }
    
    private func perform(_ action: PendingAction) async throws {
        let gmailService = GmailAPIService.shared
        guard let account = gmailService.getAccount(byEmail: action.accountEmail) else {
            throw NSError(domain: "EmailActionSynchronizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Account not found"])
        }
        
        switch action.kind {
        case .star:
            try await gmailService.starMessage(for: account, messageId: action.gmailId)
        case .unstar:
            try await gmailService.unstarMessage(for: account, messageId: action.gmailId)
        case .markRead:
            try await gmailService.markAsRead(for: account, messageId: action.gmailId)
        case .markUnread:
            try await gmailService.markAsUnread(for: account, messageId: action.gmailId)
        }
    }
    
    private func retryDelaySeconds(forAttempt attempt: Int) -> TimeInterval {
        let boundedAttempt = min(max(attempt, 1), 6)
        return min(300, pow(2.0, Double(boundedAttempt - 1)) * 5.0)
    }
    
    private func classifyRetry(for error: Error) -> (Bool, String) {
        let nsError = error as NSError
        if nsError.domain == "EmailActionSynchronizer" && nsError.code == 1 {
            return (false, "Account not found")
        }
        
        if let gmailError = error as? GmailAPIError {
            switch gmailError {
            case .notAuthenticated, .tokenExpired:
                return (false, gmailError.localizedDescription)
            default:
                return (true, gmailError.localizedDescription)
            }
        }
        
        return (true, error.localizedDescription)
    }
    
    /// JSON summary of the outbox (pending count only; optional future sync; does not replace SQLite).
    public func exportCloudSyncSummaryData() async -> Data? {
        struct Summary: Codable {
            let pendingCount: Int
            let updatedAt: Date
        }
        let s = Summary(pendingCount: pendingActions.count, updatedAt: Date())
        return try? JSONEncoder().encode(s)
    }

    private func migrateFromJSONIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.sqliteMigrationKey) else { return }
        
        let legacy = jsonStore.loadAll()
        if !legacy.isEmpty && actionStore.loadAll().isEmpty {
            for action in legacy {
                actionStore.upsert(action)
            }
            logInfo("EmailActionSynchronizer: migrated \(legacy.count) JSON actions to SQLite", category: "Email")
        }
        
        defaults.set(true, forKey: Self.sqliteMigrationKey)
    }
    
    // MARK: - Test Hooks
    
    public func setTestingDisableProcessing(_ disabled: Bool) {
        testingDisableProcessing = disabled
    }
    
    public func testingPendingActions() -> [PendingAction] {
        pendingActions
    }
    
    public func testingClearPendingActions() {
        pendingActions.removeAll()
        actionStore.removeAll()
        jsonStore.removeAll()
    }
}



