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
        XCTAssertNil(item.priority)
        XCTAssertNil(item.urgency)
        XCTAssertNil(item.projectId)
        XCTAssertNil(item.taskDescription)
    }

    func testVaultLayoutIncludesActionItemsFolder() {
        let subs = VaultLayout.standardSubfolders()
        XCTAssertTrue(subs.contains(VaultLayout.actionItemsFolder))
    }

    /// Regression: iOS and macOS must use identical relative paths (shared `VaultManager` + Drive sync).
    func testVaultActionItemAggregatePathsCrossPlatformContract() {
        XCTAssertEqual(
            VaultLayout.actionItemAggregateRelativePaths,
            [
                "ActionItems/active_items.json",
                "ActionItems/completed_items.json",
                "ActionItems/context_definitions.json",
                "ActionItems/type_definitions.json",
                "ActionItems/project_definitions.json"
            ]
        )
    }

    func testVaultActionItemIdsAndContextRoundTrip() throws {
        let original = VaultActionItemRecord(
            id: "01HZX123456789ABCDEFGHJKLM",
            title: "T",
            subjectLabel: "Work",
            contextId: "ctx-1",
            typeLabel: "Meeting",
            typeId: "type-1"
        )
        let data = try VaultJSON.encoder().encode(original)
        let back = try VaultJSON.decoder().decode(VaultActionItemRecord.self, from: data)
        XCTAssertEqual(back.id, "01HZX123456789ABCDEFGHJKLM")
        XCTAssertEqual(back.contextId, "ctx-1")
        XCTAssertEqual(back.typeId, "type-1")
    }

    func testULIDGenerateFormat() {
        let u = ULID.generate()
        XCTAssertEqual(u.count, 26)
        XCTAssertTrue(u.allSatisfy { $0.isASCII && $0.isLetter || $0.isNumber })
    }

    func testVaultEnsureStructureCreatesActionItemsFolder() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_action_items_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let backend = VaultLocalFolderBackend(vaultRoot: tmp)
        try await backend.ensureStructure()
        let actionItems = tmp.appendingPathComponent("ActionItems", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: actionItems.path))
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
            priority: 2,
            urgency: 1,
            projectId: "proj-1"
        )
        let env = VaultFileEnvelope(writeToken: 7, payload: item)
        let data = try VaultJSON.encoder().encode(env)
        let decoded = try VaultJSON.decoder().decode(VaultFileEnvelope<VaultActionItemRecord>.self, from: data)
        XCTAssertEqual(decoded.payload.title, "E")
        XCTAssertEqual(decoded.writeToken, 7)
        XCTAssertEqual(decoded.payload.urgency, 1)
        XCTAssertEqual(decoded.payload.projectId, "proj-1")
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
        let unspecified = groups.first { $0.key == ActionItemsFeatureModel.unspecifiedSubjectKey }
        XCTAssertEqual(unspecified?.items.count, 1)
    }

    func testActionItemsDefaultSortPriorityAndDone() {
        let items = [
            VaultActionItemRecord(title: "z", isDone: false, priority: 1, urgency: 2),
            VaultActionItemRecord(title: "a", isDone: true, priority: 3),
            VaultActionItemRecord(title: "m", isDone: false, priority: 3, urgency: 1)
        ]
        let sorted = ActionItemsFeatureModel.defaultSorted(items)
        XCTAssertEqual(sorted.map(\.title), ["m", "z", "a"])
    }

    func testActionItemsDefaultSortUsesIdTieBreak() {
        let items = [
            VaultActionItemRecord(id: "b", title: "t", isDone: false, priority: 1),
            VaultActionItemRecord(id: "a", title: "t", isDone: false, priority: 1)
        ]
        let sorted = ActionItemsFeatureModel.defaultSorted(items)
        XCTAssertEqual(sorted.map(\.id), ["a", "b"])
    }

    func testDisplaySubjectHash() {
        XCTAssertEqual(ActionItemsFeatureModel.displaySubjectHash(nil), "#Unspecified")
        XCTAssertEqual(ActionItemsFeatureModel.displaySubjectHash(" Work "), "#Work")
    }

    func testActionItemTitleParsingPriorityAndContext() {
        let p = ActionItemTitleParsing.parseShortcuts(from: "Buy milk p2 u1 #errands /Home")
        XCTAssertEqual(p.cleanedTitle, "Buy milk")
        XCTAssertEqual(p.priority, 2)
        XCTAssertEqual(p.urgency, 1)
        XCTAssertEqual(p.contextName, "errands")
        XCTAssertEqual(p.projectName, "Home")
    }

    func testActionItemTitleParsingBangPriority() {
        let p = ActionItemTitleParsing.parseShortcuts(from: "Task !!!")
        XCTAssertEqual(p.cleanedTitle, "Task")
        XCTAssertEqual(p.priority, 2)
    }

    func testActiveHashSuffix() {
        let s = "Hello #tra"
        let r = ActionItemTitleParsing.activeHashSuffix(in: s)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.query, "tra")
    }

    /// Snapshot inheritance for subtasks (same fields `createChildTask` copies).
    func testActionItemChildSnapshotFromParent() {
        let parent = VaultActionItemRecord(
            title: "Parent",
            priority: 2,
            urgency: 1,
            taskDescription: "Desc",
            contextNotes: "Ctx",
            subjectLabel: "Team",
            typeLabel: "Meeting",
            projectId: "p1"
        )
        let now = Date()
        let child = VaultActionItemRecord(
            title: "Child",
            priority: parent.priority,
            urgency: parent.urgency,
            taskDescription: parent.taskDescription,
            contextNotes: parent.contextNotes,
            comments: [],
            parentTaskId: parent.id,
            subjectLabel: parent.subjectLabel,
            typeLabel: parent.typeLabel,
            projectId: parent.projectId,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
        XCTAssertEqual(child.subjectLabel, parent.subjectLabel)
        XCTAssertEqual(child.typeLabel, parent.typeLabel)
        XCTAssertEqual(child.priority, parent.priority)
        XCTAssertEqual(child.urgency, parent.urgency)
        XCTAssertEqual(child.taskDescription, parent.taskDescription)
        XCTAssertEqual(child.contextNotes, parent.contextNotes)
        XCTAssertEqual(child.projectId, parent.projectId)
        XCTAssertEqual(child.parentTaskId, parent.id)
    }

    func testDedupedContextPickerEntries() {
        let defs = [
            VaultContextDefinition(id: "1", name: "Unspecified", sortOrder: 0),
            VaultContextDefinition(id: "2", name: "Inbox", sortOrder: 1),
            VaultContextDefinition(id: "3", name: "Work", sortOrder: 2)
        ]
        let entries = ActionItemsFeatureModel.dedupedContextPickerEntries(definitions: defs)
        XCTAssertEqual(entries.first?.key, ActionItemsFeatureModel.unspecifiedSubjectKey)
        XCTAssertEqual(entries.filter { $0.key == ActionItemsFeatureModel.unspecifiedSubjectKey }.count, 1)
        XCTAssertTrue(entries.contains(where: { $0.key == "Work" }))
    }

    func testGroupedByProjectHasGeneralFallback() {
        let defs = [
            VaultProjectDefinition(id: "p1", name: "Home", sortOrder: 0)
        ]
        let items = [
            VaultActionItemRecord(title: "A", projectId: nil),
            VaultActionItemRecord(title: "B", projectId: "p1")
        ]
        let groups = ActionItemsFeatureModel.groupedByProject(definitions: defs, items: items)
        XCTAssertTrue(groups.contains(where: { $0.key == ActionItemsFeatureModel.generalProjectName }))
        XCTAssertTrue(groups.contains(where: { $0.key == "Home" }))
    }

    // MARK: - Vault manifest & discovery

    func testVaultManifestRoundTripWithDriveMetadataNil() throws {
        let original = VaultManifest(
            vaultId: "vid",
            backendKind: .googleDrive,
            driveRootFolderId: nil,
            driveAccountEmail: nil,
            displayName: nil
        )
        let data = try VaultJSON.encoder().encode(original)
        let back = try VaultJSON.decoder().decode(VaultManifest.self, from: data)
        XCTAssertEqual(back.vaultId, "vid")
        XCTAssertEqual(back.backendKind, .googleDrive)
        XCTAssertNil(back.driveRootFolderId)
        XCTAssertNil(back.driveAccountEmail)
        XCTAssertNil(back.displayName)
    }

    func testVaultManifestRoundTripWithDriveMetadataSet() throws {
        let original = VaultManifest(
            vaultId: "vid",
            backendKind: .googleDrive,
            driveRootFolderId: "folder123",
            driveAccountEmail: "u@x.com",
            displayName: "My vault"
        )
        let data = try VaultJSON.encoder().encode(original)
        let back = try VaultJSON.decoder().decode(VaultManifest.self, from: data)
        XCTAssertEqual(back.driveRootFolderId, "folder123")
        XCTAssertEqual(back.driveAccountEmail, "u@x.com")
        XCTAssertEqual(back.displayName, "My vault")
    }

    func testGoogleDriveFolderWebURL() {
        XCTAssertNil(GoogleDriveWebLinks.folderURL(folderId: ""))
        XCTAssertNil(GoogleDriveWebLinks.folderURL(folderId: "   "))
        XCTAssertEqual(
            GoogleDriveWebLinks.folderURL(folderId: "abc")?.absoluteString,
            "https://drive.google.com/drive/folders/abc"
        )
        let noId = VaultActiveConfiguration(backend: .googleDrive, driveRootFolderId: nil)
        XCTAssertNil(noId.googleDriveRootWebURL)
        let local = VaultActiveConfiguration(backend: .local)
        XCTAssertNil(local.googleDriveRootWebURL)
        let drive = VaultActiveConfiguration(backend: .googleDrive, driveRootFolderId: "root1")
        XCTAssertEqual(drive.googleDriveRootWebURL?.absoluteString, "https://drive.google.com/drive/folders/root1")
        let remote = DiscoveredRemoteGoogleDriveVaultSummary(
            vaultId: "vid",
            driveRootFolderId: "root2",
            displayName: "Remote",
            connectedAccountEmail: "u@x.com"
        )
        XCTAssertEqual(remote.googleDriveRootWebURL?.absoluteString, "https://drive.google.com/drive/folders/root2")
    }

    func testVaultDiscoveryListsLocalMirrors() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault_disc_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let vaultId = UUID().uuidString
        let vaultDir = base.appendingPathComponent(vaultId, isDirectory: true)
        try FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        let manifest = VaultManifest(
            vaultId: vaultId,
            backendKind: .local,
            displayName: "Alpha"
        )
        let data = try VaultJSON.encoder().encode(manifest)
        try data.write(to: vaultDir.appendingPathComponent(VaultLayout.manifestFileName))
        let found = VaultDiscovery.discoverLocalMirrorVaults(vaultsDirectory: base)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.vaultId, vaultId)
        XCTAssertEqual(found.first?.backendKind, .local)
        XCTAssertEqual(found.first?.displayName, "Alpha")
    }
}
