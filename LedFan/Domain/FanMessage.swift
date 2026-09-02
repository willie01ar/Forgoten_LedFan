import Foundation

/// One of the fan's message slots and its text. The limits are the fan's own (D5): eight
/// messages of up to 26 characters. Validation lives here, not in the view.
nonisolated struct FanMessage: Sendable, Equatable, Identifiable {
    static let maximumCharacters = 26
    static let slotCount = 8
    static let slots = 0..<slotCount

    let slot: Int
    let text: String

    var id: Int { slot }

    /// Slot numbers as a person counts them, 1 to 8.
    var displayNumber: Int { slot + 1 }

    init(slot: Int, text: String) throws(FanMessageError) {
        guard Self.slots.contains(slot) else { throw .slotOutOfRange(slot) }
        let excess = Self.excessCharacters(in: text)
        guard excess == 0 else { throw .tooLong(by: excess) }
        self.slot = slot
        self.text = text
    }

    /// How many characters over the limit a draft is; zero when it fits.
    static func excessCharacters(in text: String) -> Int {
        max(0, text.count - maximumCharacters)
    }
}

nonisolated enum FanMessageError: Error, Equatable {
    case slotOutOfRange(Int)
    case tooLong(by: Int)
}

extension FanMessageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .slotOutOfRange(let slot):
            return "Slot \(slot + 1) does not exist. The fan has \(FanMessage.slotCount) slots."
        case .tooLong(let excess):
            return "The message is \(excess) character\(excess == 1 ? "" : "s") over the fan's limit of \(FanMessage.maximumCharacters)."
        }
    }
}
