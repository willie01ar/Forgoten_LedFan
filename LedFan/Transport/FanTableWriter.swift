import Foundation

/// The generation-2 (`0c45:7160`) write path: table serializer, then EEPROM framing. Kept as
/// the documented alternative to `PearlFanEncoder` (D17). No I/O, so any serializer can be
/// driven through it in tests.
nonisolated struct FanTableWriter: FanReportEncoding {
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

/// One file per send: each report's hex bytes, then what came back for it, one line per
/// report, so any send is reproducible and the fan's answers are on record.
nonisolated struct PacketLog: Sendable {
    let directory: URL

    /// The app's own folder inside the sandbox container.
    static var defaultDirectory: URL {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("LedFan/sends", isDirectory: true)
    }

    func write(_ reports: [[UInt8]], acknowledgements: [[UInt8]?] = [], label: String, at date: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(stamp)-\(label).hex")
        let lines = reports.enumerated().map { index, report in
            var line = Self.hex(report)
            if index < acknowledgements.count {
                line += acknowledgements[index].map { "  <- " + Self.hex($0) } ?? "  <- no acknowledgement"
            }
            return line
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
