import Foundation
import IOKit
import IOKit.hid

/// Talks to the physical fan over USB HID. It connects, reports geometry, and refuses to
/// write (D9): there is deliberately no `IOHIDDeviceSetReport` anywhere in the app target.
actor HIDFanTransport: FanDisplayTransport {
    nonisolated let displayName = "SONiX LED fan"
    nonisolated let storeAvailability: FanStoreAvailability

    /// Placeholder (D1): the real column count is unknown until the table format is.
    static let placeholderGeometry = FanGeometry(ledsPerArm: 11, columnsPerRevolution: 180)
    private static let tableAddress: UInt8 = 0

    private let vendorID: Int
    private let productID: Int
    private let tableSerializer: any MessageTableSerializing
    private let eepromWriter: any EEPROMWriting
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    init(vendorID: Int = 0x0C45,
         productID: Int = 0x7701,
         tableSerializer: any MessageTableSerializing = UnknownMessageTableSerializer(),
         eepromWriter: any EEPROMWriting = EEPROMWriter()) {
        self.vendorID = vendorID
        self.productID = productID
        self.tableSerializer = tableSerializer
        self.eepromWriter = eepromWriter
        storeAvailability = .unavailable(reason: FanTransportError.protocolNotYetKnown.localizedDescription)
    }

    var geometry: FanGeometry { Self.placeholderGeometry }

    // MARK: - FanDisplayTransport

    /// Matches without opening the manager: on this device, opening the manager first
    /// leaves report transfers failing with kIOReturnNotOpen (see docs/protocol-findings.md).
    func connect() async throws {
        guard device == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [String: Int] = [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)

        guard let match = Self.firstDevice(in: manager) else { throw FanTransportError.deviceNotFound }

        let deviceResult = IOHIDDeviceOpen(match, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else { throw FanTransportError.openFailed(code: deviceResult) }

        self.manager = manager
        device = match
    }

    func store(_ message: FanMessage) async throws {
        guard device != nil else { throw FanTransportError.notConnected }
        let table = try tableSerializer.bytes(for: [message])
        let packets = eepromWriter.packets(writing: table, toAddress: Self.tableAddress)
        try write(packets)
    }

    func disconnect() async {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        manager = nil
    }

    // MARK: - Helpers

    /// D9: no writes until the serializer is real. When that decision is lifted, this is
    /// where the SET_REPORT loop goes, pacing `EEPROMWriter.stallProneAddresses`.
    private func write(_ packets: [[UInt8]]) throws {
        throw FanTransportError.writingDisabled
    }

    private static func firstDevice(in manager: IOHIDManager) -> IOHIDDevice? {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
    }
}
