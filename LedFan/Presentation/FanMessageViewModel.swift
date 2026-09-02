import Foundation
import Observation

@MainActor
@Observable
final class FanMessageViewModel {
    var message: String = "HELLO" {
        didSet { refreshPreview() }
    }

    var transportKind: FanTransportKind {
        didSet { if oldValue != transportKind { replaceTransport() } }
    }

    private(set) var status: FanConnectionStatus = .disconnected
    private(set) var previewFrame: POVFrame = .empty
    private(set) var lastError: String?

    private let transportProvider: any FanTransportProviding
    private let rasterizer: any MessageRasterizing
    private var transport: any FanDisplayTransport
    private var ledsPerArm = FanMessageViewModel.defaultLEDsPerArm

    private static let defaultLEDsPerArm = 11

    init(transportProvider: any FanTransportProviding = DefaultFanTransportProvider(),
         rasterizer: any MessageRasterizing = ColumnRasterizer(),
         transportKind: FanTransportKind = .simulated) {
        self.transportProvider = transportProvider
        self.rasterizer = rasterizer
        self.transportKind = transportKind
        transport = transportProvider.makeTransport(for: transportKind)
        refreshPreview()
    }

    /// Pins one transport regardless of the selected kind. For tests and previews.
    convenience init(transport: any FanDisplayTransport,
                     rasterizer: any MessageRasterizing = ColumnRasterizer()) {
        self.init(transportProvider: FixedTransportProvider(transport: transport), rasterizer: rasterizer)
    }

    var transportName: String { transport.displayName }

    /// Shown while the wire protocol is unknown, so a successful write is not mistaken for a working feature.
    var sendCaveat: String? {
        guard transportKind == .hardware else { return nil }
        return "The fan's command format is still unknown. Send writes an experimental packet layout the fan may ignore."
    }

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

    private func replaceTransport() {
        let previous = transport
        transport = transportProvider.makeTransport(for: transportKind)
        status = .disconnected
        lastError = nil
        ledsPerArm = Self.defaultLEDsPerArm
        refreshPreview()
        Task { await previous.disconnect() }
    }
}
