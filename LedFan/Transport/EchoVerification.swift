import Foundation

/// D20. The fan echoes every report on the interrupt-IN endpoint; a header comes back with
/// bit 0 of its first byte set (`A0` returns as `A1`). Comparing echoes to what was sent
/// turns the acknowledgement into an end-to-end transfer check.
nonisolated struct EchoVerification: Sendable, Equatable {
    let confirmed: Int
    let mismatched: Int
    let missing: Int

    static func verify(sent reports: [[UInt8]], echoes: [[UInt8]?]) -> EchoVerification {
        var confirmed = 0, mismatched = 0, missing = 0
        for (index, report) in reports.enumerated() {
            guard index < echoes.count, let echo = echoes[index] else { missing += 1; continue }
            if confirms(report, echo: echo) { confirmed += 1 } else { mismatched += 1 }
        }
        return EchoVerification(confirmed: confirmed, mismatched: mismatched, missing: missing)
    }

    /// An echo confirms its report when it is identical, or identical but for the
    /// acknowledgement bit in the first byte.
    static func confirms(_ report: [UInt8], echo: [UInt8]) -> Bool {
        guard echo.count == report.count, let first = report.first else { return false }
        return echo == report || (echo[0] == first | 0x01 && Array(echo.dropFirst()) == Array(report.dropFirst()))
    }
}
