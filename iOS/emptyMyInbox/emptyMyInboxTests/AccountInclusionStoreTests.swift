import Foundation
import Testing
import EmptyMyInboxShared

struct AccountInclusionStoreTests {
    @Test("Unknown accounts default to included for daily briefing")
    func testUnknownAccountDefaultsToIncludedForBriefing() async {
        let unknownEmail = "unknown-\(UUID().uuidString)@example.com"
        let included = await AccountInclusionStore.shared.isIncludedInDailyBriefing(accountEmail: unknownEmail)
        #expect(included == true)
    }

    @Test("Unknown accounts default to included for insights")
    func testUnknownAccountDefaultsToIncludedForInsights() async {
        let unknownEmail = "unknown-\(UUID().uuidString)@example.com"
        let included = await AccountInclusionStore.shared.isIncludedInNewsletterInsights(accountEmail: unknownEmail)
        #expect(included == true)
    }
}
