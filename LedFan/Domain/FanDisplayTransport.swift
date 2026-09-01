import Foundation

/// What a fan can do, independent of how it is wired.
nonisolated protocol FanDisplayTransport: Sendable {
    nonisolated var displayName: String { get }
    var ledsPerArm: Int { get async }

    func connect() async throws
    func display(_ frame: POVFrame) async throws
    func disconnect() async
}

nonisolated enum FanTransportError: Error, Sendable, Equatable {
    case deviceNotFound
    case openFailed(code: Int32)
    case notConnected
    case writeFailed(code: Int32)
    case protocolNotYetKnown
}

extension FanTransportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "No LED fan found. The USB-A cable only powers the fan; the data cable must be in the fan's second port."
        case .openFailed(let code):
            return "Found the fan but could not open it (IOKit error \(code))."
        case .notConnected:
            return "Not connected to the fan."
        case .writeFailed(let code):
            return "The fan rejected the write (IOKit error \(code))."
        case .protocolNotYetKnown:
            return "The fan's command format has not been reverse-engineered yet."
        }
    }
}
