import Foundation
import IOKit
import IOKit.hid

/// Talks to the physical fan over USB HID. Output reports travel the control pipe
/// via SET_REPORT because the device exposes only an interrupt IN endpoint.
/// Deliberately thin: it owns the handles and knows nothing about what the bytes mean.
actor HIDFanTransport: FanDisplayTransport {
    nonisolated let displayName = "SONiX LED fan"

    private let vendorID: Int
    private let productID: Int
    private let arms: Int
    private let encoder: any FanPacketEncoding
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    init(vendorID: Int = 0x0C45,
         productID: Int = 0x7701,
         ledsPerArm: Int = 11,
         encoder: any FanPacketEncoding = SequencedColumnEncoder()) {
        self.vendorID = vendorID
        self.productID = productID
        self.arms = ledsPerArm
        self.encoder = encoder
    }

    var ledsPerArm: Int { arms }

    // MARK: - FanDisplayTransport

    func connect() async throws {
        guard device == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [String: Int] = [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else { throw FanTransportError.openFailed(code: managerResult) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let match = devices.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw FanTransportError.deviceNotFound
        }

        let deviceResult = IOHIDDeviceOpen(match, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw FanTransportError.openFailed(code: deviceResult)
        }

        self.manager = manager
        device = match
    }

    func display(_ frame: POVFrame) async throws {
        guard let device else { throw FanTransportError.notConnected }

        for packet in try encoder.packets(for: frame) {
            let result = packet.withUnsafeBufferPointer { buffer -> IOReturn in
                guard let base = buffer.baseAddress else { return kIOReturnBadArgument }
                return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, base, buffer.count)
            }
            guard result == kIOReturnSuccess else { throw FanTransportError.writeFailed(code: result) }
        }
    }

    func disconnect() async {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        manager = nil
    }
}
