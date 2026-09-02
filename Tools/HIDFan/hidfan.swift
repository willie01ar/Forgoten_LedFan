// hidfan — interactive probe for the SONiX 0x0C45:0x7701 LED fan.
// Throwaway reverse-engineering tool. Not part of the LedFan app target.
//
//   ./hidfan                    interactive REPL
//   ./hidfan listen [seconds]   open the device, send nothing, print any input reports
//   ./hidfan feature            read the feature report once
//   ./hidfan sweep              sweep the first byte 0x00...0xFF
//   ./hidfan bits               walk a single 1-bit through all 64 bits
//
// REPL commands:
//   01 02 03            send an output report (padded/truncated to 8 bytes)
//   f 01 02 03          send a FEATURE report
//   g                   read the feature report back
//   i                   GET_REPORT(Input) over the control pipe
//   sweep [a] [b] [ms]  sweep first byte from a to b
//   bits [ms]           walking-bit scan
//   hold <hex...>       resend a frame every 100ms until return is pressed
//   q                   quit

import Foundation
import IOKit
import IOKit.hid

let vendorID = 0x0C45
let productID = 0x7701
let reportSize = 8

// MARK: - IOReturn decoding

let knownReturnCodes: [UInt32: String] = [
    0xE00002BC: "kIOReturnError", 0xE00002BD: "kIOReturnNoMemory", 0xE00002BE: "kIOReturnNoResources",
    0xE00002C0: "kIOReturnNoDevice", 0xE00002C1: "kIOReturnNotPrivileged", 0xE00002C2: "kIOReturnBadArgument",
    0xE00002C5: "kIOReturnExclusiveAccess", 0xE00002C7: "kIOReturnUnsupported", 0xE00002CA: "kIOReturnIOError",
    0xE00002CD: "kIOReturnNotOpen", 0xE00002CE: "kIOReturnNotReadable", 0xE00002CF: "kIOReturnNotWritable",
    0xE00002D5: "kIOReturnBusy", 0xE00002D6: "kIOReturnTimeout", 0xE00002D7: "kIOReturnOffline",
    0xE00002D8: "kIOReturnNotReady", 0xE00002D9: "kIOReturnNotAttached", 0xE00002E2: "kIOReturnNotPermitted",
    0xE00002E9: "kIOReturnDeviceError", 0xE00002EB: "kIOReturnAborted", 0xE00002ED: "kIOReturnNotResponding"
]

func describe(_ result: IOReturn) -> String {
    let raw = UInt32(bitPattern: result)
    let hex = String(format: "0x%08X", raw)
    return knownReturnCodes[raw].map { "\(hex) \($0)" } ?? hex
}

func hex(_ value: Int) -> String { String(format: "0x%04X", value) }
func hexBytes(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
func log(_ text: String) { print(text); fflush(stdout) }

// MARK: - Device discovery

/// Matches without opening the manager first, so the only open on the device is ours.
/// Falls back to opening the manager if plain matching enumerates nothing.
func matchingDevice() -> IOHIDDevice? {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let criteria: [String: Any] = [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID]
    IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)

    var devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    if devices.isEmpty {
        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        log("Plain matching found nothing; IOHIDManagerOpen -> \(describe(opened))")
        devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    }
    guard let device = devices.first else {
        log("No device matching \(hex(vendorID)):\(hex(productID)). Is the DATA cable in the fan's second port?")
        return nil
    }
    let opened = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard opened == kIOReturnSuccess else {
        log("Found the device but IOHIDDeviceOpen failed: \(describe(opened))")
        return nil
    }
    return device
}

// MARK: - Input reports

private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

func listenForInputReports(on device: IOHIDDevice) {
    let thread = Thread {
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, { _, result, _, _, reportID, report, length in
            let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
            log("\n  << IN  id=\(reportID) result=\(describe(result))  \(hexBytes(bytes))")
        }, nil)
        CFRunLoopRun()
    }
    thread.start()
}

// MARK: - Output

@discardableResult
func send(_ bytes: [UInt8], to device: IOHIDDevice, type: IOHIDReportType = kIOHIDReportTypeOutput) -> Bool {
    var frame = Array(bytes.prefix(reportSize))
    frame.append(contentsOf: [UInt8](repeating: 0, count: reportSize - frame.count))
    let result = frame.withUnsafeBufferPointer { pointer in
        IOHIDDeviceSetReport(device, type, 0, pointer.baseAddress!, frame.count)
    }
    let label = type == kIOHIDReportTypeFeature ? "FEAT" : "OUT "
    if result == kIOReturnSuccess {
        log("  >> \(label) \(hexBytes(frame))")
        return true
    }
    log("  >> \(label) \(hexBytes(frame))   FAILED \(describe(result))")
    return false
}

