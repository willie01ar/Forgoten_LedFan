import Foundation

/// Stores messages in memory instead of on a fan. Also the seam unit tests write against.
actor SimulatedFanTransport: FanDisplayTransport {
    nonisolated let displayName = "Simulated fan"
    nonisolated let storeAvailability: FanStoreAvailability = .available
    /// A simulated fan is never unplugged; the stream simply never yields.
    nonisolated let connectionEvents: AsyncStream<FanConnectionEvent>

    /// Every message handed to `store(_:)`, newest wins. Single consumer; a test seam (D3).
    nonisolated let storedMessages: AsyncStream<FanMessage>

    private let fanGeometry: FanGeometry
    private let continuation: AsyncStream<FanMessage>.Continuation
    private let eventsContinuation: AsyncStream<FanConnectionEvent>.Continuation
    private var slots: [Int: FanMessage] = [:]
    private var isConnected = false

    init(geometry: FanGeometry = .preview) {
        fanGeometry = geometry
        let stream = AsyncStream.makeStream(of: FanMessage.self, bufferingPolicy: .bufferingNewest(1))
        storedMessages = stream.stream
        continuation = stream.continuation
        let events = AsyncStream.makeStream(of: FanConnectionEvent.self)
        connectionEvents = events.stream
        eventsContinuation = events.continuation
    }

    var geometry: FanGeometry { fanGeometry }

    /// What the simulated fan holds in a slot, for tests and previews.
    func message(inSlot slot: Int) -> FanMessage? { slots[slot] }

    // MARK: - FanDisplayTransport

    func connect() async throws { isConnected = true }

    /// Like the real fan, a store replaces the whole set: slots not sent are cleared.
    func store(_ messages: [FanMessage]) async throws -> FanStoreReceipt {
        guard isConnected else { throw FanTransportError.notConnected }
        slots = Dictionary(messages.map { ($0.slot, $0) }, uniquingKeysWith: { _, last in last })
        for message in messages { continuation.yield(message) }
        let filled = messages.count { !$0.text.isEmpty }
        return FanStoreReceipt(summary: "Stored \(messages.count) slots on the simulated fan, \(filled) with text.",
                               reportCount: 0, byteCount: 0, confirmedCount: 0)
    }

    func disconnect() async { isConnected = false }
}
