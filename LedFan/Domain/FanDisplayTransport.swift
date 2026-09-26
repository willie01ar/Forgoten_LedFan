import Foundation

/// Whether a transport can accept messages, and on what terms.
nonisolated enum FanStoreAvailability: Sendable, Equatable {
    case available
    /// Bytes go out, but a display is not expected. The caveat says why, for the user.
    case experimental(caveat: String)
    case unavailable(reason: String)
}

/// Something the transport noticed on its own, without a call from above.
nonisolated enum FanConnectionEvent: Sendable, Equatable {
    /// The device went away: unplugged, or its handle died. `reason` is for the user.
    case lost(reason: String)
}

/// What a store actually did, in the user's terms. Never implies a display.
nonisolated struct FanStoreReceipt: Sendable, Equatable {
    let summary: String
    let reportCount: Int
    let byteCount: Int
    /// Reports whose echo matched what was sent (D20). Equal to `reportCount` when every
    /// report was confirmed end to end.
    let confirmedCount: Int
    let mismatchedCount: Int
    let missingCount: Int
    let packetLog: URL?

    init(summary: String, reportCount: Int, byteCount: Int,
         confirmedCount: Int, mismatchedCount: Int = 0, missingCount: Int = 0, packetLog: URL? = nil) {
        self.summary = summary
        self.reportCount = reportCount
        self.byteCount = byteCount
        self.confirmedCount = confirmedCount
        self.mismatchedCount = mismatchedCount
        self.missingCount = missingCount
        self.packetLog = packetLog
    }

    var everyReportConfirmed: Bool { reportCount > 0 && confirmedCount == reportCount }
}

/// What a fan can do, independent of how it is wired. A store publishes the whole set of
/// messages (D19): the fan keeps exactly what it was last given.
nonisolated protocol FanDisplayTransport: Sendable {
    nonisolated var displayName: String { get }
    nonisolated var storeAvailability: FanStoreAvailability { get }
    /// Events the transport raises by itself, such as the device being unplugged (D21).
    nonisolated var connectionEvents: AsyncStream<FanConnectionEvent> { get }
    var geometry: FanGeometry { get async }

    func connect() async throws
    func store(_ messages: [FanMessage]) async throws -> FanStoreReceipt
    func disconnect() async
}

nonisolated enum FanTransportError: Error, Sendable, Equatable {
    case deviceNotFound
    case openFailed(code: Int32)
    case notConnected
    case deviceRemoved
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
        case .deviceRemoved:
            return "The fan was unplugged. Plug the data cable back in and press Connect again."
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
