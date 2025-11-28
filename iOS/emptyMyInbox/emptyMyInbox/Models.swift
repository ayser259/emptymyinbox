//
//  Models.swift
//  emptyMyInbox
//
//  Shared data models used throughout the app
//

import Foundation

// MARK: - Account Models

struct EmailAccount: Codable {
    let id: Int
    let email: String
    let is_active: Bool
    let last_sync: String?
    let created_at: String
    let email_count: Int
}

// MARK: - Email Models

struct EmailListItem: Codable {
    let id: Int
    let gmail_id: String
    let subject: String
    let sender: String
    let sender_name: String?
    let snippet: String
    let is_read: Bool
    let is_starred: Bool
    let labels: [String]
    let received_at: String
    let account_email: String
    let marked_read_at: String? // ISO8601 timestamp when marked as read (for 10-day deletion tracking)
    
    // Custom decoder to handle missing marked_read_at in old cached data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        gmail_id = try container.decode(String.self, forKey: .gmail_id)
        subject = try container.decode(String.self, forKey: .subject)
        sender = try container.decode(String.self, forKey: .sender)
        sender_name = try container.decodeIfPresent(String.self, forKey: .sender_name)
        snippet = try container.decode(String.self, forKey: .snippet)
        is_read = try container.decode(Bool.self, forKey: .is_read)
        is_starred = try container.decode(Bool.self, forKey: .is_starred)
        labels = try container.decode([String].self, forKey: .labels)
        received_at = try container.decode(String.self, forKey: .received_at)
        account_email = try container.decode(String.self, forKey: .account_email)
        marked_read_at = try container.decodeIfPresent(String.self, forKey: .marked_read_at)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, gmail_id, subject, sender, sender_name, snippet
        case is_read, is_starred, labels, received_at, account_email
        case marked_read_at
    }
    
    // Public initializer for creating EmailListItem instances
    init(
        id: Int,
        gmail_id: String,
        subject: String,
        sender: String,
        sender_name: String?,
        snippet: String,
        is_read: Bool,
        is_starred: Bool,
        labels: [String],
        received_at: String,
        account_email: String,
        marked_read_at: String?
    ) {
        self.id = id
        self.gmail_id = gmail_id
        self.subject = subject
        self.sender = sender
        self.sender_name = sender_name
        self.snippet = snippet
        self.is_read = is_read
        self.is_starred = is_starred
        self.labels = labels
        self.received_at = received_at
        self.account_email = account_email
        self.marked_read_at = marked_read_at
    }
}

struct EmailDetail: Codable {
    let id: Int
    let gmail_id: String
    let thread_id: String
    let subject: String
    let sender: String
    let sender_name: String?
    let recipients_to: String?
    let recipients_cc: String?
    let recipients_bcc: String?
    let body_text: String
    let body_html: String?
    let snippet: String
    let is_read: Bool
    let is_starred: Bool
    let labels: [String]
    let received_at: String
    let account_email: String
    let created_at: String
}

// MARK: - Label Models

struct Label: Codable, Hashable {
    let id: String
    let name: String
    let unread_count: Int
}

// MARK: - Filter Models

struct GmailFilter: Codable, Identifiable {
    let id: Int
    let gmail_filter_id: String
    let criteria: FilterCriteria
    let actions: FilterActions
    let created_at: String
    let updated_at: String
}

struct FilterCriteria: Codable {
    let from: String?
    let to: String?
    let subject: String?
    let query: String?
    let negatedQuery: String?
    let hasAttachment: Bool?
    let excludeChats: Bool?
    let size: Int?  // Size in bytes
    let sizeComparison: String?  // "larger" or "smaller"
    
    enum CodingKeys: String, CodingKey {
        case from
        case to
        case subject
        case query
        case negatedQuery
        case hasAttachment
        case excludeChats
        case size
        case sizeComparison
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        query = try container.decodeIfPresent(String.self, forKey: .query)
        negatedQuery = try container.decodeIfPresent(String.self, forKey: .negatedQuery)
        hasAttachment = try container.decodeIfPresent(Bool.self, forKey: .hasAttachment)
        excludeChats = try container.decodeIfPresent(Bool.self, forKey: .excludeChats)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        sizeComparison = try container.decodeIfPresent(String.self, forKey: .sizeComparison)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encodeIfPresent(query, forKey: .query)
        try container.encodeIfPresent(negatedQuery, forKey: .negatedQuery)
        try container.encodeIfPresent(hasAttachment, forKey: .hasAttachment)
        try container.encodeIfPresent(excludeChats, forKey: .excludeChats)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(sizeComparison, forKey: .sizeComparison)
    }
    
