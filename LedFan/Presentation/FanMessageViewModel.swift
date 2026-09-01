import Foundation
import Observation

@MainActor
@Observable
final class FanMessageViewModel {
    var message: String = "HELLO" {
        didSet { refreshPreview() }
    }

    private(set) var status: FanConnectionStatus = .disconnected
    private(set) var previewFrame: POVFrame = .empty
    private(set) var lastError: String?

    private let transport: any FanDisplayTransport
    private let rasterizer: any MessageRasterizing
    private var ledsPerArm = 11

    init(transport: any FanDisplayTransport = SimulatedFanTransport(),
         rasterizer: any MessageRasterizing = ColumnRasterizer()) {
        self.transport = transport
        self.rasterizer = rasterizer
        refreshPreview()
    }

    var transportName: String { transport.displayName }

    // MARK: - Lifecycle

    func connect() async {
        status = .connecting
        lastError = nil
        do {
            try await transport.connect()
            ledsPerArm = await transport.ledsPerArm
            status = .connected
            refreshPreview()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func disconnect() async {
        await transport.disconnect()
        status = .disconnected
    }

    // MARK: - Actions

    func sendMessage() async {
        guard status.allowsSending else { return }
        lastError = nil
        do {
            try await transport.display(previewFrame)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func refreshPreview() {
        previewFrame = rasterizer.frame(for: message, ledsPerArm: ledsPerArm)
    }
}
