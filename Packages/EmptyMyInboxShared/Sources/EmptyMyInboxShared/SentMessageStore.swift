//
//  SentMessageStore.swift
//  EmptyMyInboxShared
//
//  Lightweight local audit trail for messages sent from this app.
//

import Foundation
import SQLite3

public struct SentMessageRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let gmailMessageId: String
    public let threadId: String
    public let draftId: String?
    public let inReplyToGmailId: String?
    public let accountEmail: String
    public let sentAt: Date
    public let replyMode: String?

    public init(
        id: UUID = UUID(),
        gmailMessageId: String,
        threadId: String,
        draftId: String? = nil,
        inReplyToGmailId: String? = nil,
        accountEmail: String,
        sentAt: Date = Date(),
        replyMode: String? = nil
    ) {
        self.id = id
        self.gmailMessageId = gmailMessageId
        self.threadId = threadId
        self.draftId = draftId
        self.inReplyToGmailId = inReplyToGmailId
        self.accountEmail = accountEmail
        self.sentAt = sentAt
        self.replyMode = replyMode
    }
}

public extension Notification.Name {
    static let appSentMessageRecorded = Notification.Name("appSentMessageRecorded")
}

public actor SentMessageStore {
    public static let shared = SentMessageStore()

    private let store: SQLiteSentMessageStore

    private init() {
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let storeDirectory = directory.appendingPathComponent("EmailCache", isDirectory: true)
        if !fileManager.fileExists(atPath: storeDirectory.path) {
            try? fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        }
        let dbURL = storeDirectory.appendingPathComponent("sent_messages.sqlite")
        store = SQLiteSentMessageStore(dbURL: dbURL)
    }

    public func record(_ record: SentMessageRecord) {
        store.upsert(record)
    }

    public func loadAll(limit: Int? = nil) -> [SentMessageRecord] {
        store.loadAll(limit: limit)
    }

    public func load(forAccountEmail accountEmail: String, limit: Int? = nil) -> [SentMessageRecord] {
        store.loadAll(limit: limit).filter {
            $0.accountEmail.caseInsensitiveCompare(accountEmail) == .orderedSame
        }
    }

    public func contains(gmailMessageId: String) -> Bool {
        store.contains(gmailMessageId: gmailMessageId)
    }

    public func removeAll() {
        store.removeAll()
    }
}

private final class SQLiteSentMessageStore {
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

    func upsert(_ record: SentMessageRecord) {
        guard let data = try? JSONEncoder().encode(record),
              let payload = String(data: data, encoding: .utf8) else {
            return
        }

        let sql = """
        INSERT INTO sent_messages(
            id, gmail_message_id, account_email, sent_at, payload_json
        ) VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(gmail_message_id) DO UPDATE SET
            id = excluded.id,
            account_email = excluded.account_email,
            sent_at = excluded.sent_at,
            payload_json = excluded.payload_json;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (record.id.uuidString as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (record.gmailMessageId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (record.accountEmail as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 4, record.sentAt.timeIntervalSince1970)
        sqlite3_bind_text(statement, 5, (payload as NSString).utf8String, -1, SQLITE_TRANSIENT)

        _ = sqlite3_step(statement)
    }

    func loadAll(limit: Int?) -> [SentMessageRecord] {
        var sql = "SELECT payload_json FROM sent_messages ORDER BY sent_at DESC;"
        if let limit, limit > 0 {
            sql = "SELECT payload_json FROM sent_messages ORDER BY sent_at DESC LIMIT \(limit);"
        }

        var results: [SentMessageRecord] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let cString = sqlite3_column_text(statement, 0) else { continue }
            let json = String(cString: cString)
            guard let data = json.data(using: .utf8),
                  let record = try? JSONDecoder().decode(SentMessageRecord.self, from: data) else {
                continue
            }
            results.append(record)
        }
        return results
    }

    func contains(gmailMessageId: String) -> Bool {
        let sql = "SELECT 1 FROM sent_messages WHERE gmail_message_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, (gmailMessageId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    func removeAll() {
        _ = sqlite3_exec(db, "DELETE FROM sent_messages;", nil, nil, nil)
    }

    private func openDatabase() {
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            logError("SentMessageStore open failed", category: "Email")
        }
    }

    private func createSchemaIfNeeded() {
        let schema = """
        CREATE TABLE IF NOT EXISTS sent_messages(
            id TEXT PRIMARY KEY,
            gmail_message_id TEXT NOT NULL UNIQUE,
            account_email TEXT NOT NULL,
            sent_at REAL NOT NULL,
            payload_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sent_messages_sent_at
            ON sent_messages(sent_at DESC);
        CREATE INDEX IF NOT EXISTS idx_sent_messages_account
            ON sent_messages(account_email);
        """
        _ = sqlite3_exec(db, schema, nil, nil, nil)
    }
}