    // Convenience initializer for creating new criteria
    init(
        from: String? = nil,
        to: String? = nil,
        subject: String? = nil,
        query: String? = nil,
        negatedQuery: String? = nil,
        hasAttachment: Bool? = nil,
        excludeChats: Bool? = nil,
        size: Int? = nil,
        sizeComparison: String? = nil
    ) {
        self.from = from
        self.to = to
        self.subject = subject
        self.query = query
        self.negatedQuery = negatedQuery
        self.hasAttachment = hasAttachment
        self.excludeChats = excludeChats
        self.size = size
        self.sizeComparison = sizeComparison
    }
}

struct FilterActions: Codable {
    let addLabelIds: [String]?
    let removeLabelIds: [String]?
    let forward: String?
    let markAsRead: Bool?
    let archive: Bool?
    let delete: Bool?
    let alwaysMarkAsRead: Bool?
    let neverMarkAsRead: Bool?
    let neverSpam: Bool?
    let star: Bool?
    
    enum CodingKeys: String, CodingKey {
        case addLabelIds
        case removeLabelIds
        case forward
        case markAsRead
        case archive
        case delete
        case alwaysMarkAsRead
        case neverMarkAsRead
        case neverSpam
        case star
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addLabelIds = try container.decodeIfPresent([String].self, forKey: .addLabelIds)
        removeLabelIds = try container.decodeIfPresent([String].self, forKey: .removeLabelIds)
        forward = try container.decodeIfPresent(String.self, forKey: .forward)
        markAsRead = try container.decodeIfPresent(Bool.self, forKey: .markAsRead)
        archive = try container.decodeIfPresent(Bool.self, forKey: .archive)
        delete = try container.decodeIfPresent(Bool.self, forKey: .delete)
        alwaysMarkAsRead = try container.decodeIfPresent(Bool.self, forKey: .alwaysMarkAsRead)
        neverMarkAsRead = try container.decodeIfPresent(Bool.self, forKey: .neverMarkAsRead)
        neverSpam = try container.decodeIfPresent(Bool.self, forKey: .neverSpam)
        star = try container.decodeIfPresent(Bool.self, forKey: .star)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(addLabelIds, forKey: .addLabelIds)
        try container.encodeIfPresent(removeLabelIds, forKey: .removeLabelIds)
        try container.encodeIfPresent(forward, forKey: .forward)
        try container.encodeIfPresent(markAsRead, forKey: .markAsRead)
        try container.encodeIfPresent(archive, forKey: .archive)
        try container.encodeIfPresent(delete, forKey: .delete)
        try container.encodeIfPresent(alwaysMarkAsRead, forKey: .alwaysMarkAsRead)
        try container.encodeIfPresent(neverMarkAsRead, forKey: .neverMarkAsRead)
        try container.encodeIfPresent(neverSpam, forKey: .neverSpam)
        try container.encodeIfPresent(star, forKey: .star)
    }
    
    // Convenience initializer for creating new actions
    init(
        addLabelIds: [String]? = nil,
        removeLabelIds: [String]? = nil,
        forward: String? = nil,
        markAsRead: Bool? = nil,
        archive: Bool? = nil,
        delete: Bool? = nil,
        alwaysMarkAsRead: Bool? = nil,
        neverMarkAsRead: Bool? = nil,
        neverSpam: Bool? = nil,
        star: Bool? = nil
    ) {
        self.addLabelIds = addLabelIds
        self.removeLabelIds = removeLabelIds
        self.forward = forward
        self.markAsRead = markAsRead
        self.archive = archive
        self.delete = delete
        self.alwaysMarkAsRead = alwaysMarkAsRead
        self.neverMarkAsRead = neverMarkAsRead
        self.neverSpam = neverSpam
        self.star = star
    }
}

// MARK: - Email Metadata (Lightweight - No Body Content)

/// Lightweight email metadata for fast loading and counts
/// Contains everything needed for lists and counters, but NO body content
struct EmailMetadata: Codable, Identifiable {
    let id: Int
    let gmail_id: String
    let thread_id: String
    let subject: String
    let sender: String
    let sender_name: String?
    let snippet: String
    let is_read: Bool
    let is_starred: Bool
    let labels: [String]
    let received_at: String
    let account_email: String
    
    /// Convert to EmailListItem for compatibility with existing views
    func toEmailListItem() -> EmailListItem {
        EmailListItem(
            id: id,
            gmail_id: gmail_id,
            subject: subject,
            sender: sender,
            sender_name: sender_name,
            snippet: snippet,
            is_read: is_read,
            is_starred: is_starred,
            labels: labels,
            received_at: received_at,
            account_email: account_email,
            marked_read_at: nil
        )
    }
}

