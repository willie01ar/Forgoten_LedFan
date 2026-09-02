import Foundation
import Observation

@MainActor
@Observable
final class FanMessageViewModel {
    var selectedSlot: Int = 0 {
        didSet { refreshPreview() }
    }

    /// The draft for the selected slot. Drafts for all slots survive slot changes.
    var message: String {
        get { slotTexts[selectedSlot] }
        set { slotTexts[selectedSlot] = newValue; refreshPreview() }
    }

    var transportKind: FanTransportKind {
        didSet { if oldValue != transportKind { replaceTransport() } }
    }

    private(set) var slotTexts: [String] = ["HELLO"] + Array(repeating: "", count: FanMessage.slotCount - 1)
    private(set) var status: FanConnectionStatus = .disconnected
    private(set) var previewFrame: POVFrame = .blank(geometry: .preview)
    private(set) var geometry: FanGeometry = .preview
    private(set) var lastError: String?
    private(set) var lastStored: String?

    private let transportProvider: any FanTransportProviding
    private let rasterizer: any MessageRasterizing
    private let composer: any FrameComposing
    private var transport: any FanDisplayTransport

    init(transportProvider: any FanTransportProviding = DefaultFanTransportProvider(),
         rasterizer: any MessageRasterizing = ColumnRasterizer(),
         composer: any FrameComposing = RevolutionComposer(),
         transportKind: FanTransportKind = .simulated) {
        self.transportProvider = transportProvider
        self.rasterizer = rasterizer
        self.composer = composer
        self.transportKind = transportKind
        transport = transportProvider.makeTransport(for: transportKind)
        refreshPreview()
    }

    /// Pins one transport regardless of the selected kind. For tests and previews.
    convenience init(transport: any FanDisplayTransport,
                     rasterizer: any MessageRasterizing = ColumnRasterizer(),
                     composer: any FrameComposing = RevolutionComposer()) {
        self.init(transportProvider: FixedTransportProvider(transport: transport), rasterizer: rasterizer, composer: composer)
    }

    // MARK: - Derived state for the view

    var transportName: String { transport.displayName }
    var characterCount: Int { message.count }
    var excessCharacters: Int { FanMessage.excessCharacters(in: message) }
    var messageFitsTheFan: Bool { excessCharacters == 0 }
    var counterText: String { "\(characterCount)/\(FanMessage.maximumCharacters)" }

    /// Why the draft cannot be stored as typed, or nil when it can.
    var lengthProblem: String? {
        guard excessCharacters > 0 else { return nil }
        return FanMessageError.tooLong(by: excessCharacters).localizedDescription
    }

    /// Characters in the draft with no glyph, which the preview draws blank (D4).
    var blankGlyphHint: String? {
        var seen = Set<Character>()
        let missing = message.filter { !GlyphFont.supports($0) && seen.insert($0).inserted }
        guard !missing.isEmpty else { return nil }
        return "No glyph for \(missing.map { "“\($0)”" }.joined(separator: ", ")). Shown blank."
    }

    /// The transport's own reason it cannot take messages, or nil when it can.
    var storeUnavailableReason: String? {
        if case .unavailable(let reason) = transport.storeAvailability { return reason }
        return nil
    }

    var canSend: Bool {
        status.allowsSending && messageFitsTheFan && storeUnavailableReason == nil
    }

    var previewDescription: String {
        let slot = "slot \(selectedSlot + 1)"
        return message.isEmpty ? "Fan preview, \(slot), empty" : "Fan preview showing \(message) in \(slot)"
    }

    // MARK: - Lifecycle

    func connect() async {
        status = .connecting
        lastError = nil
        do {
            try await transport.connect()
            geometry = await transport.geometry
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
        guard canSend else { return }
        lastError = nil
        do {
            let fanMessage = try FanMessage(slot: selectedSlot, text: message)
            try await transport.store(fanMessage)
            lastStored = "Stored in slot \(fanMessage.displayNumber) at \(Date.now.formatted(date: .omitted, time: .standard))"
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Short messages are centred on the top of the disc; longer ones start there and wrap.
    private func refreshPreview() {
        let strip = rasterizer.strip(for: message, ledsPerArm: geometry.ledsPerArm)
        let fitsOneRevolution = strip.columns.count <= geometry.columnsPerRevolution
        let offset = fitsOneRevolution ? -(strip.columns.count / 2) : 0
        previewFrame = composer.frame(from: strip, geometry: geometry, columnOffset: offset)
    }

    private func replaceTransport() {
        let previous = transport
        transport = transportProvider.makeTransport(for: transportKind)
        status = .disconnected
        lastError = nil
        lastStored = nil
        geometry = .preview
        refreshPreview()
        Task { await previous.disconnect() }
    }
}
