//
//  ActionItemsFeatureModel.swift
//  EmptyMyInboxShared
//
//  Filtering, grouping, and sorting for vault-backed action items (shared by iOS and macOS).
//

import Foundation

/// Filtering, grouping, and sorting for vault-backed action items.
/// Call sites should pass **active** items from `VaultManager.listActionItems()` (completed items are in `ActionItems/completed_items.json`).
public enum ActionItemsFeatureModel {
    // MARK: - Subject / context

    /// Canonical bucket for items without a named context (sidebar grouping).
    public static let unspecifiedSubjectKey = "Unspecified"

    /// Display key for sidebar grouping; empty, legacy inbox/uncategorized → `unspecifiedSubjectKey`.
    public static func normalizedSubjectKey(_ label: String?) -> String {
        let t = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return unspecifiedSubjectKey }
        let lower = t.lowercased()
        if lower == "inbox" || lower == "uncategorized" { return unspecifiedSubjectKey }
        return t
    }

    /// Sorted `(subjectKey, items)` for context/channel UI.
    public static func groupedBySubject(_ items: [VaultActionItemRecord]) -> [(key: String, items: [VaultActionItemRecord])] {
        let dict = Dictionary(grouping: items) { normalizedSubjectKey($0.subjectLabel) }
        return dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { key in (key, defaultSorted(dict[key] ?? [])) }
    }

    /// Sidebar label: `#` + normalized subject (e.g. `#Unspecified`).
    public static func displaySubjectHash(_ label: String?) -> String {
        "#" + normalizedSubjectKey(label)
    }

    public struct ContextPickerEntry: Equatable {
        public var key: String
        public var context: VaultContextDefinition?
    }

    /// Lookup a saved context definition for a sidebar bucket key.
    public static func contextDefinition(matchingSubjectKey key: String, definitions: [VaultContextDefinition]) -> VaultContextDefinition? {
        definitions.first { normalizedSubjectKey($0.name) == key }
    }

    /// Menu source for context pickers/autocomplete with one synthetic `Unspecified` row and no duplicates.
    public static func dedupedContextPickerEntries(definitions: [VaultContextDefinition]) -> [ContextPickerEntry] {
        var seen = Set<String>()
        var entries: [ContextPickerEntry] = []
        entries.append(ContextPickerEntry(key: unspecifiedSubjectKey, context: nil))
        seen.insert(unspecifiedSubjectKey.lowercased())
        let sorted = definitions.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        for def in sorted {
            let normalized = normalizedSubjectKey(def.name)
            let canonicalKey = normalized.lowercased()
            guard !seen.contains(canonicalKey) else { continue }
            seen.insert(canonicalKey)
            entries.append(ContextPickerEntry(key: normalized, context: def))
        }
        return entries
    }

    /// Context sidebar: `#Unspecified` first, then all definitions (by sort order), then any item-only buckets.
    public static func groupedBySubjectForSidebar(
        definitions: [VaultContextDefinition],
        items: [VaultActionItemRecord]
    ) -> [(key: String, items: [VaultActionItemRecord])] {
        let dict = Dictionary(grouping: items) { normalizedSubjectKey($0.subjectLabel) }
        let keys = orderedContextSidebarKeys(definitions: definitions, itemKeys: Array(dict.keys))
        return keys.map { k in (k, defaultSorted(dict[k] ?? [])) }
    }

    private static func orderedContextSidebarKeys(
        definitions: [VaultContextDefinition],
        itemKeys: [String]
    ) -> [String] {
        var result: [String] = [unspecifiedSubjectKey]
        let sortedDefs = definitions.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        for d in sortedDefs {
            let k = normalizedSubjectKey(d.name)
            if k == unspecifiedSubjectKey { continue }
            if !result.contains(k) { result.append(k) }
        }
        for k in itemKeys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            if !result.contains(k) { result.append(k) }
        }
        return result
    }

    // MARK: - Sorting

    /// Primary list sort: incomplete first, then urgency (`u0`...`u4`), then priority (`p0`...`p4`), then stable `id`.
    public static func defaultSorted(_ items: [VaultActionItemRecord]) -> [VaultActionItemRecord] {
        items.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone && b.isDone }
            let ua = a.urgency ?? 999
            let ub = b.urgency ?? 999
            if ua != ub { return ua < ub }
            let pa = a.priority.map { $0 } ?? 999
            let pb = b.priority.map { $0 } ?? 999
            if pa != pb { return pa < pb }
            return a.id < b.id
        }
    }

    // MARK: - Projects

    public static let generalProjectName = "General"

    public static func normalizedProjectKey(_ name: String?) -> String {
        let t = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return generalProjectName }
        return t
    }

    public static func displayProjectPath(_ name: String?) -> String {
        "/" + normalizedProjectKey(name)
    }

    public static func groupedByProject(
        definitions: [VaultProjectDefinition],
        items: [VaultActionItemRecord]
    ) -> [(key: String, items: [VaultActionItemRecord])] {
        var idToDefinition: [String: VaultProjectDefinition] = [:]
        for def in definitions { idToDefinition[def.id] = def }
        let grouped = Dictionary(grouping: items) { item -> String in
            guard let pid = item.projectId, let def = idToDefinition[pid] else { return generalProjectName }
            return normalizedProjectKey(def.name)
        }
        var keys = [generalProjectName]
        for def in definitions.sorted(by: { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }) {
            let key = normalizedProjectKey(def.name)
            if !keys.contains(key) { keys.append(key) }
        }
        for key in grouped.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) where !keys.contains(key) {
            keys.append(key)
        }
        return keys.map { ($0, defaultSorted(grouped[$0] ?? [])) }
    }
}
