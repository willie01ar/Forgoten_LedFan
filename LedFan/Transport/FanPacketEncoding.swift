import Foundation

nonisolated protocol FanPacketEncoding: Sendable {
    func packets(for frame: POVFrame) throws -> [[UInt8]]
}

/// HYPOTHESIS ONLY. The real command format for SONiX 0x0C45:0x7701 is not known;
/// this packs a sequence byte plus three big-endian columns into each 8-byte report.
/// Replace this one type once the protocol is reverse-engineered — nothing else should change.
nonisolated struct SequencedColumnEncoder: FanPacketEncoding {
    static let reportSize = 8
    static let columnsPerPacket = 3

    func packets(for frame: POVFrame) throws -> [[UInt8]] {
        guard !frame.isEmpty else { throw FanTransportError.protocolNotYetKnown }

        return frame.columns
            .chunked(into: Self.columnsPerPacket)
            .enumerated()
            .map { index, columns in
                var packet: [UInt8] = [UInt8(index % 256)]
                for column in columns {
                    packet.append(UInt8(column >> 8))
                    packet.append(UInt8(column & 0xFF))
                }
                packet.append(contentsOf: [UInt8](repeating: 0, count: Self.reportSize - packet.count))
                return packet
            }
    }
}

// MARK: -

private nonisolated extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
