import Foundation
import Testing
@testable import LedFan

struct InputReportInboxTests {
    @Test func aReportDeliveredFirstIsReturnedAtOnce() async {
        let inbox = InputReportInbox()
        await inbox.deliver([1, 2, 3])
        #expect(await inbox.next(within: .milliseconds(50)) == [1, 2, 3])
    }

    @Test func nothingWithinTheTimeoutIsNil() async {
        let inbox = InputReportInbox()
        let started = ContinuousClock.now
        #expect(await inbox.next(within: .milliseconds(30)) == nil)
        #expect(ContinuousClock.now - started >= .milliseconds(30))
    }

    @Test func aReportDeliveredWhileWaitingWakesTheWaiter() async {
        let inbox = InputReportInbox()
        let deliverer = Task {
            try? await Task.sleep(for: .milliseconds(20))
            await inbox.deliver([9])
        }
        #expect(await inbox.next(within: .seconds(2)) == [9])
        await deliverer.value
    }

    @Test func reportsQueueInOrder() async {
        let inbox = InputReportInbox()
        await inbox.deliver([1]); await inbox.deliver([2])
        #expect(await inbox.next(within: .milliseconds(10)) == [1])
        #expect(await inbox.next(within: .milliseconds(10)) == [2])
        #expect(await inbox.next(within: .milliseconds(10)) == nil)
    }
}
