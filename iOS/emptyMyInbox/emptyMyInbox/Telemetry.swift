//
//  Telemetry.swift
//  emptyMyInbox
//

import Foundation

enum Telemetry {
    private static let sensitiveMetadataKeys: Set<String> = [
        "email",
        "api_key",
        "authorization",
        "subject",
        "snippet",
        "body",
        "sender"
    ]

    static func event(_ name: String, metadata: [String: String] = [:]) {
        let sanitized = sanitizeMetadata(metadata)
        let payload = sanitized.isEmpty ? "" : " \(sanitized)"
        logInfo("Telemetry event: \(name)\(payload)", category: "Metrics")
    }
    
    static func counter(_ name: String, delta: Int = 1, metadata: [String: String] = [:]) {
        var merged = metadata
        merged["delta"] = "\(delta)"
        event("counter.\(name)", metadata: merged)
    }
    
    static func timed<T>(_ name: String, metadata: [String: String] = [:], operation: () async throws -> T) async rethrows -> T {
        let start = Date()
        defer {
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            var merged = metadata
            merged["elapsed_ms"] = "\(elapsedMs)"
            event("timer.\(name)", metadata: merged)
        }
        return try await operation()
    }

    static func hashForDiagnostics(_ value: String) -> String {
        String(value.lowercased().hashValue, radix: 16)
    }

    static func sanitizeMetadata(_ metadata: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (key, value) in metadata {
            if sensitiveMetadataKeys.contains(key.lowercased()) {
                sanitized[key] = "<redacted>"
            } else {
                sanitized[key] = redactPII(in: value)
            }
        }
        return sanitized
    }

    static func redactPII(in text: String) -> String {
        var redacted = text
        let patterns = [
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            #"sk-[A-Za-z0-9_-]+"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
                redacted = regex.stringByReplacingMatches(
                    in: redacted,
                    options: [],
                    range: range,
                    withTemplate: "<redacted>"
                )
            }
        }
        return redacted
    }
}
