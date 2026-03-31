//
//  ActionItemTitleParsing.swift
//  EmptyMyInboxShared
//

import Foundation

/// Parses inline shortcuts from action item titles: `#context`, `p0`…`p4`, and `!`…`!!!!!`.
public enum ActionItemTitleParsing {
    public struct ParsedShortcuts: Sendable, Equatable {
        public var cleanedTitle: String
        public var contextName: String?
        public var priority: Int?
    }

    // MARK: - Active # token (for autocomplete)

    /// If the title ends with an incomplete `#token`, returns the substring range to replace and the filter query.
    public static func activeHashSuffix(in title: String) -> (fullTokenRange: Range<String.Index>, query: String)? {
        guard let range = title.range(of: "#([^\\s#]*)$", options: .regularExpression) else { return nil }
        let afterHash = title.index(after: range.lowerBound)
        let query: String
        if afterHash < range.upperBound {
            query = String(title[afterHash..<range.upperBound])
        } else {
            query = ""
        }
        return (range, query)
    }

    /// Replace the trailing `#...` token with `#Name ` (keeps leading text).
    public static func applyHashSelection(title: String, contextName: String) -> String {
        guard let (r, _) = activeHashSuffix(in: title) else { return title }
        let prefix = String(title[..<r.lowerBound])
        let safeName = contextName.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "#" + safeName + " "
    }

    // MARK: - Full parse at save time

    /// Strips priority/context markers and returns structured fields. Last `#token` wins for context; highest urgency wins for priority.
    public static func parseShortcuts(from rawTitle: String) -> ParsedShortcuts {
        var t = rawTitle
        var context: String?
        var priority: Int?

        var pFromWord: Int?
        t = stripPriorityWords(from: t, into: &pFromWord)

        var pFromBang: Int?
        t = stripBangRuns(from: t, into: &pFromBang)

        var ctx: String?
        t = stripHashContexts(from: t, into: &ctx)

        priority = mergedPriority(pFromWord, pFromBang)
        context = ctx

        let cleaned = t
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedShortcuts(cleanedTitle: cleaned, contextName: context, priority: priority)
    }

    private static func mergedPriority(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case (nil, nil): return nil
        case let (x?, nil): return x
        case let (nil, y?): return y
        case let (x?, y?): return min(x, y)
        }
    }

    private static func stripPriorityWords(from s: String, into priority: inout Int?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\bp([0-4])\b"#, options: []) else { return s }
        let ns = s as NSString
        var best: Int?
        regex.enumerateMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            if let p = Int(ns.substring(with: match.range(at: 1))) {
                if let b = best {
                    best = min(b, p)
                } else {
                    best = p
                }
            }
        }
        priority = best
        return regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    private static func stripBangRuns(from s: String, into priority: inout Int?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!+"#, options: []) else { return s }
        let ns = s as NSString
        var maxRun = 0
        regex.enumerateMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match else { return }
            maxRun = max(maxRun, match.range.length)
        }
        if maxRun > 0 {
            let bangP = min(4, maxRun - 1)
            priority = bangP
        }
        return regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    /// All `#token` names in order (for inline chips).
    public static func hashTagNames(in title: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"#([^\s#]+)"#, options: []) else { return [] }
        let ns = title as NSString
        var out: [String] = []
        regex.enumerateMatches(in: title, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let name = ns.substring(with: match.range(at: 1))
            if !name.isEmpty { out.append(name) }
        }
        return out
    }

    private static func stripHashContexts(from s: String, into context: inout String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"#([^\s#]+)"#, options: []) else { return s }
        let ns = s as NSString
        var lastName: String?
        regex.enumerateMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let name = ns.substring(with: match.range(at: 1))
            if !name.isEmpty {
                lastName = name
            }
        }
        context = lastName
        return regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }
}
