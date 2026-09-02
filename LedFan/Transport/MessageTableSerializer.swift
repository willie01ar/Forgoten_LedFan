import Foundation

/// UNKNOWN (D8). Serialises the message table the display firmware parses.
nonisolated protocol MessageTableSerializing: Sendable {
    func bytes(for messages: [FanMessage]) throws -> [UInt8]
}

/// The one place in the app that admits the fan's table format is unknown. Every published
/// sibling format was tried and rejected by the head (protocol-findings.md). Replace this
/// type, and only this type, when the format arrives.
nonisolated struct UnknownMessageTableSerializer: MessageTableSerializing {
    func bytes(for messages: [FanMessage]) throws -> [UInt8] {
        throw FanTransportError.protocolNotYetKnown
    }
}
