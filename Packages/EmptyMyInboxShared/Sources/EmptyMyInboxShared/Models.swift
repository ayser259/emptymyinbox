//
//  Models.swift
//  emptyMyInbox
//
//  Shared data models used throughout the app
//

import Foundation

// MARK: - Account Models

public struct EmailAccount: Codable {
    public let id: Int
    public let email: String
    public let is_active: Bool
    public let last_sync: String?
    public let created_at: String
    public let email_count: Int
    
    public init(id: Int, email: String, is_active: Bool, last_sync: String?, created_at: String, email_count: Int) {
        self.id = id
        self.email = email
        self.is_active = is_active
        self.last_sync = last_sync
        self.created_at = created_at
        self.email_count = email_count
    }
}

// MARK: - Email Models

public struct EmailListItem: Codable {
    public let id: Int
    public let gmail_id: String
    public let subject: String
    public let sender: String
    public let sender_name: String?
    public let snippet: String
    public let is_read: Bool
    public let is_starred: Bool
    public let labels: [String]
    public let received_at: String
    public let account_email: String
    public let marked_read_at: String? // ISO8601 timestamp when marked as read (for 10-day deletion tracking)
    
    // Custom decoder to handle missing marked_read_at in old cached data
    public init(from decoder: Decoder) throws {
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
    
    public enum CodingKeys: String, CodingKey {
        case id, gmail_id, subject, sender, sender_name, snippet
        case is_read, is_starred, labels, received_at, account_email
        case marked_read_at
    }
    
    // Public initializer for creating EmailListItem instances
    public init(
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

public struct EmailDetail: Codable {
    public let id: Int
    public let gmail_id: String
    public let thread_id: String
    public let subject: String
    public let sender: String
    public let sender_name: String?
    public let recipients_to: String?
    public let recipients_cc: String?
    public let recipients_bcc: String?
    public let body_text: String
    public let body_html: String?
    public let snippet: String
    public let is_read: Bool
    public let is_starred: Bool
    public let labels: [String]
    public let received_at: String
    public let account_email: String
    public let created_at: String
    
    public init(
        id: Int,
        gmail_id: String,
        thread_id: String,
        subject: String,
        sender: String,
        sender_name: String?,
        recipients_to: String?,
        recipients_cc: String?,
        recipients_bcc: String?,
        body_text: String,
        body_html: String?,
        snippet: String,
        is_read: Bool,
        is_starred: Bool,
        labels: [String],
        received_at: String,
        account_email: String,
        created_at: String
    ) {
        self.id = id
        self.gmail_id = gmail_id
        self.thread_id = thread_id
        self.subject = subject
        self.sender = sender
        self.sender_name = sender_name
        self.recipients_to = recipients_to
        self.recipients_cc = recipients_cc
        self.recipients_bcc = recipients_bcc
        self.body_text = body_text
        self.body_html = body_html
        self.snippet = snippet
        self.is_read = is_read
        self.is_starred = is_starred
        self.labels = labels
        self.received_at = received_at
        self.account_email = account_email
        self.created_at = created_at
    }
}

// MARK: - Label Models

public struct GmailLabel: Codable, Hashable {
    public let id: String
    public let name: String
    public let unread_count: Int
    
    public init(id: String, name: String, unread_count: Int) {
        self.id = id
        self.name = name
        self.unread_count = unread_count
    }
}

// MARK: - Filter Models

public struct GmailFilter: Codable, Identifiable {
    public let id: Int
    public let gmail_filter_id: String
    public let criteria: FilterCriteria
    public let actions: FilterActions
    public let created_at: String
    public let updated_at: String
    
    public init(
        id: Int,
        gmail_filter_id: String,
        criteria: FilterCriteria,
        actions: FilterActions,
        created_at: String,
        updated_at: String
    ) {
        self.id = id
        self.gmail_filter_id = gmail_filter_id
        self.criteria = criteria
        self.actions = actions
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

public struct FilterCriteria: Codable {
    public let from: String?
    public let to: String?
    public let subject: String?
    public let hasAttachment: Bool?
    public let excludeChats: Bool?
    public let size: Int?  // Size in bytes
    public let sizeComparison: String?  // "larger" or "smaller"
    
    public enum CodingKeys: String, CodingKey {
        case from
        case to
        case subject
        case hasAttachment
        case excludeChats
        case size
        case sizeComparison
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(String.self, forKey: .from)
        to = try container.decodeIfPresent(String.self, forKey: .to)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        hasAttachment = try container.decodeIfPresent(Bool.self, forKey: .hasAttachment)
        excludeChats = try container.decodeIfPresent(Bool.self, forKey: .excludeChats)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        sizeComparison = try container.decodeIfPresent(String.self, forKey: .sizeComparison)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encodeIfPresent(hasAttachment, forKey: .hasAttachment)
        try container.encodeIfPresent(excludeChats, forKey: .excludeChats)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(sizeComparison, forKey: .sizeComparison)
    }
    
    // Convenience initializer for creating new criteria
    public init(
        from: String? = nil,
        to: String? = nil,
        subject: String? = nil,
        hasAttachment: Bool? = nil,
        excludeChats: Bool? = nil,
        size: Int? = nil,
        sizeComparison: String? = nil
    ) {
        self.from = from
        self.to = to
        self.subject = subject
        self.hasAttachment = hasAttachment
        self.excludeChats = excludeChats
        self.size = size
        self.sizeComparison = sizeComparison
    }
}

public struct FilterActions: Codable {
    public let addLabelIds: [String]?
    public let removeLabelIds: [String]?
    public let forward: String?
    public let markAsRead: Bool?
    public let archive: Bool?
    public let delete: Bool?
    public let alwaysMarkAsRead: Bool?
    public let neverMarkAsRead: Bool?
    public let neverSpam: Bool?
    public let star: Bool?
    
    public enum CodingKeys: String, CodingKey {
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
    
    public init(from decoder: Decoder) throws {
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
    
    public func encode(to encoder: Encoder) throws {
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
    public init(
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
public struct EmailMetadata: Codable, Identifiable {
    public let id: Int
    public let gmail_id: String
    public let thread_id: String
    public let subject: String
    public let sender: String
    public let sender_name: String?
    public let snippet: String
    public let is_read: Bool
    public let is_starred: Bool
    public let labels: [String]
    public let received_at: String
    public let account_email: String

    public init(
        id: Int,
        gmail_id: String,
        thread_id: String,
        subject: String,
        sender: String,
        sender_name: String?,
        snippet: String,
        is_read: Bool,
        is_starred: Bool,
        labels: [String],
        received_at: String,
        account_email: String
    ) {
        self.id = id
        self.gmail_id = gmail_id
        self.thread_id = thread_id
        self.subject = subject
        self.sender = sender
        self.sender_name = sender_name
        self.snippet = snippet
        self.is_read = is_read
        self.is_starred = is_starred
        self.labels = labels
        self.received_at = received_at
        self.account_email = account_email
    }
    
    /// Convert to EmailListItem for compatibility with existing views
    public func toEmailListItem() -> EmailListItem {
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

// MARK: - Daily Briefing

public enum BriefingItemType: String, Codable, CaseIterable {
    case directCommunication
    case calendarInvite
    case urgentNotification
}

public struct DailyBriefingItem: Codable, Identifiable, Hashable {
    public let id: Int
    public let emailId: Int
    public let gmailId: String
    public let threadId: String?
    public let accountEmail: String
    public let sender: String
    public let senderName: String?
    public let subject: String
    public let snippet: String
    public let receivedAt: String
    public let type: BriefingItemType
}

public struct DailyBriefingPayload: Codable {
    public let generatedAt: Date
    public let sinceDate: Date?
    public let introText: String
    public let items: [DailyBriefingItem]
}

// MARK: - Newsletter Insights

public struct NewsletterTheme: Codable, Hashable {
    public let tag: String
    public let confidence: Double

    public init(tag: String, confidence: Double) {
        self.tag = tag
        self.confidence = confidence
    }
}

public struct InsightCard: Codable, Identifiable, Hashable {
    public let id: Int
    public let emailId: Int
    public let gmailId: String
    public let accountEmail: String
    public let sender: String
    public let senderName: String?
    public let subject: String
    public let summary: String
    public let keyPoints: [String]
    public let theme: NewsletterTheme

    public init(
        id: Int,
        emailId: Int,
        gmailId: String,
        accountEmail: String,
        sender: String,
        senderName: String?,
        subject: String,
        summary: String,
        keyPoints: [String],
        theme: NewsletterTheme
    ) {
        self.id = id
        self.emailId = emailId
        self.gmailId = gmailId
        self.accountEmail = accountEmail
        self.sender = sender
        self.senderName = senderName
        self.subject = subject
        self.summary = summary
        self.keyPoints = keyPoints
        self.theme = theme
    }
}

public enum InterestSignalType: String, Codable {
    case more
    case less
}

public struct InterestSignal: Codable {
    public let timestamp: Date
    public let signalType: InterestSignalType
    public let themeTag: String
    public let sender: String
    
    public init(timestamp: Date, signalType: InterestSignalType, themeTag: String, sender: String) {
        self.timestamp = timestamp
        self.signalType = signalType
        self.themeTag = themeTag
        self.sender = sender
    }
}

public struct InterestProfile: Codable {
    public var themeScores: [String: Double]
    public var senderScores: [String: Double]
    public var recentSignals: [InterestSignal]
    public var updatedAt: Date

    public static var empty: InterestProfile {
        InterestProfile(
            themeScores: [:],
            senderScores: [:],
            recentSignals: [],
            updatedAt: Date()
        )
    }
}

// MARK: - Account Feature Inclusion

public struct FeatureAccountInclusion: Codable, Identifiable, Hashable {
    public var id: String { accountEmail.lowercased() }
    public let accountEmail: String
    public var includeInDailyBriefing: Bool
    public var includeInNewsletterInsights: Bool
    public var isPrimaryNewsletterAddress: Bool
}

// MARK: - LLM Settings

public struct LLMSettings: Codable {
    public var defaultModel: String
    public var initialPassModel: String
    public var proModel: String
    public var useProModelForDeepAnalysis: Bool
    public var requestTimeoutSeconds: Double
    public var maxRetries: Int

    public init(
        defaultModel: String,
        initialPassModel: String,
        proModel: String,
        useProModelForDeepAnalysis: Bool,
        requestTimeoutSeconds: Double,
        maxRetries: Int
    ) {
        self.defaultModel = defaultModel
        self.initialPassModel = initialPassModel
        self.proModel = proModel
        self.useProModelForDeepAnalysis = useProModelForDeepAnalysis
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.maxRetries = maxRetries
    }

    public static var `default`: LLMSettings {
        LLMSettings(
            defaultModel: "gpt-4o-mini",
            initialPassModel: "gpt-4o-mini",
            proModel: "gpt-4.1",
            useProModelForDeepAnalysis: false,
            requestTimeoutSeconds: 30,
            maxRetries: 2
        )
    }
}

