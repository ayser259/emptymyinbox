//
//  ReplyModels.swift
//  EmptyMyInboxShared
//

import Foundation

// MARK: - Mode & intent

public enum ReplyMode: String, CaseIterable, Sendable, Identifiable {
    case reply
    case replyAll

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reply: return "Reply"
        case .replyAll: return "Reply All"
        }
    }
}

/// Identifiable payload for presenting the reply composer (sheet on iOS, slide-in on Mac).
public struct ReplyComposerPresentation: Identifiable {
    public let email: EmailDetail
    public let mode: ReplyMode
    public let isCatchUpContext: Bool

    public var id: String { "\(email.id)-\(mode.rawValue)-\(isCatchUpContext)" }

    public init(email: EmailDetail, mode: ReplyMode = .reply, isCatchUpContext: Bool = false) {
        self.email = email
        self.mode = mode
        self.isCatchUpContext = isCatchUpContext
    }
}

public struct ReplyIntent {
    public let email: EmailDetail
    public var mode: ReplyMode
    /// When true, composer may offer post-send triage actions.
    public let isCatchUpContext: Bool

    public init(email: EmailDetail, mode: ReplyMode = .reply, isCatchUpContext: Bool = false) {
        self.email = email
        self.mode = mode
        self.isCatchUpContext = isCatchUpContext
    }
}

// MARK: - Recipients

public struct ReplyMailboxAddress: Hashable, Sendable, Identifiable {
    public var id: String { email.lowercased() }
    public let email: String
    public let displayName: String?

    public init(email: String, displayName: String? = nil) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var formattedForHeader: String {
        guard let name = displayName, !name.isEmpty else { return email }
        let safe = name.replacingOccurrences(of: "\"", with: "")
        return "\"\(safe)\" <\(email)>"
    }
}

public struct ReplyRecipientSet: Equatable, Sendable {
    public var to: [ReplyMailboxAddress]
    public var cc: [ReplyMailboxAddress]
    public var bcc: [ReplyMailboxAddress]

    public init(
        to: [ReplyMailboxAddress] = [],
        cc: [ReplyMailboxAddress] = [],
        bcc: [ReplyMailboxAddress] = []
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
    }

    public var isEmpty: Bool { to.isEmpty && cc.isEmpty && bcc.isEmpty }
}

/// Payload used when creating/updating Gmail reply drafts.
public struct ReplyDraftEnvelope: Equatable, Sendable {
    public var to: [ReplyMailboxAddress]
    public var cc: [ReplyMailboxAddress]
    public var bcc: [ReplyMailboxAddress]
    public var subject: String
    public var body: String
    public var includeQuotedOriginal: Bool

    public init(
        to: [ReplyMailboxAddress],
        cc: [ReplyMailboxAddress] = [],
        bcc: [ReplyMailboxAddress] = [],
        subject: String,
        body: String,
        includeQuotedOriginal: Bool = false
    ) {
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.includeQuotedOriginal = includeQuotedOriginal
    }
}

// MARK: - Catch-up outcomes

public enum CatchUpReplyOutcome: Sendable {
    case markReadAndAdvance
    case keepUnreadAndAdvance
    case stay
}

// MARK: - Quick Reply

public enum QuickReplyAction: String, CaseIterable, Sendable, Identifiable {
    case yes
    case no
    case thanks
    case schedule
    case needMoreInfo
    case shorten
    case soften
    case makeDirect
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .yes: return "Yes"
        case .no: return "No"
        case .thanks: return "Thanks"
        case .schedule: return "Schedule"
        case .needMoreInfo: return "More info"
        case .shorten: return "Shorten"
        case .soften: return "Soften"
        case .makeDirect: return "Direct"
        case .custom: return "Custom"
        }
    }

    public var systemImage: String {
        switch self {
        case .yes: return "checkmark.circle"
        case .no: return "xmark.circle"
        case .thanks: return "hand.thumbsup"
        case .schedule: return "calendar"
        case .needMoreInfo: return "questionmark.circle"
        case .shorten: return "arrow.down.right.and.arrow.up.left"
        case .soften: return "face.smiling"
        case .makeDirect: return "arrow.right.circle"
        case .custom: return "pencil"
        }
    }

    /// Instruction passed to the LLM as `quickReplyAsk`.
    public func promptPhrase(customText: String = "") -> String {
        switch self {
        case .yes:
            return "Write a brief affirmative reply agreeing with the request."
        case .no:
            return "Write a polite decline or refusal with a brief reason if appropriate."
        case .thanks:
            return "Write a short thank-you reply acknowledging the message."
        case .schedule:
            return "Propose scheduling a call or meeting and ask for availability."
        case .needMoreInfo:
            return "Ask clarifying questions before committing to an answer."
        case .shorten:
            return "Rewrite the current draft to be shorter while keeping the meaning."
        case .soften:
            return "Rewrite the current draft to sound warmer and less blunt."
        case .makeDirect:
            return "Rewrite the current draft to be more direct and concise."
        case .custom:
            return customText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public var isRewriteAction: Bool {
        switch self {
        case .shorten, .soften, .makeDirect: return true
        default: return false
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
