import Foundation

/// Turns messages into the exact 8-byte reports a transport sends. Each fan protocol is one
/// conformance; the transport knows nothing about what the bytes mean.
nonisolated protocol FanReportEncoding: Sendable {
    func reports(for messages: [FanMessage]) throws -> [[UInt8]]
}
