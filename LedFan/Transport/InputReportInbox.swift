import Foundation

/// Collects the fan's input reports as IOKit delivers them, and hands them out one at a
/// time with a timeout. Reports that arrive while nobody is waiting queue up, as they would
/// in the reference driver's read buffer.
actor InputReportInbox {
    private var queue: [[UInt8]] = []
    private var waiter: CheckedContinuation<[UInt8]?, Never>?

    func deliver(_ report: [UInt8]) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: report)
        } else {
            queue.append(report)
        }
    }

    /// The next report, or nil if none arrives within `timeout`.
    func next(within timeout: Duration) async -> [UInt8]? {
        if !queue.isEmpty { return queue.removeFirst() }
        let expiry = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.expire()
        }
        let report = await withCheckedContinuation { waiter = $0 }
        expiry.cancel()
        return report
    }

    func drain() { queue.removeAll() }

    private func expire() {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: nil)
    }
}

/// Set by IOKit's removal callback; read by the transport before it trusts its handle.
actor RemovalFlag {
    private(set) var isRemoved = false

    func markRemoved() { isRemoved = true }
    func reset() { isRemoved = false }
}

/// The context object handed to the C callbacks. Everything it holds is Sendable, so the
/// callbacks can reach the actors without a reference back to the transport.
nonisolated final class DeviceCallbackBridge: Sendable {
    let inbox: InputReportInbox
    let removal: RemovalFlag
    let events: AsyncStream<FanConnectionEvent>.Continuation

    init(inbox: InputReportInbox, removal: RemovalFlag, events: AsyncStream<FanConnectionEvent>.Continuation) {
        self.inbox = inbox
        self.removal = removal
        self.events = events
    }
}
