import Foundation
import Observation

@MainActor
@Observable
final class FanMessageViewModel {
    var selectedSlot: Int = 0 {
        didSet { refreshPreview(); persist() }
    }

    /// The draft for the selected slot. Drafts for all slots survive slot changes and relaunches.
    var message: String {
        get { slotTexts[selectedSlot] }
        set { slotTexts[selectedSlot] = newValue; refreshPreview(); persist() }
    }

    var transportKind: FanTransportKind {
        didSet { if oldValue != transportKind { replaceTransport() } }
    }

    private(set) var slotTexts: [String] = SavedDrafts.empty.slotTexts
    private(set) var status: FanConnectionStatus = .disconnected
    private(set) var previewFrame: POVFrame
    private(set) var geometry: FanGeometry
    private(set) var lastError: String?
    private(set) var lastStored: String?
    /// When the current message started scrolling; reset whenever the message changes.
    private(set) var scrollEpoch = Date.now

    private let transportProvider: any FanTransportProviding
    private let rasterizer: any MessageRasterizing
    private let composer: any FrameComposing
    private let messageStore: any MessageStoring
    private let previewGeometry: FanGeometry
    private var transport: any FanDisplayTransport
    private var strip: ColumnStrip = .empty(ledsPerArm: 0)

    init(transportProvider: any FanTransportProviding = DefaultFanTransportProvider(),
         rasterizer: any MessageRasterizing = ColumnRasterizer(),
         composer: any FrameComposing = RevolutionComposer(),
         messageStore: any MessageStoring = FileMessageStore(),
         previewGeometry: FanGeometry = .preview,
         transportKind: FanTransportKind = .simulated) {
        self.transportProvider = transportProvider
        self.rasterizer = rasterizer
        self.composer = composer
        self.messageStore = messageStore
        self.previewGeometry = previewGeometry
        self.transportKind = transportKind
        geometry = previewGeometry
        previewFrame = .blank(geometry: previewGeometry)
        transport = transportProvider.makeTransport(for: transportKind)
        refreshPreview()
    }

    /// Pins one transport regardless of the selected kind. For tests and previews.
    convenience init(transport: any FanDisplayTransport,
                     rasterizer: any MessageRasterizing = ColumnRasterizer(),
                     composer: any FrameComposing = RevolutionComposer(),
                     messageStore: any MessageStoring = TransientMessageStore()) {
        self.init(transportProvider: FixedTransportProvider(transport: transport),
                  rasterizer: rasterizer, composer: composer, messageStore: messageStore)
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

    // MARK: - Scrolling

    /// Only a message longer than one revolution has anything to scroll. Shorter ones stand
    /// still, centred on the top of the disc.
    var scrollingIsPossible: Bool {
        strip.columns.count > geometry.columnsPerRevolution
    }

    /// The frame to draw at `date` while scrolling, or the static frame when `date` is nil
    /// (Reduce Motion, hidden window, or nothing to scroll). The marquee runs towards the
    /// left of the top arc, so new characters enter on the right.
    func previewFrame(at date: Date?) -> POVFrame {
        guard let date, scrollingIsPossible else { return previewFrame }
        let elapsed = max(0, date.timeIntervalSince(scrollEpoch))
        let advance = Int((elapsed * Motion.scrollColumnsPerSecond).rounded())
        return composer.frame(from: scrollableStrip, geometry: geometry, columnOffset: -advance)
    }

    // MARK: - Lifecycle

    /// Loads the saved drafts. Absent or unreadable data leaves every slot empty.
    func restore() async {
        guard let saved = await messageStore.load() else { return }
        slotTexts = saved.slotTexts
        selectedSlot = saved.selectedSlot
    }

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

    /// Short messages are centred on the top of the disc; longer ones start there and scroll.
    private func refreshPreview() {
        strip = rasterizer.strip(for: message, ledsPerArm: geometry.ledsPerArm)
        let offset = scrollingIsPossible ? 0 : -(strip.columns.count / 2)
        previewFrame = composer.frame(from: strip, geometry: geometry, columnOffset: offset)
        scrollEpoch = .now
    }

    /// The strip with a dark gap after it, so a wrapped message never touches its own start.
    private var scrollableStrip: ColumnStrip {
        ColumnStrip(ledsPerArm: strip.ledsPerArm,
                    columns: strip.columns + [UInt16](repeating: 0, count: Motion.scrollGapColumns))
    }

    private func persist() {
        let snapshot = SavedDrafts(slotTexts: slotTexts, selectedSlot: selectedSlot)
        Task {
            do { try await messageStore.save(snapshot) } catch { lastError = error.localizedDescription }
        }
    }

    private func replaceTransport() {
        let previous = transport
        transport = transportProvider.makeTransport(for: transportKind)
        status = .disconnected
        lastError = nil
        lastStored = nil
        geometry = previewGeometry
        refreshPreview()
        Task { await previous.disconnect() }
    }
}
