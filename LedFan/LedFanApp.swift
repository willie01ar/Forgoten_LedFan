import AppKit
import SwiftUI

@main
struct LedFanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: FanMessageViewModel(messageStore: LaunchOptions.messageStore,
                                                       previewGeometry: LaunchOptions.previewGeometry))
                .task { if LaunchOptions.pinWindowToPrimaryDisplay { Self.moveWindowToPrimaryDisplay() } }
        }
    }

    /// Evidence and UI tests only. AppKit is the only way to place a window; SwiftUI's
    /// default position follows the active display, which follows the pointer.
    @MainActor
    private static func moveWindowToPrimaryDisplay() {
        guard let window = NSApplication.shared.windows.first, let screen = NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let origin = NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2)
        window.setFrameOrigin(origin)
    }
}
