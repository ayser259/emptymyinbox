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
}
