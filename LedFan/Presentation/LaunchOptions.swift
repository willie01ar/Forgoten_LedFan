import Foundation

/// Command-line overrides for evidence and UI tests. None of them exist in normal use.
///
///   -columnsPerRevolution 120   narrower preview geometry, so a long message scrolls
///   -transientStore YES         drafts live in memory; the container is never touched
///   -seedDrafts "a|b|c"          with the transient store: the eight slots' starting text, pipe-separated
enum LaunchOptions {
    static var previewGeometry: FanGeometry {
        let columns = UserDefaults.standard.integer(forKey: "columnsPerRevolution")
        guard columns > 0 else { return .preview }
        return FanGeometry(ledsPerArm: FanGeometry.preview.ledsPerArm, columnsPerRevolution: columns)
    }

    static var messageStore: any MessageStoring {
        guard UserDefaults.standard.bool(forKey: "transientStore") else { return FileMessageStore() }
        guard let seed = UserDefaults.standard.string(forKey: "seedDrafts") else { return TransientMessageStore() }
        let texts = seed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return TransientMessageStore(initial: SavedDrafts(slotTexts: texts, selectedSlot: 0))
    }
}
