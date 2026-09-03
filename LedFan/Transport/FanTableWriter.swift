import Foundation

/// Turns messages into the exact reports a transport sends: serializer, then EEPROM framing.
/// No I/O and no device knowledge, so the whole chain is testable with any serializer.
nonisolated struct FanTableWriter: Sendable {
    static let tableAddress: UInt16 = 0

    let serializer: any MessageTableSerializing
    let eepromWriter: any EEPROMWriting

    init(serializer: any MessageTableSerializing = GenerationTwoTableSerializer(),
         eepromWriter: any EEPROMWriting = EEPROMWriter()) {
        self.serializer = serializer
        self.eepromWriter = eepromWriter
    }

    func reports(for messages: [FanMessage]) throws -> [[UInt8]] {
        let table = try serializer.bytes(for: messages)
        return eepromWriter.packets(writing: table, toAddress: Self.tableAddress)
    }
}

/// One file per send, hex bytes, one report per line, so any send is reproducible later.
nonisolated struct PacketLog: Sendable {
    let directory: URL

    /// The app's own folder inside the sandbox container.
    static var defaultDirectory: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("LedFan/sends", isDirectory: true)
    }

    func write(_ reports: [[UInt8]], label: String, at date: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(stamp)-\(label).hex")
        let lines = reports.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
