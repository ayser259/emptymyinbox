import XCTest
@testable import ProjectJadeShared

final class ProjectJadeSharedTests: XCTestCase {
    func testStableIDDeterministic() {
        let a = StableID.accountId(email: "a@b.com")
        let b = StableID.accountId(email: "a@b.com")
        XCTAssertEqual(a, b)
    }
}
