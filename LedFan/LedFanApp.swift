import SwiftUI

@main
struct LedFanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: FanMessageViewModel(messageStore: LaunchOptions.messageStore,
                                                       previewGeometry: LaunchOptions.previewGeometry))
        }
    }
}
