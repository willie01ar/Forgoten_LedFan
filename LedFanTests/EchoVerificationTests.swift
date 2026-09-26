import Foundation
import Testing
@testable import LedFan

struct EchoVerificationTests {
    private let header: [UInt8] = [0xA0, 0x10, 0x00, 0x00, 0x55, 0x00, 0x00, 0x00]
    private let data: [UInt8] = [0xFF, 0xFF, 0xFD, 0xF7, 0xFD, 0xB7, 0xFD, 0xB7]

    @Test func anIdenticalEchoConfirms() {
        #expect(EchoVerification.confirms(data, echo: data))
    }

    @Test func theHeaderComesBackWithItsAcknowledgementBitSet() {
        var echo = header; echo[0] = 0xA1
        #expect(EchoVerification.confirms(header, echo: echo))
        #expect(EchoVerification.confirms(header, echo: header), "an exact echo also counts")
    }

    @Test func anyOtherDifferenceIsAMismatch() {
        var wrongByte = data; wrongByte[5] ^= 0x01
        #expect(!EchoVerification.confirms(data, echo: wrongByte))
        #expect(!EchoVerification.confirms(data, echo: Array(data.dropLast())))
        var wrongFlag = header; wrongFlag[0] = 0xA2
        #expect(!EchoVerification.confirms(header, echo: wrongFlag))
    }

    @Test func allConfirmed() {
        var headerEcho = header; headerEcho[0] = 0xA1
        let result = EchoVerification.verify(sent: [header, data, data], echoes: [headerEcho, data, data])
        #expect(result == EchoVerification(confirmed: 3, mismatched: 0, missing: 0))
    }

    @Test func someMismatchedAndSomeMissing() {
        var bad = data; bad[0] = 0x00
        let result = EchoVerification.verify(sent: [header, data, data, data], echoes: [header, bad, nil])
        #expect(result == EchoVerification(confirmed: 1, mismatched: 1, missing: 2), "a short echo list counts as missing")
    }
}
