import XCTest
@testable import EmptyMyInboxShared

final class SentMessageStoreTests: XCTestCase {
    override func setUp() async throws {
        await SentMessageStore.shared.removeAll()
    }

    override func tearDown() async throws {
        await SentMessageStore.shared.removeAll()
    }

    func testRecordAndLoadOrdersNewestFirst() async {
        let older = SentMessageRecord(
            gmailMessageId: "msg-old",
            threadId: "thread-1",
            accountEmail: "user@test.com",
            sentAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = SentMessageRecord(
            gmailMessageId: "msg-new",
            threadId: "thread-2",
            accountEmail: "user@test.com",
            sentAt: Date(timeIntervalSince1970: 2_000)
        )

        await SentMessageStore.shared.record(older)
        await SentMessageStore.shared.record(newer)

        let loaded = await SentMessageStore.shared.loadAll()
        XCTAssertEqual(loaded.map(\.gmailMessageId), ["msg-new", "msg-old"])
    }

    func testDuplicateGmailMessageIdUpdatesExistingRecord() async {
        let first = SentMessageRecord(
            gmailMessageId: "msg-dup",
            threadId: "thread-a",
            draftId: "draft-1",
            accountEmail: "user@test.com",
            sentAt: Date(timeIntervalSince1970: 1_000),
            replyMode: "reply"
        )
        let second = SentMessageRecord(
            gmailMessageId: "msg-dup",
            threadId: "thread-b",
            draftId: "draft-2",
            accountEmail: "user@test.com",
            sentAt: Date(timeIntervalSince1970: 2_000),
            replyMode: "reply_all"
        )

        await SentMessageStore.shared.record(first)
        await SentMessageStore.shared.record(second)

        let loaded = await SentMessageStore.shared.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.threadId, "thread-b")
        XCTAssertEqual(loaded.first?.draftId, "draft-2")
        XCTAssertEqual(loaded.first?.replyMode, "reply_all")
        let containsDup = await SentMessageStore.shared.contains(gmailMessageId: "msg-dup")
        XCTAssertTrue(containsDup)
    }

    func testLoadForAccountEmailFiltersCaseInsensitively() async {
        await SentMessageStore.shared.record(
            SentMessageRecord(
                gmailMessageId: "msg-a",
                threadId: "t1",
                accountEmail: "User@Test.com"
            )
        )
        await SentMessageStore.shared.record(
            SentMessageRecord(
                gmailMessageId: "msg-b",
                threadId: "t2",
                accountEmail: "other@test.com"
            )
        )

        let loaded = await SentMessageStore.shared.load(forAccountEmail: "user@test.com")
        XCTAssertEqual(loaded.map(\.gmailMessageId), ["msg-a"])
    }
}
