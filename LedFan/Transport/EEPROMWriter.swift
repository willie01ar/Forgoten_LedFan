import Foundation

/// KNOWN (D8). Frames an EEPROM write as 8-byte reports: `A0`, address, up to six data bytes.
nonisolated protocol EEPROMWriting: Sendable {
    func packets(writing bytes: [UInt8], toAddress address: UInt8) -> [[UInt8]]
}

/// The head behaves like a HID-to-I2C bridge in front of a 24Cxx EEPROM: `A0` is the
/// chip's write address, the next byte the memory address, then data, zero padded to 8.
/// Only `A0`-headed reports ever showed write timing on the real device.
nonisolated struct EEPROMWriter: EEPROMWriting {
    static let reportSize = 8
    static let writeHeader: UInt8 = 0xA0
    static let dataBytesPerPacket = 6

    /// Every long probing run stalled once, for the host's full 5 s timeout, at an address in
    /// this range. Not avoided here; a future writer should pace or retry these.
    static let stallProneAddresses: ClosedRange<UInt8> = 0x18...0x23

    func packets(writing bytes: [UInt8], toAddress address: UInt8) -> [[UInt8]] {
        var nextAddress = address
        return stride(from: 0, to: bytes.count, by: Self.dataBytesPerPacket).map { start in
            let chunk = Array(bytes[start..<min(start + Self.dataBytesPerPacket, bytes.count)])
            let packet = [Self.writeHeader, nextAddress] + chunk
            nextAddress &+= UInt8(chunk.count)   // 8-bit address model: wraps at 256
            return packet + [UInt8](repeating: 0, count: Self.reportSize - packet.count)
        }
    }
}
