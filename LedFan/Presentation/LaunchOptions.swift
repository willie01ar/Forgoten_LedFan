import Foundation

/// Command-line overrides for evidence and UI tests. None of them exist in normal use.
///
///   -columnsPerRevolution 120   narrower preview geometry, so a long message scrolls
///   -transientStore YES         drafts live in memory; the container is never touched
///   -seedDrafts a%7Cb%7Cc       with the transient store: the eight fields' starting text, pipe-separated
///                               and percent-encoded (UserDefaults mangles asterisks and quotes otherwise)
enum LaunchOptions {
    static var previewGeometry: FanGeometry {
        let columns = UserDefaults.standard.integer(forKey: "columnsPerRevolution")
        guard columns > 0 else { return .preview }
        return FanGeometry(ledsPerArm: FanGeometry.preview.ledsPerArm, columnsPerRevolution: columns)
    }

    static var messageStore: any MessageStoring {
        guard UserDefaults.standard.bool(forKey: "transientStore") else { return FileMessageStore() }
        guard let encoded = UserDefaults.standard.string(forKey: "seedDrafts"),
              let seed = encoded.removingPercentEncoding else { return TransientMessageStore() }
        let texts = seed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        return TransientMessageStore(initial: SavedDrafts(slotTexts: texts, selectedSlot: 0))
    }
}
