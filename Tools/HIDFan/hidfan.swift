// hidfan — interactive probe for the SONiX 0x0C45:0x7701 LED fan.
// Throwaway reverse-engineering tool. Not part of the LedFan app target.
//
//   ./hidfan                    interactive REPL
//   ./hidfan sweep              sweep the first byte 0x00...0xFF
//   ./hidfan bits               walk a single 1-bit through all 64 bits
//
// REPL commands:
//   01 02 03            send an output report (padded/truncated to 8 bytes)
//   f 01 02 03          send a FEATURE report
//   g                   read the feature report back
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

// MARK: - Device discovery

func matchingDevice() -> IOHIDDevice? {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let criteria: [String: Any] = [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID]
    IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)

    guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
        print("Could not open the HID manager.")
        return nil
    }
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else {
        print("No device matching \(hex(vendorID)):\(hex(productID)). Is the DATA cable connected?")
        return nil
    }
    guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
        print("Found the device but could not open it.")
        return nil
    }
    return device
}

func hex(_ value: Int) -> String { String(format: "0x%04X", value) }
func hexBytes(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }

// MARK: - Input reports

private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

func listenForInputReports(on device: IOHIDDevice) {
    let thread = Thread {
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, { _, _, _, _, reportID, report, length in
            let bytes = Array(UnsafeBufferPointer(start: report, count: Int(length)))
            print("\n  << IN  id=\(reportID)  \(hexBytes(bytes))")
            print("> ", terminator: "")
            fflush(stdout)
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
        print("  >> \(label) \(hexBytes(frame))")
        return true
    }
    print("  >> \(label) \(hexBytes(frame))   FAILED (0x\(String(result, radix: 16)))")
    return false
}

func readFeature(from device: IOHIDDevice) {
    var buffer = [UInt8](repeating: 0, count: reportSize)
    var length = reportSize
    let result = buffer.withUnsafeMutableBufferPointer { pointer in
        IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, pointer.baseAddress!, &length)
    }
    if result == kIOReturnSuccess {
        print("  << FEAT \(hexBytes(Array(buffer.prefix(length))))")
    } else {
        print("  << FEAT read failed (0x\(String(result, radix: 16)))")
    }
}

// MARK: - Scans

func sweepFirstByte(from start: Int, to end: Int, delayMilliseconds: Int, on device: IOHIDDevice) {
    print("Sweeping first byte \(hex(start))...\(hex(end)). Watch the fan; note when anything changes.")
    for value in start...end {
        send([UInt8(value), 0, 0, 0, 0, 0, 0, 0], to: device)
        usleep(useconds_t(delayMilliseconds * 1000))
    }
}

func walkingBit(delayMilliseconds: Int, on device: IOHIDDevice) {
    print("Walking a single 1-bit through all 64 bits.")
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
print("Opened SONiX \(hex(vendorID)):\(hex(productID)) — 8-byte reports, vendor usage page 0xFFFF.")
listenForInputReports(on: device)

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "sweep" {
    sweepFirstByte(from: 0, to: 255, delayMilliseconds: 150, on: device)
    exit(0)
}
if arguments.first == "bits" {
    walkingBit(delayMilliseconds: 150, on: device)
    exit(0)
}

print("Type hex bytes to send. 'q' to quit, see the header comment for commands.\n")
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
        print("Holding — press return to stop.")
        let stop = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { _ = readLine(); stop.signal() }
        while stop.wait(timeout: .now() + 0.1) == .timedOut { send(frame, to: device) }
    default:
        send(parseBytes(tokens), to: device)
    }
}
