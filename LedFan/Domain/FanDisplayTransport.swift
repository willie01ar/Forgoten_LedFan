import Foundation

/// Whether a transport can accept messages, and on what terms.
nonisolated enum FanStoreAvailability: Sendable, Equatable {
    case available
    /// Bytes go out, but a display is not expected. The caveat says why, for the user.
    case experimental(caveat: String)
    case unavailable(reason: String)
}

/// What a store actually did, in the user's terms. Never implies a display.
nonisolated struct FanStoreReceipt: Sendable, Equatable {
    let summary: String
    let reportCount: Int
    let byteCount: Int
    /// True only when every report was acknowledged.
    let acknowledged: Bool
    let acknowledgementCount: Int
    let packetLog: URL?

    init(summary: String, reportCount: Int, byteCount: Int, acknowledged: Bool, acknowledgementCount: Int = 0, packetLog: URL? = nil) {
        self.summary = summary
        self.reportCount = reportCount
        self.byteCount = byteCount
        self.acknowledged = acknowledged
        self.acknowledgementCount = acknowledgementCount
        self.packetLog = packetLog
    }
}

/// What a fan can do, independent of how it is wired. The unit of work is a message in a
/// slot (D5); on hardware, storing means writing the head's table, not showing anything.
nonisolated protocol FanDisplayTransport: Sendable {
    nonisolated var displayName: String { get }
    nonisolated var storeAvailability: FanStoreAvailability { get }
    var geometry: FanGeometry { get async }

    func connect() async throws
    func store(_ message: FanMessage) async throws -> FanStoreReceipt
    func disconnect() async
}

nonisolated enum FanTransportError: Error, Sendable, Equatable {
    case deviceNotFound
    case openFailed(code: Int32)
    case notConnected
    case writeFailed(code: Int32)
    case nothingToStore
    case tableTooLarge(bytes: Int, limit: Int)
    case imageTooWide(columns: Int, limit: Int)
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
        case .nothingToStore:
            return "The message is empty, so there is nothing to write."
        case .tableTooLarge(let bytes, let limit):
            return "The message table is \(bytes) bytes; the fan's store holds \(limit). Nothing was written."
        case .imageTooWide(let columns, let limit):
            return "The message is \(columns) columns wide; the fan shows \(limit). Nothing was written."
        }
    }
}
