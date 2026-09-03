import Foundation

/// The eight drafts and the selected slot, as they are saved between launches.
/// The initialiser normalises anything malformed, so a decoded value is always usable.
nonisolated struct SavedDrafts: Sendable, Equatable, Codable {
    let slotTexts: [String]
    let selectedSlot: Int

    init(slotTexts: [String], selectedSlot: Int) {
        let padded = slotTexts + Array(repeating: "", count: max(0, FanMessage.slotCount - slotTexts.count))
        self.slotTexts = Array(padded.prefix(FanMessage.slotCount))
        self.selectedSlot = min(max(0, selectedSlot), FanMessage.slotCount - 1)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(slotTexts: try container.decode([String].self, forKey: .slotTexts),
                  selectedSlot: try container.decode(Int.self, forKey: .selectedSlot))
    }

    static let empty = SavedDrafts(slotTexts: [], selectedSlot: 0)
    /// What a first launch showed before persistence existed. Used by the transient store.
    static let starter = SavedDrafts(slotTexts: ["HELLO"], selectedSlot: 0)
}

/// Where drafts live between launches. The ViewModel never knows what is behind it.
/// `load()` answers nil for absent or unreadable data; the caller treats nil as empty.
nonisolated protocol MessageStoring: Sendable {
    func load() async -> SavedDrafts?
    func save(_ drafts: SavedDrafts) async throws
}
