import Foundation

/// Stores messages in memory instead of on a fan. Also the seam unit tests write against.
actor SimulatedFanTransport: FanDisplayTransport {
    nonisolated let displayName = "Simulated fan"
    nonisolated let storeAvailability: FanStoreAvailability = .available

    /// Every message handed to `store(_:)`, newest wins. Single consumer; a test seam (D3).
    nonisolated let storedMessages: AsyncStream<FanMessage>

    private let fanGeometry: FanGeometry
    private let continuation: AsyncStream<FanMessage>.Continuation
    private var slots: [Int: FanMessage] = [:]
    private var isConnected = false

    init(geometry: FanGeometry = .preview) {
        fanGeometry = geometry
        let stream = AsyncStream.makeStream(of: FanMessage.self, bufferingPolicy: .bufferingNewest(1))
        storedMessages = stream.stream
        continuation = stream.continuation
    }

    var geometry: FanGeometry { fanGeometry }

    /// What the simulated fan holds in a slot, for tests and previews.
    func message(inSlot slot: Int) -> FanMessage? { slots[slot] }

    // MARK: - FanDisplayTransport

    func connect() async throws { isConnected = true }

    func store(_ message: FanMessage) async throws -> FanStoreReceipt {
        guard isConnected else { throw FanTransportError.notConnected }
        slots[message.slot] = message
        continuation.yield(message)
        return FanStoreReceipt(summary: "Stored in slot \(message.displayNumber) on the simulated fan.",
                               reportCount: 0, byteCount: 0, acknowledged: true)
    }

    func disconnect() async { isConnected = false }
}
