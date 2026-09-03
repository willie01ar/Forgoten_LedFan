import Foundation
import IOKit
import IOKit.hid

/// Talks to the physical fan over USB HID: connects, reports geometry, and writes the
/// message table as `A0`-framed output reports (D16). It never reads anything back,
/// because this head never sends anything back.
actor HIDFanTransport: FanDisplayTransport {
    nonisolated let displayName = "SONiX LED fan"
    nonisolated let storeAvailability: FanStoreAvailability

    /// Placeholder (D1): the real column count is unknown.
    static let placeholderGeometry = FanGeometry(ledsPerArm: 11, columnsPerRevolution: 180)

    static let caveat = "This fan is a different generation from the one whose message format the app "
        + "implements. Send will write the bytes, but nothing is expected to appear on the blades."

    private let vendorID: Int
    private let productID: Int
    private let writer: FanTableWriter
    private let packetLog: PacketLog?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    init(vendorID: Int = 0x0C45,
         productID: Int = 0x7701,
         writer: FanTableWriter = FanTableWriter(),
         packetLogDirectory: URL? = PacketLog.defaultDirectory) {
        self.vendorID = vendorID
        self.productID = productID
        self.writer = writer
        packetLog = packetLogDirectory.map { PacketLog(directory: $0) }
        storeAvailability = .experimental(caveat: Self.caveat)
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

    func store(_ message: FanMessage) async throws -> FanStoreReceipt {
        guard let device else { throw FanTransportError.notConnected }
        let reports = try writer.reports(for: [message])

        var heldWrites = 0
        for report in reports {
            let result = Self.send(report, to: device)
            // The vendor protocol reads a 3-byte acknowledgement after every report. This head
            // never sends one (protocol-findings.md), so nothing is read and silence is normal.
            if result == kIOReturnTimeout {
                heldWrites += 1     // the 5 s hold seen in probing; the head recovers on its own
                continue
            }
            guard result == kIOReturnSuccess else { throw FanTransportError.writeFailed(code: result) }
        }

        let log = try? packetLog?.write(reports, label: "slot\(message.displayNumber)")
        let bytes = reports.reduce(0) { $0 + $1.count }
        return FanStoreReceipt(summary: Self.receiptSummary(reportCount: reports.count, byteCount: bytes, heldWrites: heldWrites),
                               reportCount: reports.count, byteCount: bytes, acknowledged: false,
                               heldWrites: heldWrites, packetLog: log)
    }

    func disconnect() async {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        manager = nil
    }

    // MARK: - Copy

    /// What happened, without the word "sent" standing alone and without implying a display.
    nonisolated static func receiptSummary(reportCount: Int, byteCount: Int, heldWrites: Int) -> String {
        var summary = "Wrote \(reportCount) reports (\(byteCount) bytes) to the fan. No acknowledgement came back, which is normal for this fan. Nothing is expected on the blades."
        if heldWrites > 0 {
            summary += " \(heldWrites) write\(heldWrites == 1 ? " was" : "s were") held for the 5-second timeout."
        }
        return summary
    }

    // MARK: - Helpers

    private static func send(_ report: [UInt8], to device: IOHIDDevice) -> IOReturn {
        report.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, base, buffer.count)
        }
    }

    private static func firstDevice(in manager: IOHIDManager) -> IOHIDDevice? {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first
    }
}
