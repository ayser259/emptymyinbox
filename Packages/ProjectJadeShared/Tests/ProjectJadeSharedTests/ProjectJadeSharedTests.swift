import XCTest
@testable import ProjectJadeShared

final class ProjectJadeSharedTests: XCTestCase {
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

    func testVaultLayoutIncludesStoriesAndBriefFolders() {
        let subs = VaultLayout.standardSubfolders()
        XCTAssertTrue(subs.contains(VaultLayout.storiesFolder))
        XCTAssertTrue(subs.contains(VaultLayout.briefFolder))
        XCTAssertTrue(subs.contains("\(VaultLayout.inboxFolder)/\(VaultLayout.inboxThreadsSubfolder)"))
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
        let path = "\(VaultLayout.inboxFolder)/\(VaultLayout.inboxThreadsSubfolder)/t1.json"
        let thread = VaultInboxThreadRecord(id: "t1", threadId: "thread-1", title: "Hello")
        let token = VaultLWWHelpers.nextWriteToken(existingData: nil)
        let env = VaultFileEnvelope(updatedAt: Date(), writeToken: token, payload: thread)
        let data = try VaultJSON.encoder().encode(env)
        try await backend.write(relativePath: path, data: data)
        let read = try await backend.read(relativePath: path)
        let decoded = try VaultJSON.decoder().decode(VaultFileEnvelope<VaultInboxThreadRecord>.self, from: read)
        XCTAssertEqual(decoded.payload.title, "Hello")
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