func readFeature(from device: IOHIDDevice) { readReport(kIOHIDReportTypeFeature, from: device) }

/// GET_REPORT over the control pipe. For input reports this bypasses the interrupt endpoint.
func readReport(_ type: IOHIDReportType, from device: IOHIDDevice) {
    var buffer = [UInt8](repeating: 0, count: reportSize)
    var length = reportSize
    let result = buffer.withUnsafeMutableBufferPointer { pointer in
        IOHIDDeviceGetReport(device, type, 0, pointer.baseAddress!, &length)
    }
    let label = type == kIOHIDReportTypeFeature ? "FEAT" : "IN? "
    if result == kIOReturnSuccess {
        log("  << \(label) \(hexBytes(Array(buffer.prefix(length))))")
    } else {
        log("  << \(label) read failed \(describe(result))")
    }
}

// MARK: - Scans

func sweepFirstByte(from start: Int, to end: Int, delayMilliseconds: Int, on device: IOHIDDevice) {
    log("Sweeping first byte \(hex(start))...\(hex(end)). Watch the fan; note when anything changes.")
    for value in start...end {
        send([UInt8(value), 0, 0, 0, 0, 0, 0, 0], to: device)
        usleep(useconds_t(delayMilliseconds * 1000))
    }
}

func walkingBit(delayMilliseconds: Int, on device: IOHIDDevice) {
    log("Walking a single 1-bit through all 64 bits.")
    for bitIndex in 0..<(reportSize * 8) {
        var frame = [UInt8](repeating: 0, count: reportSize)
        frame[bitIndex / 8] = UInt8(1 << (bitIndex % 8))
        send(frame, to: device)
        usleep(useconds_t(delayMilliseconds * 1000))
    }
}

// MARK: - Parsing

func parseBytes(_ tokens: [String]) -> [UInt8] {
    tokens.compactMap { UInt8($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }
}

// MARK: - Entry point

guard let device = matchingDevice() else { exit(1) }
log("Opened SONiX \(hex(vendorID)):\(hex(productID)) - 8-byte reports, vendor usage page 0xFFFF.")
listenForInputReports(on: device)

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "listen":
    let seconds = arguments.count > 1 ? Int(arguments[1]) ?? 10 : 10
    log("Listening for \(seconds)s without sending anything.")
    sleep(UInt32(seconds))
    log("Done listening.")
    exit(0)
case "feature":
    readFeature(from: device)
    sleep(1)
    exit(0)
case "sweep":
    sweepFirstByte(from: 0, to: 255, delayMilliseconds: 150, on: device)
    sleep(1)
    exit(0)
case "bits":
    walkingBit(delayMilliseconds: 150, on: device)
    sleep(1)
    exit(0)
default:
    break
}

log("Type hex bytes to send. 'q' to quit, see the header comment for commands.\n")
while true {
    print("> ", terminator: "")
    fflush(stdout)
    guard let line = readLine(strippingNewline: true) else { break }
    let tokens = line.split(separator: " ").map(String.init)
    guard let first = tokens.first else { continue }

    switch first {
    case "q", "quit", "exit":
        exit(0)
    case "g":
        readFeature(from: device)
    case "i":
        readReport(kIOHIDReportTypeInput, from: device)
    case "f":
        send(parseBytes(Array(tokens.dropFirst())), to: device, type: kIOHIDReportTypeFeature)
    case "sweep":
        let start = tokens.count > 1 ? Int(tokens[1], radix: 16) ?? 0 : 0
        let end = tokens.count > 2 ? Int(tokens[2], radix: 16) ?? 255 : 255
        let delay = tokens.count > 3 ? Int(tokens[3]) ?? 150 : 150
        sweepFirstByte(from: start, to: min(end, 255), delayMilliseconds: delay, on: device)
    case "bits":
        walkingBit(delayMilliseconds: tokens.count > 1 ? Int(tokens[1]) ?? 150 : 150, on: device)
    case "hold":
        let frame = parseBytes(Array(tokens.dropFirst()))
        log("Holding - press return to stop.")
        let stop = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { _ = readLine(); stop.signal() }
        while stop.wait(timeout: .now() + 0.1) == .timedOut { send(frame, to: device) }
    default:
        let bytes = parseBytes(tokens)
        if bytes.isEmpty {
            log("  ?? not a command and not hex: \(line)")
        } else {
            send(bytes, to: device)
        }
    }
}
