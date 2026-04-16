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

    /// Sidebar / grouping key: prefers linked context definition name (rename-safe) when `contextId` resolves.
    public static func contextBucketKey(for item: VaultActionItemRecord, definitions: [VaultContextDefinition]) -> String {
        if let cid = item.contextId, let def = definitions.first(where: { $0.id == cid }) {
            return normalizedSubjectKey(def.name)
        }
        return normalizedSubjectKey(item.subjectLabel)
    }

    /// Display name for labels / chips: same resolution as `contextBucketKey`, but returns `nil` when there is no named context.
    public static func resolvedContextDisplayName(for item: VaultActionItemRecord, definitions: [VaultContextDefinition]) -> String? {
        let key = contextBucketKey(for: item, definitions: definitions)
        return key == unspecifiedSubjectKey ? nil : key
    }

    /// Sorted `(subjectKey, items)` for context/channel UI. Pass `definitions` so buckets follow context renames via `contextId`.
    public static func groupedBySubject(_ items: [VaultActionItemRecord], definitions: [VaultContextDefinition] = []) -> [(key: String, items: [VaultActionItemRecord])] {
        let dict = Dictionary(grouping: items) { contextBucketKey(for: $0, definitions: definitions) }
        return dict.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { key in (key, defaultSorted(dict[key] ?? [])) }
    }

    /// Sidebar label: `#` + space + normalized subject (e.g. `# Unspecified`).
    public static func displaySubjectHash(_ label: String?) -> String {
        "# " + normalizedSubjectKey(label)
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
        let dict = Dictionary(grouping: items) { contextBucketKey(for: $0, definitions: definitions) }
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

    /// Sidebar label: `_` + spaces around segments (e.g. `_ General`, `_ Client _ Q1`). Names may still contain `/` internally; we split on `/` for hierarchy only.
    public static func displayProjectPath(_ name: String?) -> String {
        let key = normalizedProjectKey(name)
        let segments = key.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if segments.isEmpty {
            return "_ " + generalProjectName
        }
        return "_ " + segments.joined(separator: " _ ")
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

    // MARK: - Priority / urgency boards (P0…P4 / U0…U4 + None)

    /// Stable bucket id for priority boards: `p0`…`p4`, `none`, or `other` (out-of-range stored values).
    public static func priorityBucketId(for item: VaultActionItemRecord) -> String {
        guard let p = item.priority else { return "none" }
        if (0 ... 4).contains(p) { return "p\(p)" }
        return "other"
    }

    /// Stable bucket id for urgency boards: `u0`…`u4`, `none`, or `other`.
    public static func urgencyBucketId(for item: VaultActionItemRecord) -> String {
        guard let u = item.urgency else { return "none" }
        if (0 ... 4).contains(u) { return "u\(u)" }
        return "other"
    }

    /// Board columns for the Priority category: **P0…P4**, **None**, then **Other** if needed.
    public static func boardColumnsForPriority(_ items: [VaultActionItemRecord]) -> [ActionItemsBoardColumn] {
        let dict = Dictionary(grouping: items, by: priorityBucketId(for:))
        var columns: [ActionItemsBoardColumn] = []
        for id in ["p0", "p1", "p2", "p3", "p4", "none"] {
            columns.append(
                ActionItemsBoardColumn(
                    boardId: id,
                    title: priorityBoardTitle(forBoardId: id),
                    items: defaultSorted(dict[id] ?? [])
                )
            )
        }
        if let other = dict["other"], !other.isEmpty {
            columns.append(
                ActionItemsBoardColumn(boardId: "other", title: "Other", items: defaultSorted(other))
            )
        }
        return columns
    }

    /// Board columns for the Urgency category: **U0…U4**, **None**, then **Other** if needed.
    public static func boardColumnsForUrgency(_ items: [VaultActionItemRecord]) -> [ActionItemsBoardColumn] {
        let dict = Dictionary(grouping: items, by: urgencyBucketId(for:))
        var columns: [ActionItemsBoardColumn] = []
        for id in ["u0", "u1", "u2", "u3", "u4", "none"] {
            columns.append(
                ActionItemsBoardColumn(
                    boardId: id,
                    title: urgencyBoardTitle(forBoardId: id),
                    items: defaultSorted(dict[id] ?? [])
                )
            )
        }
        if let other = dict["other"], !other.isEmpty {
            columns.append(
                ActionItemsBoardColumn(boardId: "other", title: "Other", items: defaultSorted(other))
            )
        }
        return columns
    }

    /// Title for a priority board / sidebar channel (`p0`…`p4`, `none`, `other`).
    public static func priorityBoardTitle(forBoardId id: String) -> String {
        switch id {
        case "p0": return "P0"
        case "p1": return "P1"
        case "p2": return "P2"
        case "p3": return "P3"
        case "p4": return "P4"
        case "none": return "None"
        case "other": return "Other"
        default: return id
        }
    }

    /// Title for an urgency board / sidebar channel (`u0`…`u4`, `none`, `other`).
    public static func urgencyBoardTitle(forBoardId id: String) -> String {
        switch id {
        case "u0": return "U0"
        case "u1": return "U1"
        case "u2": return "U2"
        case "u3": return "U3"
        case "u4": return "U4"
        case "none": return "None"
        case "other": return "Other"
        default: return id
        }
    }

    /// Items belonging to a single priority channel.
    public static func itemsInPriorityChannel(boardId: String, items: [VaultActionItemRecord]) -> [VaultActionItemRecord] {
        defaultSorted(items.filter { priorityBucketId(for: $0) == boardId })
    }

    /// Items belonging to a single urgency channel.
    public static func itemsInUrgencyChannel(boardId: String, items: [VaultActionItemRecord]) -> [VaultActionItemRecord] {
        defaultSorted(items.filter { urgencyBucketId(for: $0) == boardId })
    }

    /// Items for one label / subject bucket (`subjectKey` is the normalized bucket key).
    public static func itemsInLabelChannel(
        subjectKey: String,
        definitions: [VaultContextDefinition],
        items: [VaultActionItemRecord]
    ) -> [VaultActionItemRecord] {
        defaultSorted(items.filter { contextBucketKey(for: $0, definitions: definitions) == subjectKey })
    }

    /// Items for one project bucket (`projectKey` matches `groupedByProject` keys).
    public static func itemsInProjectChannel(
        projectKey: String,
        definitions: [VaultProjectDefinition],
        items: [VaultActionItemRecord]
    ) -> [VaultActionItemRecord] {
        var idToDefinition: [String: VaultProjectDefinition] = [:]
        for def in definitions { idToDefinition[def.id] = def }
        return defaultSorted(items.filter { item in
            guard let pid = item.projectId, let def = idToDefinition[pid] else {
                return projectKey == generalProjectName
            }
            return normalizedProjectKey(def.name) == projectKey
        })
    }

    /// Tasks not assigned to a named project: only the default **General** bucket (same rules as `itemsInProjectChannel` for `generalProjectName`).
    public static func itemsWithoutNamedProject(
        definitions: [VaultProjectDefinition],
        items: [VaultActionItemRecord]
    ) -> [VaultActionItemRecord] {
        itemsInProjectChannel(
            projectKey: generalProjectName,
            definitions: definitions,
            items: items
        )
    }

    /// Open tasks whose `scheduledDate` falls on the same calendar day as `referenceDay`.
    public static func itemsScheduledForCalendarDay(
        referenceDay: Date = Date(),
        calendar: Calendar = .current,
        items: [VaultActionItemRecord]
    ) -> [VaultActionItemRecord] {
        defaultSorted(items.filter { item in
            guard let s = item.scheduledDate else { return false }
            return calendar.isDate(s, inSameDayAs: referenceDay)
        })
    }

    /// Open tasks with a schedule on any day in `[start, end)` (compared by start-of-day).
    public static func itemsScheduledInDateRange(
        start: Date,
        end: Date,
        calendar: Calendar = .current,
        items: [VaultActionItemRecord]
    ) -> [VaultActionItemRecord] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return defaultSorted(items.filter { item in
            guard let s = item.scheduledDate else { return false }
            let d = calendar.startOfDay(for: s)
            return d >= startDay && d < endDay
        })
    }

    /// Board columns for **Labels** (context/subject buckets); `boardId` is the normalized subject key.
    public static func boardColumnsForLabels(
        definitions: [VaultContextDefinition],
        items: [VaultActionItemRecord]
    ) -> [ActionItemsBoardColumn] {
        groupedBySubjectForSidebar(definitions: definitions, items: items).map { pair in
            ActionItemsBoardColumn(
                boardId: pair.key,
                title: displaySubjectHash(pair.key),
                items: pair.items
            )
        }
    }

    /// Board columns for **Projects**; `boardId` matches `groupedByProject` keys (e.g. `General`).
    public static func boardColumnsForProjects(
        definitions: [VaultProjectDefinition],
        items: [VaultActionItemRecord]
    ) -> [ActionItemsBoardColumn] {
        groupedByProject(definitions: definitions, items: items).map { pair in
            ActionItemsBoardColumn(
                boardId: pair.key,
                title: displayProjectPath(pair.key),
                items: pair.items
            )
        }
    }
}
