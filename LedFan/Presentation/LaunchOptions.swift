import Foundation

/// Command-line overrides for evidence and UI tests. None of them exist in normal use.
///
///   -columnsPerRevolution 120   narrower preview geometry, so a long message scrolls
///   -transientStore YES         drafts live in memory; the container is never touched
enum LaunchOptions {
    static var previewGeometry: FanGeometry {
        let columns = UserDefaults.standard.integer(forKey: "columnsPerRevolution")
        guard columns > 0 else { return .preview }
        return FanGeometry(ledsPerArm: FanGeometry.preview.ledsPerArm, columnsPerRevolution: columns)
    }

    static var messageStore: any MessageStoring {
        UserDefaults.standard.bool(forKey: "transientStore") ? TransientMessageStore() : FileMessageStore()
    }
}
