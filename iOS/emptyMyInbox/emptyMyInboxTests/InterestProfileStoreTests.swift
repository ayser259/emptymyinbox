import Foundation
import Testing
@testable import emptyMyInbox

struct InterestProfileStoreTests {
    @Test("Interest profile learns less-preference signals")
    func testInterestSignalLowersPreference() async {
        let theme = "theme-\(UUID().uuidString)"
        let sender = "sender-\(UUID().uuidString)@example.com"

        let signalA = InterestSignal(timestamp: Date(), signalType: .less, themeTag: theme, sender: sender)
        let signalB = InterestSignal(timestamp: Date(), signalType: .less, themeTag: theme, sender: sender)
        let signalC = InterestSignal(timestamp: Date(), signalType: .less, themeTag: theme, sender: sender)

        await InterestProfileStore.shared.applySignal(signalA)
        await InterestProfileStore.shared.applySignal(signalB)
        await InterestProfileStore.shared.applySignal(signalC)

        let shouldProcess = await InterestProfileStore.shared.shouldProcessNewsletter(themeTag: theme, sender: sender)
        #expect(shouldProcess == false)
    }

    @Test("Interest profile learns more-preference signals")
    func testInterestSignalRaisesPreference() async {
        let theme = "theme-\(UUID().uuidString)"
        let sender = "sender-\(UUID().uuidString)@example.com"

        let signal = InterestSignal(timestamp: Date(), signalType: .more, themeTag: theme, sender: sender)
        await InterestProfileStore.shared.applySignal(signal)

        let shouldProcess = await InterestProfileStore.shared.shouldProcessNewsletter(themeTag: theme, sender: sender)
        #expect(shouldProcess == true)
    }
}
