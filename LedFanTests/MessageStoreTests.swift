import Foundation
import Testing
@testable import LedFan

struct MessageStoreTests {
    // MARK: - SavedDrafts normalisation

    @Test func fewerThanEightSlotsArePaddedAndMoreAreTrimmed() {
        let short = SavedDrafts(slotTexts: ["A", "B"], selectedSlot: 0)
        #expect(short.slotTexts == ["A", "B", "", "", "", "", "", ""])
        let long = SavedDrafts(slotTexts: Array(repeating: "X", count: 12), selectedSlot: 0)
        #expect(long.slotTexts.count == FanMessage.slotCount)
    }

    @Test func theSelectedSlotIsClampedIntoRange() {
        #expect(SavedDrafts(slotTexts: [], selectedSlot: -4).selectedSlot == 0)
        #expect(SavedDrafts(slotTexts: [], selectedSlot: 99).selectedSlot == FanMessage.slotCount - 1)
    }

    @Test func decodingMalformedValuesStillNormalises() throws {
        let json = #"{"slotTexts":["ONE"],"selectedSlot":42}"#.data(using: .utf8) ?? Data()
        let drafts = try JSONDecoder().decode(SavedDrafts.self, from: json)
        #expect(drafts.slotTexts.count == FanMessage.slotCount)
        #expect(drafts.selectedSlot == FanMessage.slotCount - 1)
    }

    // MARK: - File store, in a temporary directory

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LedFanTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func absentDataLoadsAsNil() async {
        let store = FileMessageStore(directory: temporaryDirectory())
        #expect(await store.load() == nil)
    }

    @Test func savedDraftsRoundTrip() async throws {
        let store = FileMessageStore(directory: temporaryDirectory())
        let drafts = SavedDrafts(slotTexts: ["HELLO", "", "THIRD"], selectedSlot: 2)
        try await store.save(drafts)
        #expect(await store.load() == drafts)
    }

    @Test func corruptDataLoadsAsNilNotACrash() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json at all {{{".utf8).write(to: directory.appendingPathComponent("drafts.json"))
        let store = FileMessageStore(directory: directory)
        #expect(await store.load() == nil)
    }

    @Test func savingOverwritesAtomically() async throws {
        let store = FileMessageStore(directory: temporaryDirectory())
        try await store.save(SavedDrafts(slotTexts: ["FIRST"], selectedSlot: 0))
        try await store.save(SavedDrafts(slotTexts: ["SECOND"], selectedSlot: 1))
        let loaded = await store.load()
        #expect(loaded?.slotTexts.first == "SECOND")
        #expect(loaded?.selectedSlot == 1)
    }

    // MARK: - Transient store

    @Test func theTransientStoreStartsWithTheStarterDraftsAndForgetsNothingWhileAlive() async throws {
        let store = TransientMessageStore()
        #expect(await store.load() == .starter)
        try await store.save(.empty)
        #expect(await store.load() == .empty)
    }
}
