//
//  ActionItemTitleParsing.swift
//  EmptyMyInboxShared
//

import Foundation

/// Parses inline shortcuts from action item titles: `@context` (labels), `#project`, `p0`…`p4`, `u0`…`u4`, legacy `_project` and `/project`, and `!` runs for priority.
///
/// **Tokens must be separate “words”** (whitespace or punctuation boundaries): `p2 u1` works; `fooP2` does not.
/// Priority from `!`: each `!` bumps priority (1–4), e.g. `!` → P1, `!!` → P2, … `!!!!` → P4 (longer runs cap at P4).
public enum ActionItemTitleParsing {
    public struct ParsedShortcuts: Sendable, Equatable {
        public var cleanedTitle: String
        public var contextName: String?
        public var priority: Int?
        public var urgency: Int?
        public var projectName: String?
    }

    // MARK: - Active trailing tokens (for autocomplete)

    /// Trailing token at end of title, allowing optional whitespace before end-of-string (so `@ab ` still matches).
    private static func matchTrailingToken(
        in title: String,
        pattern: String
    ) -> (fullMatch: Range<String.Index>, query: String)? {
        let ns = title as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        guard let match = regex.firstMatch(in: title, options: [], range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2,
              let fullRange = Range(match.range, in: title),
              let innerRange = Range(match.range(at: 1), in: title)
        else { return nil }
        return (fullMatch: fullRange, query: String(title[innerRange]))
    }

    /// If the title ends with an incomplete `@token` (label), returns the substring range to replace and the filter query.
    public static func activeLabelSuffix(in title: String) -> (fullTokenRange: Range<String.Index>, query: String)? {
        guard let m = matchTrailingToken(in: title, pattern: "@([^\\s@]*)\\s*$") else { return nil }
        return (m.fullMatch, m.query)
    }

    /// If the title ends with an incomplete `#`, `_`, or `/` project token, returns the substring range to replace and the filter query.
    public static func activeProjectSuffix(in title: String) -> (fullTokenRange: Range<String.Index>, query: String)? {
        if let m = matchTrailingToken(in: title, pattern: "#([^\\s#]*)\\s*$") { return (m.fullMatch, m.query) }
        return matchTrailingToken(in: title, pattern: "(?:/|_)([^\\s#]*)\\s*$").map { ($0.fullMatch, $0.query) }
    }

    /// Replace the trailing `@...` token with `@Name ` (keeps leading text).
    public static func applyLabelSelection(title: String, contextName: String) -> String {
        guard let (r, _) = activeLabelSuffix(in: title) else { return title }
        let prefix = String(title[..<r.lowerBound])
        let safeName = contextName.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "@" + safeName + " "
    }

    /// Replace the trailing `#...`, `_...`, or `/...` token with `#Name ` (keeps leading text).
    public static func applyProjectSelection(title: String, projectName: String) -> String {
        guard activeProjectSuffix(in: title) != nil else { return title }
        let prefix: String
        if let (r, _) = matchTrailingToken(in: title, pattern: "#([^\\s#]*)\\s*$") {
            prefix = String(title[..<r.lowerBound])
        } else if let (r, _) = matchTrailingToken(in: title, pattern: "(?:/|_)([^\\s#]*)\\s*$") {
            prefix = String(title[..<r.lowerBound])
        } else {
            return title
        }
        let safeName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + "#" + safeName + " "
    }

    // MARK: - Full parse at save time

    /// Strips shortcut markers and returns structured fields.
    public static func parseShortcuts(from rawTitle: String) -> ParsedShortcuts {
        var t = rawTitle
        var context: String?
        var priority: Int?
        var urgency: Int?
        var projectName: String?

        var pFromWord: Int?
        t = stripPriorityWords(from: t, into: &pFromWord)

        var uFromWord: Int?
        t = stripUrgencyWords(from: t, into: &uFromWord)

        var pFromBang: Int?
        t = stripBangRuns(from: t, into: &pFromBang)

        var ctx: String?
        t = stripAtContexts(from: t, into: &ctx)

        var project: String?
        t = stripProjectPath(from: t, into: &project)

        priority = mergedPriority(pFromWord, pFromBang)
        urgency = uFromWord
        context = ctx
        projectName = project

        let cleaned = t
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedShortcuts(
            cleanedTitle: cleaned,
            contextName: context,
            priority: priority,
            urgency: urgency,
            projectName: projectName
        )
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

    private static func stripUrgencyWords(from s: String, into urgency: inout Int?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\bu([0-4])\b"#, options: []) else { return s }
        let ns = s as NSString
        var best: Int?
        regex.enumerateMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            if let u = Int(ns.substring(with: match.range(at: 1))) {
                if let b = best {
                    best = min(b, u)
                } else {
                    best = u
                }
            }
        }
        urgency = best
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
            priority = min(4, maxRun)
        }
        return regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    /// All `@token` names in order (for inline chips).
    public static func labelTagNames(in title: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"@([^\s@]+)"#, options: []) else { return [] }
        let ns = title as NSString
        var out: [String] = []
        regex.enumerateMatches(in: title, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let name = ns.substring(with: match.range(at: 1))
            if !name.isEmpty { out.append(name) }
        }
        return out
    }

    private static func stripAtContexts(from s: String, into context: inout String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"@([^\s@]+)"#, options: []) else { return s }
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

    private static func stripProjectPath(from s: String, into projectName: inout String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?:#|/|_)([^\s#]+)"#, options: []) else { return s }
        let ns = s as NSString
        var lastName: String?
        regex.enumerateMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let name = ns.substring(with: match.range(at: 1))
            if !name.isEmpty {
                lastName = name
            }
        }
        projectName = lastName
        return regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }
}
