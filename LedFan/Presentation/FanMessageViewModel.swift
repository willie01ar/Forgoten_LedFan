import Foundation
import Observation

@MainActor
@Observable
final class FanMessageViewModel {
    /// The field with keyboard focus, set by the view. The preview follows it.
    var focusedField: Int? {
        didSet { if oldValue != focusedField { refreshPreview() } }
    }

    var transportKind: FanTransportKind {
        didSet { if oldValue != transportKind { replaceTransport() } }
    }

    /// Eight fields, a UI convenience persisted as such; not fan slot numbers (D22).
    private(set) var fieldTexts: [String] = SavedDrafts.empty.slotTexts
    private(set) var status: FanConnectionStatus = .disconnected
    private(set) var previewFrame: POVFrame
    private(set) var geometry: FanGeometry
    private(set) var lastError: String?
    private(set) var lastSuccess: String?
    /// When the previewed message started scrolling; reset whenever it changes.
    private(set) var scrollEpoch = Date.now

    private let transportProvider: any FanTransportProviding
    private let rasterizer: any MessageRasterizing
    private let composer: any FrameComposing
    private let messageStore: any MessageStoring
    private let previewGeometry: FanGeometry
    private var transport: any FanDisplayTransport
    private var strip: ColumnStrip = .empty(ledsPerArm: 0)
    private var connectionWatch: Task<Void, Never>?

    static let fields = 0..<FanMessage.slotCount

