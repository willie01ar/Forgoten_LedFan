import Foundation

/// KNOWN (D8). Frames an EEPROM write as 8-byte reports: device address, memory address,
/// up to six data bytes. Addresses run over the whole 2 KB store.
nonisolated protocol EEPROMWriting: Sendable {
    func packets(writing bytes: [UInt8], toAddress address: UInt16) -> [[UInt8]]
}

/// The head behaves like a HID-to-I2C bridge in front of a 24C16 EEPROM: 2 KB as eight
/// 256-byte blocks, block `b` reached at I2C write address `0xA0 | (b << 1)`, then a one-byte
/// address inside the block, then data, zero padded to 8. Only `A0`-headed reports ever
/// showed write timing on the real device. A packet never crosses a block boundary.
nonisolated struct EEPROMWriter: EEPROMWriting {
    static let reportSize = 8
    static let dataBytesPerPacket = 6
    static let blockSize = 256
    static let capacity = 2048
    static let baseHeader: UInt8 = 0xA0

    /// Every long probing run stalled once, for the host's full 5 s timeout, at an address in
    /// this range of block 0. The transport counts such holds rather than failing on them.
    static let stallProneAddresses: ClosedRange<UInt8> = 0x18...0x23

    static func header(forBlock block: Int) -> UInt8 {
        baseHeader | UInt8((block & 0x7) << 1)
    }

    func packets(writing bytes: [UInt8], toAddress address: UInt16) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        var cursor = Int(address)
        var offset = 0
        while offset < bytes.count {
            let block = (cursor / Self.blockSize) % (Self.capacity / Self.blockSize)
            let inBlock = cursor % Self.blockSize
            let length = min(Self.dataBytesPerPacket, bytes.count - offset, Self.blockSize - inBlock)
            let chunk = Array(bytes[offset..<offset + length])
            let packet = [Self.header(forBlock: block), UInt8(inBlock)] + chunk
            packets.append(packet + [UInt8](repeating: 0, count: Self.reportSize - packet.count))
            offset += length
            cursor += length
        }
        return packets
    }
}
