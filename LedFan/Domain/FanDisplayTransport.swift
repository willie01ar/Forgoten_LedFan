import Foundation

/// Whether a transport can accept messages at all. Unavailable carries copy for the user.
nonisolated enum FanStoreAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)
}

/// What a fan can do, independent of how it is wired. The unit of work is a message in a
/// slot (D5); on hardware, storing means writing the head's table, not showing anything.
nonisolated protocol FanDisplayTransport: Sendable {
    nonisolated var displayName: String { get }
    nonisolated var storeAvailability: FanStoreAvailability { get }
    var geometry: FanGeometry { get async }

    func connect() async throws
    func store(_ message: FanMessage) async throws
    func disconnect() async
}

nonisolated enum FanTransportError: Error, Sendable, Equatable {
    case deviceNotFound
    case openFailed(code: Int32)
    case notConnected
    case writeFailed(code: Int32)
    case protocolNotYetKnown
    case writingDisabled
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
            return "The fan's message format isn't known yet, so messages can't be sent to it. Connecting still works and shows what the fan reports."
        case .writingDisabled:
            return "This version of the app never writes to the fan. Nothing was sent."
        }
    }
}