    init(transportProvider: any FanTransportProviding = DefaultFanTransportProvider(),
         rasterizer: any MessageRasterizing = ColumnRasterizer(),
         composer: any FrameComposing = RevolutionComposer(),
         messageStore: any MessageStoring = FileMessageStore(),
         previewGeometry: FanGeometry = .preview,
         transportKind: FanTransportKind = .hardware) {
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

    // MARK: - Fields

    func text(forField index: Int) -> String { fieldTexts[index] }

    func setText(_ text: String, forField index: Int) {
        guard fieldTexts[index] != text else { return }
        fieldTexts[index] = text
        if index == previewField { refreshPreview() } else if focusedField == nil { refreshPreview() }
        persist()
    }

    func characterCount(forField index: Int) -> Int { fieldTexts[index].count }
    func counterText(forField index: Int) -> String { "\(characterCount(forField: index))/\(FanMessage.maximumCharacters)" }
    func fieldFitsTheFan(_ index: Int) -> Bool { FanMessage.excessCharacters(in: fieldTexts[index]) == 0 }

    var overLengthFields: [Int] { fieldTexts.indices.filter { !fieldFitsTheFan($0) } }

    /// Which messages are over the limit and by how much, or nil when all fit.
    var lengthProblem: String? {
        let problems = overLengthFields.map { index in
            let excess = FanMessage.excessCharacters(in: fieldTexts[index])
            return "Message \(index + 1) is \(excess) character\(excess == 1 ? "" : "s") over the fan's limit of \(FanMessage.maximumCharacters)."
        }
        return problems.isEmpty ? nil : problems.joined(separator: " ")
    }

    // MARK: - Preview

    /// The field the preview shows: the focused one, else the first with text, else none.
    var previewField: Int? {
        focusedField ?? fieldTexts.firstIndex { !$0.isEmpty }
    }

    var previewText: String { previewField.map { fieldTexts[$0] } ?? "" }

    var previewDescription: String {
        guard let field = previewField else { return "Fan preview, nothing to show" }
        let text = fieldTexts[field]
        return text.isEmpty ? "Fan preview, message \(field + 1), empty" : "Fan preview showing \(text) (message \(field + 1))"
    }

    /// Characters in the previewed message with no glyph, which the preview draws blank (D4).
    var blankGlyphHint: String? {
        var seen = Set<Character>()
        let missing = previewText.filter { !GlyphFont.supports($0) && seen.insert($0).inserted }
        guard !missing.isEmpty else { return nil }
        return "No glyph for \(missing.map { "“\($0)”" }.joined(separator: ", ")). Shown blank."
    }

    // MARK: - Sending (D22)

    /// The filled fields, in order, numbered from 0 with no gaps: what the fan will cycle.
    var filledMessages: [FanMessage] {
        fieldTexts.filter { !$0.isEmpty }.enumerated().compactMap { try? FanMessage(slot: $0.offset, text: $0.element) }
    }

    var filledCount: Int { fieldTexts.count { !$0.isEmpty } }

    static let sendExplanation = "Send publishes the filled messages and replaces everything the fan holds. Empty fields are not sent."

    var transportName: String { transport.displayName }

    /// The transport's own reason it cannot take messages, or nil when it can.
    var storeUnavailableReason: String? {
        if case .unavailable(let reason) = transport.storeAvailability { return reason }
        return nil
    }

    /// How to program this fan, from the transport, or nil.
    var storeCaveat: String? {
        if case .experimental(let caveat) = transport.storeAvailability { return caveat }
        return nil
    }

    var canSend: Bool {
        status.allowsSending && overLengthFields.isEmpty && filledCount > 0 && storeUnavailableReason == nil
    }

    // MARK: - Scrolling

    var scrollingIsPossible: Bool {
        strip.columns.count > geometry.columnsPerRevolution
    }

    /// The frame to draw at `date` while scrolling, or the static frame when `date` is nil.
    func previewFrame(at date: Date?) -> POVFrame {
        guard let date, scrollingIsPossible else { return previewFrame }
        let elapsed = max(0, date.timeIntervalSince(scrollEpoch))
        let advance = Int((elapsed * Motion.scrollColumnsPerSecond).rounded())
        return composer.frame(from: scrollableStrip, geometry: geometry, columnOffset: -advance)
    }

    // MARK: - Lifecycle

    /// Loads the saved drafts. Absent or unreadable data leaves every field empty.
    func restore() async {
        guard let saved = await messageStore.load() else { return }
        fieldTexts = saved.slotTexts
        refreshPreview()
    }

    func connect() async {
        status = .connecting
        lastError = nil
        do {
            try await transport.connect()
            geometry = await transport.geometry
            status = .connected
            refreshPreview()
            watchConnection()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func disconnect() async {
        stopWatchingConnection()
        await transport.disconnect()
        status = .disconnected
    }

    /// Publishes the filled messages; the fan keeps exactly what it is last given.
    func sendMessage() async {
        guard canSend else { return }
        lastError = nil
        lastSuccess = nil
        let messages = filledMessages
        do {
            let receipt = try await transport.store(messages)
            if receipt.reportCount > 0 && !receipt.everyReportConfirmed {
                lastError = "The fan did not confirm everything it was sent. Check the data cable and send again."
            } else {
                let count = messages.count == 1 ? "1 message" : "\(messages.count) messages"
                lastSuccess = "\(Date.now.formatted(date: .omitted, time: .shortened)): Sent \(count) to \(transportName)."
            }
        } catch FanTransportError.deviceRemoved {
            connectionLost(FanTransportError.deviceRemoved.localizedDescription)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func refreshPreview() {
        strip = rasterizer.strip(for: previewText, ledsPerArm: geometry.ledsPerArm)
        let offset = scrollingIsPossible ? 0 : -(strip.columns.count / 2)
        previewFrame = composer.frame(from: strip, geometry: geometry, columnOffset: offset)
        scrollEpoch = .now
    }

    private var scrollableStrip: ColumnStrip {
        ColumnStrip(ledsPerArm: strip.ledsPerArm,
                    columns: strip.columns + [UInt16](repeating: 0, count: Motion.scrollGapColumns))
    }

    private func persist() {
        let snapshot = SavedDrafts(slotTexts: fieldTexts, selectedSlot: focusedField ?? 0)
        Task {
            do { try await messageStore.save(snapshot) } catch { lastError = error.localizedDescription }
        }
    }

    /// The transport tells us when the fan goes away (D21); Send disables by itself.
    private func watchConnection() {
        stopWatchingConnection()
        let events = transport.connectionEvents
        connectionWatch = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled, let self else { return }
                if case .lost(let reason) = event { self.connectionLost(reason) }
            }
        }
    }

    private func stopWatchingConnection() {
        connectionWatch?.cancel()
        connectionWatch = nil
    }

    private func connectionLost(_ reason: String) {
        stopWatchingConnection()
        status = .disconnected
        lastError = reason
    }

    private func replaceTransport() {
        stopWatchingConnection()
        let previous = transport
        transport = transportProvider.makeTransport(for: transportKind)
        status = .disconnected
        lastError = nil
        lastSuccess = nil
        geometry = previewGeometry
        refreshPreview()
        Task { await previous.disconnect() }
    }
}
