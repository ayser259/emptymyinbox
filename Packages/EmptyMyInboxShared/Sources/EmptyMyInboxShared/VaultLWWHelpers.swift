//
//  VaultLWWHelpers.swift
//  EmptyMyInboxShared
//
//  Last-write-wins using envelope `updatedAt` then `writeToken`.
//

import Foundation

public enum VaultLWWHelpers {
    public struct EnvelopeMeta: Sendable, Equatable {
        public var updatedAt: Date?
        public var writeToken: UInt64?

        public init(updatedAt: Date?, writeToken: UInt64?) {
            self.updatedAt = updatedAt
            self.writeToken = writeToken
        }
    }

    /// Parse top-level `updatedAt` (ISO8601) and `writeToken` from JSON without decoding payload.
    public static func parseEnvelopeMeta(from data: Data) -> EnvelopeMeta? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var updatedAt: Date?
        if let s = obj["updatedAt"] as? String {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            updatedAt = f1.date(from: s)
            if updatedAt == nil {
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                updatedAt = f2.date(from: s)
            }
        }
        let token: UInt64?
        if let n = obj["writeToken"] as? UInt64 {
            token = n
        } else if let i = obj["writeToken"] as? Int, i >= 0 {
            token = UInt64(i)
        } else {
            token = nil
        }
        if updatedAt == nil && token == nil { return nil }
        return EnvelopeMeta(updatedAt: updatedAt, writeToken: token)
    }

    /// Returns true if `a` should win over `b` (strictly newer). If equal on both fields, prefers `a`.
    public static func shouldPreferLocal(
        localMeta: EnvelopeMeta,
        localFileModDate: Date?,
        remoteMeta: EnvelopeMeta,
        remoteDriveModified: Date?
    ) -> Bool {
        let la = localMeta.updatedAt ?? localFileModDate ?? .distantPast
        let ra = remoteMeta.updatedAt ?? remoteDriveModified ?? .distantPast
        if la != ra {
            return la > ra
        }
        let lt = localMeta.writeToken ?? 0
        let rt = remoteMeta.writeToken ?? 0
        if lt != rt {
            return lt > rt
        }
        return true
    }

    public static func nextWriteToken(existingData: Data?) -> UInt64 {
        guard let existingData,
              let meta = parseEnvelopeMeta(from: existingData),
              let t = meta.writeToken
        else {
            return UInt64(Date().timeIntervalSince1970 * 1000)
        }
        return t &+ 1
    }
}
