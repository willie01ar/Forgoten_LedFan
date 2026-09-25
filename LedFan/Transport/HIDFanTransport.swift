import Foundation
import IOKit
import IOKit.hid

/// Talks to the physical fan over USB HID the way the reference driver does: the device is
/// opened seized, every 8-byte output report goes out as SET_REPORT, and after each one the
/// interrupt-IN endpoint is given one second to echo it back. Echoes are verified (D20),
/// removal is observed (D21), and a send publishes the whole set of slots (D19).
actor HIDFanTransport: FanDisplayTransport {
    nonisolated let displayName = "SONiX LED fan"
    nonisolated let storeAvailability: FanStoreAvailability
    nonisolated let connectionEvents: AsyncStream<FanConnectionEvent>

    /// Placeholder (D1): the preview's column count; the real disc is 156 columns wide.
    static let placeholderGeometry = FanGeometry(ledsPerArm: 11, columnsPerRevolution: 180)
    /// The reference driver's read timeout after each packet (pearlfan-rs src/device.rs:90).
    static let acknowledgementTimeout: Duration = .seconds(1)
    private static let inputBufferSize = 64
    /// What IOKit answers on a handle whose device has gone: not "no device", but these.
    private static let deadHandleCodes: Set<IOReturn> = [kIOReturnBadArgument, kIOReturnNotOpen, kIOReturnNoDevice,
                                                         kIOReturnNotAttached, kIOReturnOffline]

    static let caveat = "Send uses the PearlFan protocol for this fan model. Program with the data cable in and "
        + "the fan switched off, then swap to the power cable to see the result."

    private let vendorID: Int
    private let productID: Int
    private let encoder: any FanReportEncoding
    private let packetLog: PacketLog?
    private let inbox = InputReportInbox()
    private let removal = RemovalFlag()
    private let events: AsyncStream<FanConnectionEvent>.Continuation
    private var bridge: DeviceCallbackBridge?
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
        let stream = AsyncStream.makeStream(of: FanConnectionEvent.self)
        connectionEvents = stream.stream
        events = stream.continuation
    }

    var geometry: FanGeometry { Self.placeholderGeometry }

    // MARK: - FanDisplayTransport

    /// Matches without opening the manager (opening it first breaks report transfers on this
    /// device), opens the device seized like hidapi does, and listens for input reports and
    /// removal on the main run loop, which a SwiftUI app always has running.
    func connect() async throws {
        if device != nil {
            guard await removal.isRemoved else { return }
            await releaseDevice()
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let criteria: [String: Int] = [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID]
        IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)

        guard let match = Self.firstDevice(in: manager) else { throw FanTransportError.deviceNotFound }

        let deviceResult = IOHIDDeviceOpen(match, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard deviceResult == kIOReturnSuccess else { throw FanTransportError.openFailed(code: deviceResult) }

        await removal.reset()
        await inbox.drain()
        let bridge = DeviceCallbackBridge(inbox: inbox, removal: removal, events: events)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputBufferSize)
        let context = Unmanaged.passUnretained(bridge).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(match, buffer, Self.inputBufferSize, Self.inputReportArrived, context)
        IOHIDDeviceRegisterRemovalCallback(match, Self.deviceWasRemoved, context)
        IOHIDDeviceScheduleWithRunLoop(match, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        self.bridge = bridge
        inputBuffer = buffer
        device = match
    }

    func store(_ messages: [FanMessage]) async throws -> FanStoreReceipt {
        guard let device else { throw FanTransportError.notConnected }
        if await removal.isRemoved { await releaseDevice(); throw FanTransportError.deviceRemoved }
        let reports = try encoder.reports(for: messages)

        var echoes: [[UInt8]?] = []
        let started = ContinuousClock.now
        for report in reports {
            let result = Self.send(report, to: device)
            let unplugged = await removal.isRemoved
            if unplugged || Self.deadHandleCodes.contains(result) {
                await releaseDevice()
                throw FanTransportError.deviceRemoved
            }
            guard result == kIOReturnSuccess else { throw FanTransportError.writeFailed(code: result) }
            // The reference reads 8 bytes with a 1 s timeout after every packet and treats a
            // timeout as nothing to read. This head echoes each report; the log keeps every one.
            echoes.append(await inbox.next(within: Self.acknowledgementTimeout))
        }
        let elapsed = ContinuousClock.now - started
        let verification = EchoVerification.verify(sent: reports, echoes: echoes)

        let log = try? packetLog?.write(reports, acknowledgements: echoes, label: "\(messages.count)-slots")
        let bytes = reports.reduce(0) { $0 + $1.count }
        return FanStoreReceipt(summary: Self.receiptSummary(messageCount: messages.count, reportCount: reports.count,
                                                            byteCount: bytes, verification: verification, elapsed: elapsed),
                               reportCount: reports.count, byteCount: bytes,
                               confirmedCount: verification.confirmed, mismatchedCount: verification.mismatched,
                               missingCount: verification.missing, packetLog: log)
    }

    func disconnect() async {
        await releaseDevice()
    }

    // MARK: - Copy

    /// What happened, in words that never claim a display.
    nonisolated static func receiptSummary(messageCount: Int, reportCount: Int, byteCount: Int,
                                           verification: EchoVerification, elapsed: Duration) -> String {
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let check: String
        if verification.confirmed == reportCount {
            check = "Every report was confirmed by the fan's echo."
        } else if verification.confirmed == 0 && verification.mismatched == 0 {
            check = "No echo came back from the fan."
        } else {
            check = "\(verification.confirmed) of \(reportCount) reports confirmed by echo; "
                + "\(verification.mismatched) differed, \(verification.missing) missing."
        }
        return "Published all \(messageCount) slots: \(reportCount) reports (\(byteCount) bytes) in "
            + "\(String(format: "%.1f", seconds)) s. \(check) Swap to the power cable to see the result."
    }

    // MARK: - Helpers

    private func releaseDevice() async {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        }
        inputBuffer?.deallocate()
        inputBuffer = nil
        bridge = nil
        device = nil
    }

    private static let inputReportArrived: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context, length > 0 else { return }
        let bridge = Unmanaged<DeviceCallbackBridge>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        Task { await bridge.inbox.deliver(bytes) }
    }

    private static let deviceWasRemoved: IOHIDCallback = { context, _, _ in
        guard let context else { return }
        let bridge = Unmanaged<DeviceCallbackBridge>.fromOpaque(context).takeUnretainedValue()
        Task {
            await bridge.removal.markRemoved()
            bridge.events.yield(.lost(reason: FanTransportError.deviceRemoved.localizedDescription))
        }
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
