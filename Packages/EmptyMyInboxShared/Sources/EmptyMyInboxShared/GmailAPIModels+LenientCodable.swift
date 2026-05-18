//
//  GmailAPIModels+LenientCodable.swift
//  EmptyMyInboxShared
//
//  Gmail API responses sometimes omit keys our models treated as required; decode with defaults.
//

import Foundation

extension GmailMessage {
    enum CodingKeys: String, CodingKey {
        case id, threadId, snippet, payload, labelIds, internalDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        snippet = try c.decodeIfPresent(String.self, forKey: .snippet) ?? ""
        payload = try c.decodeIfPresent(GmailPayload.self, forKey: .payload)
        labelIds = try c.decodeIfPresent([String].self, forKey: .labelIds) ?? []
        internalDate = try c.decodeIfPresent(String.self, forKey: .internalDate) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadId, forKey: .threadId)
        try c.encode(snippet, forKey: .snippet)
        try c.encodeIfPresent(payload, forKey: .payload)
        try c.encode(labelIds, forKey: .labelIds)
        try c.encode(internalDate, forKey: .internalDate)
    }
}

extension GmailPayload {
    enum CodingKeys: String, CodingKey {
        case mimeType, headers, parts, body
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        headers = try c.decodeIfPresent([GmailHeader].self, forKey: .headers) ?? []
        parts = try c.decodeIfPresent([GmailPart].self, forKey: .parts)
        body = try c.decodeIfPresent(GmailBody.self, forKey: .body)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(mimeType, forKey: .mimeType)
        try c.encode(headers, forKey: .headers)
        try c.encodeIfPresent(parts, forKey: .parts)
        try c.encodeIfPresent(body, forKey: .body)
    }
}
