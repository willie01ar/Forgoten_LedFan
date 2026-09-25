import Foundation
import IOKit
import IOKit.hid

/// Talks to the physical fan over USB HID the way the reference driver does: the device is
/// opened seized, every 8-byte output report goes out as SET_REPORT, and after each one the
/// interrupt-IN endpoint is given one second to answer. Silence is logged, never fatal.
actor HIDFanTransport: FanDisplayTransport {
    nonisolated let displayName = "SONiX LED fan"
    nonisolated let storeAvailability: FanStoreAvailability

    /// Placeholder (D1): the preview's column count; the real disc is 156 columns wide.
    static let placeholderGeometry = FanGeometry(ledsPerArm: 11, columnsPerRevolution: 180)
    /// The reference driver's read timeout after each packet (pearlfan-rs src/device.rs:90).
    static let acknowledgementTimeout: Duration = .seconds(1)
    private static let inputBufferSize = 64

    static let caveat = "Send uses the PearlFan protocol for this fan model. Program with the data cable in and "
        + "the fan switched off, then swap to the power cable to see the result."

    private let vendorID: Int
    private let productID: Int
    private let encoder: any FanReportEncoding
    private let packetLog: PacketLog?
    private let inbox = InputReportInbox()
    private var bridge: InputReportBridge?
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var device: IOHIDDevice?

    init(vendorID: Int = 0x0C45,
         productID: Int = 0x7701,
         encoder: any FanReportEncoding = PearlFanEncoder(),
         packetLogDirectory: URL? = PacketLog.defaultDirectory) {
        self.vendorID = vendorID
        self.productID = productID
        self.encoder = encoder
        packetLog = packetLogDirectory.map { PacketLog(directory: $0) }
        storeAvailability = .experimental(caveat: Self.caveat)
    }

    var geometry: FanGeometry { Self.placeholderGeometry }

    // MARK: - FanDisplayTransport

    /// Matches without opening the manager (opening it first breaks report transfers on this
    /// device), opens the device seized like hidapi does, and listens for input reports on the
    /// main run loop, which a SwiftUI app always has running.
    func connect() async throws {
        guard device == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [String: Int] = [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)

        guard let match = Self.firstDevice(in: manager) else { throw FanTransportError.deviceNotFound }

        let deviceResult = IOHIDDeviceOpen(match, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard deviceResult == kIOReturnSuccess else { throw FanTransportError.openFailed(code: deviceResult) }

        let bridge = InputReportBridge(inbox: inbox)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputBufferSize)
        IOHIDDeviceRegisterInputReportCallback(match, buffer, Self.inputBufferSize, Self.inputReportArrived,
                                               Unmanaged.passUnretained(bridge).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(match, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        self.bridge = bridge
        inputBuffer = buffer
        device = match
    }

    func store(_ message: FanMessage) async throws -> FanStoreReceipt {
        guard let device else { throw FanTransportError.notConnected }
        let reports = try encoder.reports(for: [message])

        var acknowledgements: [[UInt8]?] = []
        let started = ContinuousClock.now
        for report in reports {
            let result = Self.send(report, to: device)
            guard result == kIOReturnSuccess else { throw FanTransportError.writeFailed(code: result) }
            // The reference reads 8 bytes with a 1 s timeout after every packet and treats a
            // timeout as nothing to read. Whether this head ever answers is what the log records.
            acknowledgements.append(await inbox.next(within: Self.acknowledgementTimeout))
        }
        let elapsed = ContinuousClock.now - started

        let log = try? packetLog?.write(reports, acknowledgements: acknowledgements, label: "slot\(message.displayNumber)")
        let acknowledged = acknowledgements.count { $0 != nil }
        let bytes = reports.reduce(0) { $0 + $1.count }
        return FanStoreReceipt(summary: Self.receiptSummary(reportCount: reports.count, byteCount: bytes,
                                                            acknowledged: acknowledged, elapsed: elapsed),
                               reportCount: reports.count, byteCount: bytes,
                               acknowledged: acknowledged == reports.count,
                               acknowledgementCount: acknowledged, packetLog: log)
    }

    func disconnect() async {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
        inputBuffer?.deallocate()
        inputBuffer = nil
        bridge = nil
        device = nil
    }

    // MARK: - Copy

    /// What happened, in words that never claim a display.
    nonisolated static func receiptSummary(reportCount: Int, byteCount: Int, acknowledged: Int, elapsed: Duration) -> String {
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let ack = acknowledged == 0
            ? "No acknowledgement came back from the fan."
            : "The fan acknowledged \(acknowledged) of \(reportCount)."
        return "Wrote \(reportCount) reports (\(byteCount) bytes) in \(String(format: "%.1f", seconds)) s. \(ack) "
            + "Swap to the power cable to see whether it took."
    }

    // MARK: - Helpers

    private static let inputReportArrived: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context, length > 0 else { return }
        let bridge = Unmanaged<InputReportBridge>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        Task { await bridge.inbox.deliver(bytes) }
    }

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
