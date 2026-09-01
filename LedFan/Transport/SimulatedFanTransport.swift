import Foundation

/// Renders to the on-screen fan instead of hardware. Also the seam unit tests write against.
actor SimulatedFanTransport: FanDisplayTransport {
    nonisolated let displayName = "Simulated fan"

    /// Every frame handed to `display(_:)`, newest wins. Single consumer.
    nonisolated let frames: AsyncStream<POVFrame>

    private let arms: Int
    private let continuation: AsyncStream<POVFrame>.Continuation
    private var isConnected = false

    init(ledsPerArm: Int = 11) {
        arms = ledsPerArm
        let stream = AsyncStream.makeStream(of: POVFrame.self, bufferingPolicy: .bufferingNewest(1))
        frames = stream.stream
        continuation = stream.continuation
    }

    var ledsPerArm: Int { arms }

    // MARK: - FanDisplayTransport

    func connect() async throws { isConnected = true }

    func display(_ frame: POVFrame) async throws {
        guard isConnected else { throw FanTransportError.notConnected }
        continuation.yield(frame)
    }

    func disconnect() async { isConnected = false }
}
