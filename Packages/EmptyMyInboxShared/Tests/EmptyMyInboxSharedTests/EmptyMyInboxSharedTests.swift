import XCTest
@testable import EmptyMyInboxShared

final class EmptyMyInboxSharedTests: XCTestCase {
    func testStableIDDeterministic() {
        let a = StableID.accountId(email: "a@b.com")
        let b = StableID.accountId(email: "a@b.com")
        XCTAssertEqual(a, b)
    }

    func testVaultLWWPreferNewerUpdatedAt() {
        let older = VaultLWWHelpers.EnvelopeMeta(updatedAt: Date(timeIntervalSince1970: 1_000), writeToken: 99)
        let newerLocal = VaultLWWHelpers.EnvelopeMeta(updatedAt: Date(timeIntervalSince1970: 2_000), writeToken: 1)
        XCTAssertTrue(
            VaultLWWHelpers.shouldPreferLocal(
                localMeta: newerLocal,
                localFileModDate: nil,
                remoteMeta: older,
                remoteDriveModified: nil
            )
        )
        XCTAssertFalse(
            VaultLWWHelpers.shouldPreferLocal(
                localMeta: older,
                localFileModDate: nil,
                remoteMeta: newerLocal,
                remoteDriveModified: nil
            )
        )
    }

    func testVaultLWWTieBreakerWriteToken() {
        let sameDate = Date(timeIntervalSince1970: 5_000)
        let a = VaultLWWHelpers.EnvelopeMeta(updatedAt: sameDate, writeToken: 2)
        let b = VaultLWWHelpers.EnvelopeMeta(updatedAt: sameDate, writeToken: 1)
        XCTAssertTrue(
            VaultLWWHelpers.shouldPreferLocal(
                localMeta: a,
                localFileModDate: nil,
                remoteMeta: b,
                remoteDriveModified: nil
            )
        )
    }

