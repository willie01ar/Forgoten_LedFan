import Foundation
import Testing
@testable import LedFan

struct FanMessageTests {
    @Test func aMessageWithinTheLimitsIsAccepted() throws {
        let message = try FanMessage(slot: 0, text: "HELLO")
        #expect(message.slot == 0)
        #expect(message.text == "HELLO")
        #expect(message.displayNumber == 1)
    }

    @Test func exactlyTwentySixCharactersFit() throws {
        let text = "THE QUICK BROWN FOX JUMPS!"
        #expect(text.count == 26)
        #expect(try FanMessage(slot: 7, text: text).text == text)
        #expect(FanMessage.excessCharacters(in: text) == 0)
    }

    @Test func theTwentySeventhCharacterIsRefusedWithTheExcessCount() {
        let text = "THE QUICK BROWN FOX JUMPS!!"
        #expect(FanMessage.excessCharacters(in: text) == 1)
        #expect(throws: FanMessageError.tooLong(by: 1)) {
            try FanMessage(slot: 0, text: text)
        }
    }

    @Test func charactersAreCountedAsAPersonWouldCountThem() {
        // Combining sequences and emoji count once each, like the fan's "26 characters".
        #expect(FanMessage.excessCharacters(in: String(repeating: "é", count: 27)) == 1)
        #expect(FanMessage.excessCharacters(in: String(repeating: "🙂", count: 26)) == 0)
    }

    @Test(arguments: [-1, 8, 99])
    func slotsOutsideOneToEightAreRefused(slot: Int) {
        #expect(throws: FanMessageError.slotOutOfRange(slot)) {
            try FanMessage(slot: slot, text: "A")
        }
    }

    @Test func errorsHaveHumanReadableDescriptions() {
        #expect(FanMessageError.tooLong(by: 1).localizedDescription.contains("1 character over"))
        #expect(FanMessageError.tooLong(by: 3).localizedDescription.contains("3 characters over"))
        #expect(FanMessageError.slotOutOfRange(8).localizedDescription.contains("Slot 9"))
    }

    @Test func emptyTextIsAValidMessage() throws {
        #expect(try FanMessage(slot: 3, text: "").text.isEmpty)
    }
}