    func testNextWriteTokenIncrementsFromJSON() throws {
        let envelope: [String: Any] = [
            "schemaVersion": 1,
            "updatedAt": "2024-01-01T00:00:00Z",
            "writeToken": 5,
            "payload": [String: String]()
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let next = VaultLWWHelpers.nextWriteToken(existingData: data)
        XCTAssertEqual(next, 6)
    }

    func testVaultLocalFolderRoundTrip() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let backend = VaultLocalFolderBackend(vaultRoot: tmp)
        try await backend.ensureStructure()
        let path = "\(VaultLayout.calendarFolder)/\(VaultLayout.calendarEventsSubfolder)/e1.json"
        let event = VaultCalendarEventRecord(id: "e1", title: "Hello")
        let token = VaultLWWHelpers.nextWriteToken(existingData: nil)
        let env = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: event)
        let data = try VaultJSON.encoder().encode(env)
        try await backend.write(relativePath: path, data: data)
        let read = try await backend.read(relativePath: path)
        let decoded = try VaultJSON.decoder().decode(VaultFileEnvelope<VaultCalendarEventRecord>.self, from: read)
        XCTAssertEqual(decoded.payload.title, "Hello")
        let listed = try await backend.listRelativeFilePaths()
        let normalized = listed.map { $0.replacingOccurrences(of: "\\", with: "/") }
        XCTAssertTrue(
            normalized.contains(path),
            "Expected path \(path) in \(normalized)"
        )
    }

    // MARK: - Action items model & feature logic

    func testVaultActionItemBackwardCompatibleDecode() throws {
        let json = """
        {"id":"legacy-1","title":"Legacy task","isDone":true,"notes":"hello"}
        """.data(using: .utf8)!
        let item = try VaultJSON.decoder().decode(VaultActionItemRecord.self, from: json)
        XCTAssertEqual(item.id, "legacy-1")
        XCTAssertEqual(item.title, "Legacy task")
        XCTAssertTrue(item.isDone)
        XCTAssertEqual(item.notes, "hello")
        XCTAssertTrue(item.comments.isEmpty)
        XCTAssertNil(item.startDate)
        XCTAssertNil(item.priority)
        XCTAssertNil(item.taskDescription)
    }

    func testVaultActionItemDescriptionCodingKeyRoundTrip() throws {
        let original = VaultActionItemRecord(
            title: "T",
            priority: 3,
            taskDescription: "Doc body",
            contextNotes: "ctx",
            comments: [VaultActionItemCommentRecord(text: "note")],
            subjectLabel: "Inbox",
            typeLabel: "Meeting"
        )
        let data = try VaultJSON.encoder().encode(original)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["description"] as? String, "Doc body")
        let back = try VaultJSON.decoder().decode(VaultActionItemRecord.self, from: data)
        XCTAssertEqual(back.taskDescription, "Doc body")
        XCTAssertEqual(back.priority, 3)
        XCTAssertEqual(back.comments.count, 1)
    }

    func testVaultActionItemEnvelopeRoundTrip() throws {
        let item = VaultActionItemRecord(
            title: "E",
            startDate: Date(timeIntervalSince1970: 86_400),
            endDate: Date(timeIntervalSince1970: 172_800)
        )
        let env = VaultFileEnvelope(writeToken: 7, payload: item)
        let data = try VaultJSON.encoder().encode(env)
        let decoded = try VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data)
        XCTAssertEqual(decoded.payload.title, "E")
        XCTAssertEqual(decoded.writeToken, 7)
        XCTAssertEqual(decoded.payload.startDate, item.startDate)
    }

    func testActionItemsOverlapsCalendarDay() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2025
        c.month = 6
        c.day = 10
        let day = cal.date(from: c)!
        let start = cal.date(from: DateComponents(year: 2025, month: 6, day: 10, hour: 22))!
        let item = VaultActionItemRecord(title: "A", startDate: start, endDate: nil)
        XCTAssertTrue(ActionItemsFeatureModel.overlapsCalendarDay(item, day: day, calendar: cal))
    }

    func testActionItemsTodayListIncludesUnscheduled() {
        let cal = Calendar(identifier: .gregorian)
        var c = DateComponents()
        c.year = 2025
        c.month = 6
        c.day = 10
        let ref = cal.date(from: c)!
        let onDay = VaultActionItemRecord(
            title: "On day",
            startDate: cal.date(from: DateComponents(year: 2025, month: 6, day: 10, hour: 8))!
        )
        let unscheduled = VaultActionItemRecord(title: "No dates")
        let otherDay = VaultActionItemRecord(
            title: "Other",
            startDate: cal.date(from: DateComponents(year: 2025, month: 6, day: 11, hour: 8))!
        )
        let items = [onDay, unscheduled, otherDay]
        let result = ActionItemsFeatureModel.itemsForTodayList(items, referenceDay: ref, calendar: cal)
        XCTAssertEqual(result.scheduled.count, 1)
        XCTAssertEqual(result.scheduled.first?.title, "On day")
        XCTAssertEqual(result.unscheduled.count, 1)
        XCTAssertEqual(result.unscheduled.first?.title, "No dates")
    }

    func testActionItemsGroupedBySubject() {
        let items = [
            VaultActionItemRecord(title: "a", subjectLabel: " Work "),
            VaultActionItemRecord(title: "b", subjectLabel: nil),
            VaultActionItemRecord(title: "c", subjectLabel: "Work")
        ]
        let groups = ActionItemsFeatureModel.groupedBySubject(items)
        XCTAssertEqual(groups.count, 2)
        let work = groups.first { $0.key == "Work" }
        XCTAssertEqual(work?.items.count, 2)
        let unc = groups.first { $0.key == "Uncategorized" }
        XCTAssertEqual(unc?.items.count, 1)
    }

    func testActionItemsRangeFilter() {
        let cal = Calendar(identifier: .gregorian)
        let r0 = cal.date(from: DateComponents(year: 2025, month: 3, day: 1))!
        let r1 = cal.date(from: DateComponents(year: 2025, month: 3, day: 31))!
        let inside = VaultActionItemRecord(
            title: "i",
            startDate: cal.date(from: DateComponents(year: 2025, month: 3, day: 15))!
        )
        let outside = VaultActionItemRecord(
            title: "o",
            startDate: cal.date(from: DateComponents(year: 2025, month: 4, day: 1))!
        )
        let noDates = VaultActionItemRecord(title: "n")
        let out = ActionItemsFeatureModel.itemsIntersectingRange(
            [inside, outside, noDates],
            rangeStart: r0,
            rangeEnd: r1,
            calendar: cal
        )
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.title, "i")
    }

    func testActionItemsDefaultSortPriorityAndDone() {
        let items = [
            VaultActionItemRecord(title: "z", isDone: false, priority: 1),
            VaultActionItemRecord(title: "a", isDone: true, priority: 3),
            VaultActionItemRecord(title: "m", isDone: false, priority: 3)
        ]
        let sorted = ActionItemsFeatureModel.defaultSorted(items)
        XCTAssertEqual(sorted.map(\.title), ["m", "z", "a"])
    }

    /// Snapshot inheritance for subtasks (same fields `createChildTask` copies).
    func testActionItemChildSnapshotFromParent() {
        let parent = VaultActionItemRecord(
            title: "Parent",
            priority: 2,
            taskDescription: "Desc",
            contextNotes: "Ctx",
            subjectLabel: "Team",
            typeLabel: "Meeting"
        )
        let now = Date()
        let child = VaultActionItemRecord(
            title: "Child",
            startDate: nil,
            endDate: nil,
            priority: parent.priority,
            taskDescription: parent.taskDescription,
            contextNotes: parent.contextNotes,
            comments: [],
            parentTaskId: parent.id,
            subjectLabel: parent.subjectLabel,
            typeLabel: parent.typeLabel,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
        XCTAssertEqual(child.subjectLabel, parent.subjectLabel)
        XCTAssertEqual(child.typeLabel, parent.typeLabel)
        XCTAssertEqual(child.priority, parent.priority)
        XCTAssertEqual(child.taskDescription, parent.taskDescription)
        XCTAssertEqual(child.contextNotes, parent.contextNotes)
        XCTAssertNil(child.startDate)
        XCTAssertEqual(child.parentTaskId, parent.id)
    }
}
