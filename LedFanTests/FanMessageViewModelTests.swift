import Foundation
import Testing
@testable import LedFan

/// Records what the ViewModel stores, so the ViewModel can be tested without hardware.
actor RecordingTransport: FanDisplayTransport {
    nonisolated let displayName = "Recording"
    nonisolated let storeAvailability: FanStoreAvailability
    nonisolated let connectionEvents: AsyncStream<FanConnectionEvent>
    private let events: AsyncStream<FanConnectionEvent>.Continuation
    private(set) var storedSets: [[FanMessage]] = []
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private let fanGeometry: FanGeometry
    private let connectShouldFail: Bool
    private let storeError: FanTransportError?
    private let receipt: FanStoreReceipt?

    init(geometry: FanGeometry = .preview,
         connectShouldFail: Bool = false,
         storeError: FanTransportError? = nil,
         storeAvailability: FanStoreAvailability = .available,
         receipt: FanStoreReceipt? = nil) {
        fanGeometry = geometry
        self.connectShouldFail = connectShouldFail
        self.storeError = storeError
        self.storeAvailability = storeAvailability
        self.receipt = receipt
        let stream = AsyncStream.makeStream(of: FanConnectionEvent.self)
        connectionEvents = stream.stream
        events = stream.continuation
    }

    var geometry: FanGeometry { fanGeometry }
    var storedMessages: [FanMessage] { storedSets.last ?? [] }

    /// Simulates the fan being unplugged.
    nonisolated func unplug() { events.yield(.lost(reason: FanTransportError.deviceRemoved.localizedDescription)) }

    func connect() async throws {
        connectCount += 1
        if connectShouldFail { throw FanTransportError.deviceNotFound }
    }

    func store(_ messages: [FanMessage]) async throws -> FanStoreReceipt {
        if let storeError { throw storeError }
        storedSets.append(messages)
        return receipt ?? FanStoreReceipt(summary: "Recorded \(messages.count) slots.", reportCount: 0, byteCount: 0, confirmedCount: 0)
    }

    func disconnect() async { disconnectCount += 1 }
}

/// One recording transport per kind, so switching can be observed.
struct RecordingTransportProvider: FanTransportProviding {
    let simulated = RecordingTransport()
    let hardware = RecordingTransport(
        geometry: FanGeometry(ledsPerArm: 7, columnsPerRevolution: 90),
        storeAvailability: .unavailable(reason: "Hardware cannot store yet.")
    )

    func makeTransport(for kind: FanTransportKind) -> any FanDisplayTransport {
        switch kind {
        case .simulated: simulated
        case .hardware: hardware
        }
    }
}

/// A store that never touches the disk and remembers every save.
actor RecordingMessageStore: MessageStoring {
    private(set) var saves: [SavedDrafts] = []
    private let stored: SavedDrafts?
    private let saveShouldFail: Bool

    init(stored: SavedDrafts? = nil, saveShouldFail: Bool = false) {
        self.stored = stored
        self.saveShouldFail = saveShouldFail
    }

    func load() async -> SavedDrafts? { stored }

    func save(_ drafts: SavedDrafts) async throws {
        if saveShouldFail { throw CocoaError(.fileWriteNoPermission) }
        saves.append(drafts)
    }
}

@MainActor
struct FanMessageViewModelTests {
    private let twentySix = "THE QUICK BROWN FOX JUMPS!"
    private let narrow = FanGeometry(ledsPerArm: 11, columnsPerRevolution: 60)

    private func viewModel(store: any MessageStoring = TransientMessageStore(),
                           transport: RecordingTransport = RecordingTransport()) -> FanMessageViewModel {
        FanMessageViewModel(transport: transport, messageStore: store)
    }

    private func providerViewModel(_ provider: RecordingTransportProvider,
                                   kind: FanTransportKind = .simulated) -> FanMessageViewModel {
        FanMessageViewModel(transportProvider: provider, messageStore: TransientMessageStore(), transportKind: kind)
    }

    // MARK: - Preview

    @Test func editingTheMessageRefreshesThePreview() {
        let viewModel = viewModel()
        let before = viewModel.previewFrame

        viewModel.message = "DIFFERENT"

        #expect(viewModel.previewFrame != before)
        #expect(viewModel.previewFrame.columns.count == FanGeometry.preview.columnsPerRevolution)
    }

    @Test func thePreviewCentresAShortMessageOnTheTopOfTheDisc() {
        let viewModel = viewModel()
        viewModel.message = "HELLO"
        let strip = ColumnRasterizer().strip(for: "HELLO", ledsPerArm: 11)
        let expected = RevolutionComposer().frame(from: strip, geometry: .preview, columnOffset: -(strip.columns.count / 2))
        #expect(viewModel.previewFrame == expected)
    }

    @Test func slotsStartEmptyUntilRestored() {
        let viewModel = viewModel()
        #expect(viewModel.message.isEmpty)
        #expect(viewModel.previewFrame.isBlank)
        #expect(viewModel.previewDescription == "Fan preview, slot 1, empty")
    }

    @Test func thePreviewDescriptionNamesTheMessageAndSlot() {
        let viewModel = viewModel()
        viewModel.selectedSlot = 2
        viewModel.message = "HI"
        #expect(viewModel.previewDescription == "Fan preview showing HI in slot 3")
    }

    // MARK: - Scrolling

    @Test func aMessageThatFitsOneRevolutionDoesNotScroll() {
        let viewModel = viewModel()
        viewModel.message = twentySix          // 156 columns < 180
        #expect(!viewModel.scrollingIsPossible)
        #expect(viewModel.previewFrame(at: .now.addingTimeInterval(5)) == viewModel.previewFrame)
    }

    @Test func anEmptyMessageNeverScrolls() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(geometry: narrow), messageStore: TransientMessageStore())
        viewModel.message = ""
        #expect(!viewModel.scrollingIsPossible)
        #expect(viewModel.previewFrame(at: .now).isBlank)
    }

    @Test func aMessageLongerThanARevolutionScrollsAtTheDesignSystemSpeed() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(geometry: narrow), messageStore: TransientMessageStore())
        await viewModel.connect()                       // adopts the 60-column geometry
        viewModel.message = twentySix                   // 156 columns > 60
        #expect(viewModel.scrollingIsPossible)

        let strip = ColumnRasterizer().strip(for: twentySix, ledsPerArm: 11)
        let padded = ColumnStrip(ledsPerArm: 11, columns: strip.columns + [UInt16](repeating: 0, count: Motion.scrollGapColumns))
        let later = viewModel.scrollEpoch.addingTimeInterval(2)
        let expectedAdvance = Int(2 * Motion.scrollColumnsPerSecond)
        let expected = RevolutionComposer().frame(from: padded, geometry: narrow, columnOffset: -expectedAdvance)

        #expect(viewModel.previewFrame(at: later) == expected)
        #expect(viewModel.previewFrame(at: viewModel.scrollEpoch) == viewModel.previewFrame, "at the epoch the scrolled frame is the static one")
        #expect(viewModel.previewFrame(at: nil) == viewModel.previewFrame, "nil date means the static frame")
    }

    @Test func aScrollingMessageWrapsThroughAGapNotASeam() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(geometry: narrow), messageStore: TransientMessageStore())
        await viewModel.connect()
        viewModel.message = twentySix
        let strip = ColumnRasterizer().strip(for: twentySix, ledsPerArm: 11)
        let period = Double(strip.columns.count + Motion.scrollGapColumns) / Motion.scrollColumnsPerSecond

        let onePeriodLater = viewModel.previewFrame(at: viewModel.scrollEpoch.addingTimeInterval(period))
        #expect(onePeriodLater == viewModel.previewFrame, "after one full period the marquee is back at the start")

        let advance = strip.columns.count
        let frame = viewModel.previewFrame(at: viewModel.scrollEpoch.addingTimeInterval(Double(advance) / Motion.scrollColumnsPerSecond))
        #expect(frame.columns[0..<Motion.scrollGapColumns].allSatisfy { $0 == 0 })
    }

    @Test func editingRestartsTheScrollFromTheBeginning() {
        let viewModel = viewModel()
        let before = viewModel.scrollEpoch
        viewModel.message = "NEW"
        #expect(viewModel.scrollEpoch >= before)
    }

    // MARK: - Persistence

    @Test func restoringLoadsEveryDraftAndTheSelectedSlot() async {
        let saved = SavedDrafts(slotTexts: ["ONE", "TWO", "", "", "", "", "", "EIGHT"], selectedSlot: 7)
        let viewModel = viewModel(store: RecordingMessageStore(stored: saved))

        await viewModel.restore()

        #expect(viewModel.slotTexts == saved.slotTexts)
        #expect(viewModel.selectedSlot == 7)
        #expect(viewModel.message == "EIGHT")
        #expect(viewModel.previewDescription == "Fan preview showing EIGHT in slot 8")
    }

    @Test func restoringWithNothingSavedLeavesEverySlotEmpty() async {
        let viewModel = viewModel(store: RecordingMessageStore(stored: nil))
        await viewModel.restore()
        #expect(viewModel.slotTexts == SavedDrafts.empty.slotTexts)
        #expect(viewModel.selectedSlot == 0)
    }

    @Test func everyEditAndSlotChangeIsSaved() async {
        let store = RecordingMessageStore()
        let viewModel = viewModel(store: store)

        viewModel.message = "A"
        viewModel.selectedSlot = 3
        viewModel.message = "D"
        await waitUntil { await store.saves.count >= 3 }

        let last = await store.saves.last
        #expect(last == SavedDrafts(slotTexts: ["A", "", "", "D", "", "", "", ""], selectedSlot: 3))
    }

    @Test func aFailedSaveSurfacesAsAnErrorNotACrash() async {
        let viewModel = viewModel(store: RecordingMessageStore(saveShouldFail: true))
        viewModel.message = "A"
        await waitUntil { viewModel.lastError != nil }
        #expect(viewModel.lastError?.isEmpty == false)
        #expect(viewModel.message == "A", "the draft is kept even when saving fails")
    }

    // MARK: - Slots and limits

    @Test func eachSlotKeepsItsOwnDraft() {
        let viewModel = viewModel()
        viewModel.message = "FIRST"
        viewModel.selectedSlot = 1
        #expect(viewModel.message.isEmpty)
        viewModel.message = "SECOND"
        viewModel.selectedSlot = 0
        #expect(viewModel.message == "FIRST")
        viewModel.selectedSlot = 1
        #expect(viewModel.message == "SECOND")
        #expect(viewModel.slotTexts.count == FanMessage.slotCount)
    }

    @Test func theCounterTracksTheLimit() {
        let viewModel = viewModel()
        viewModel.message = twentySix
        #expect(viewModel.counterText == "26/26")
        #expect(viewModel.messageFitsTheFan)
        #expect(viewModel.lengthProblem == nil)

        viewModel.message = twentySix + "?"
        #expect(viewModel.counterText == "27/26")
        #expect(!viewModel.messageFitsTheFan)
        #expect(viewModel.lengthProblem?.contains("1 character over") == true)
    }

    @Test func anOverLengthDraftIsRefusedNotTruncated() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()
        viewModel.message = twentySix + "?"

        #expect(!viewModel.canSend)
        await viewModel.sendMessage()

        #expect(await transport.storedSets.isEmpty)
        #expect(viewModel.message == twentySix + "?", "the draft must not be silently cut")
    }

    @Test func anOverLengthDraftInAnotherSlotBlocksSendAndIsNamed() async {
        let viewModel = viewModel()
        await viewModel.connect()
        viewModel.selectedSlot = 2
        viewModel.message = twentySix + "?"
        viewModel.selectedSlot = 0
        viewModel.message = "FINE"

        #expect(viewModel.lengthProblem == nil)
        #expect(viewModel.otherOverLengthSlots == [2])
        #expect(viewModel.otherSlotsProblem?.contains("Slot 3 is over 26") == true)
        #expect(!viewModel.canSend)
    }

    @Test func blankGlyphsAreNamedOnce() {
        let viewModel = viewModel()
        viewModel.message = "HÉLLO 🙂🙂"
        #expect(viewModel.blankGlyphHint == "No glyph for “É”, “🙂”. Shown blank.")
        viewModel.message = "Hello"
        #expect(viewModel.blankGlyphHint == nil, "lowercase has glyphs now")
    }

    // MARK: - Sending publishes all eight slots (D19)

    @Test func sendingIsBlockedUntilConnected() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        viewModel.message = "HI"

        await viewModel.sendMessage()

        #expect(await transport.storedSets.isEmpty)
        #expect(!viewModel.canSend)
    }

    @Test func sendWritesAllEightSlotsInOrderWithEmptyOnesBlank() async throws {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        viewModel.selectedSlot = 4
        viewModel.message = "FIVE"
        viewModel.selectedSlot = 0
        viewModel.message = "ONE"

        await viewModel.connect()
        await viewModel.sendMessage()

        let sent = await transport.storedMessages
        #expect(sent.count == FanMessage.slotCount)
        #expect(sent.map(\.slot) == Array(0..<8))
        #expect(sent.map(\.text) == ["ONE", "", "", "", "FIVE", "", "", ""])
        #expect(viewModel.lastStored?.hasSuffix("Recorded 8 slots.") == true)
    }

    @Test func theExplanationSaysSendReplacesEverything() {
        #expect(FanMessageViewModel.sendExplanation.contains("all eight slots"))
        #expect(FanMessageViewModel.sendExplanation.contains("Empty slots are cleared"))
    }

    @Test func theReceiptIsShownVerbatimAfterTheTime() async {
        let receipt = FanStoreReceipt(summary: "Published all 8 slots: 320 reports. Every report was confirmed by the fan's echo.",
                                      reportCount: 320, byteCount: 2560, confirmedCount: 320)
        let viewModel = viewModel(transport: RecordingTransport(receipt: receipt))
        await viewModel.connect()
        await viewModel.sendMessage()
        #expect(viewModel.lastStored?.hasSuffix(receipt.summary) == true)
        #expect(receipt.everyReportConfirmed)
    }

    @Test func connectingAdoptsTheTransportGeometry() async {
        let geometry = FanGeometry(ledsPerArm: 7, columnsPerRevolution: 90)
        let viewModel = viewModel(transport: RecordingTransport(geometry: geometry))

        await viewModel.connect()

        #expect(viewModel.geometry == geometry)
        #expect(viewModel.previewFrame.geometry == geometry)
        #expect(viewModel.previewFrame.columns.count == 90)
    }

    @Test func aFailedConnectionSurfacesTheReason() async {
        let viewModel = viewModel(transport: RecordingTransport(connectShouldFail: true))

        await viewModel.connect()

        #expect(viewModel.status != .connected)
        #expect(!viewModel.canSend)
        #expect(viewModel.status.summary == FanTransportError.deviceNotFound.localizedDescription)
    }

    @Test func aFailedStoreSurfacesTheReasonAndStaysConnected() async {
        let viewModel = viewModel(transport: RecordingTransport(storeError: .writeFailed(code: -536870201)))
        viewModel.message = "HI"

        await viewModel.connect()
        await viewModel.sendMessage()

        #expect(viewModel.status == .connected)
        #expect(viewModel.lastError == FanTransportError.writeFailed(code: -536870201).localizedDescription)
        #expect(viewModel.lastStored == nil)
    }

    @Test func aTransportThatCannotStoreDisablesSendAndExplainsWhy() async {
        let transport = RecordingTransport(storeAvailability: .unavailable(reason: "Not yet."))
        let viewModel = viewModel(transport: transport)

        await viewModel.connect()

        #expect(viewModel.status == .connected)
        #expect(!viewModel.canSend)
        #expect(viewModel.storeUnavailableReason == "Not yet.")
        await viewModel.sendMessage()
        #expect(await transport.storedSets.isEmpty)
    }

    @Test func anExperimentalTransportKeepsSendEnabledAndShowsItsCaveat() async {
        let transport = RecordingTransport(storeAvailability: .experimental(caveat: "Not this generation."))
        let viewModel = viewModel(transport: transport)
        viewModel.message = "HI"

        await viewModel.connect()

        #expect(viewModel.canSend)
        #expect(viewModel.storeCaveat == "Not this generation.")
        #expect(viewModel.storeUnavailableReason == nil)
        await viewModel.sendMessage()
        #expect(await transport.storedSets.count == 1)
    }

    // MARK: - Device removal (D21)

    @Test func aRemovedDeviceOnSendLandsInDisconnectedWithTheUnpluggedCopy() async {
        let viewModel = viewModel(transport: RecordingTransport(storeError: .deviceRemoved))
        viewModel.message = "HI"
        await viewModel.connect()
        #expect(viewModel.canSend)

        await viewModel.sendMessage()

        #expect(viewModel.status == .disconnected)
        #expect(!viewModel.canSend)
        #expect(viewModel.lastError?.contains("unplugged") == true)
        #expect(viewModel.lastError?.lowercased().contains("rejected") == false)
    }

    @Test func anUnplugEventDisconnectsOnItsOwn() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()
        #expect(viewModel.status == .connected)

        transport.unplug()
        await waitUntil { viewModel.status == .disconnected }

        #expect(viewModel.status == .disconnected)
        #expect(!viewModel.canSend)
        #expect(viewModel.lastError?.contains("unplugged") == true)
    }

    @Test func disconnectingStopsListeningForUnplugs() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()
        await viewModel.disconnect()

        transport.unplug()
        await waitUntil { false }

        #expect(viewModel.lastError == nil, "an unplug after an orderly disconnect is not an error")
    }

    @Test func disconnectingReturnsToDisconnected() async {
        let viewModel = viewModel()

        await viewModel.connect()
        await viewModel.disconnect()

        #expect(viewModel.status == .disconnected)
        #expect(!viewModel.canSend)
    }

    @Test func transportNameIsExposedForTheUI() {
        #expect(viewModel().transportName == "Recording")
    }

    // MARK: - Transport selection

    @Test func theSimulatedTransportIsTheDefault() {
        let viewModel = providerViewModel(RecordingTransportProvider())
        #expect(viewModel.transportKind == .simulated)
        #expect(viewModel.storeUnavailableReason == nil)
    }

    @Test func switchingKindDisconnectsThePreviousTransportAndResetsState() async {
        let provider = RecordingTransportProvider()
        let viewModel = providerViewModel(provider, kind: .hardware)
        await viewModel.connect()
        #expect(viewModel.previewFrame.geometry.ledsPerArm == 7)

        viewModel.transportKind = .simulated

        #expect(viewModel.status == .disconnected)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.previewFrame.geometry == .preview, "geometry returns to the preview default until the new transport connects")
        await waitUntil { await provider.hardware.disconnectCount == 1 }
        #expect(await provider.hardware.disconnectCount == 1)
        #expect(await provider.simulated.connectCount == 0)
    }

    @Test func connectingAfterSwitchingUsesTheNewTransport() async {
        let provider = RecordingTransportProvider()
        let viewModel = providerViewModel(provider)

        viewModel.transportKind = .simulated
        await viewModel.connect()
        viewModel.message = "A"
        await viewModel.sendMessage()

        #expect(await provider.simulated.storedSets.count == 1)
        #expect(await provider.hardware.storedSets.isEmpty)
    }

    @Test func selectingTheSameKindAgainKeepsTheConnection() async {
        let provider = RecordingTransportProvider()
        let viewModel = providerViewModel(provider)
        await viewModel.connect()

        viewModel.transportKind = .simulated

        #expect(viewModel.status == .connected)
        #expect(await provider.simulated.disconnectCount == 0)
    }

    @Test func theHardwareKindExplainsThatItCannotStoreAndSendStaysOff() async {
        let provider = RecordingTransportProvider()
        let viewModel = providerViewModel(provider)
        viewModel.transportKind = .hardware
        await viewModel.connect()

        #expect(viewModel.status == .connected)
        #expect(viewModel.storeUnavailableReason == "Hardware cannot store yet.")
        #expect(!viewModel.canSend)
    }

    @Test func aPinnedTransportIgnoresTheKind() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()

        viewModel.transportKind = .hardware
        await viewModel.connect()

        #expect(viewModel.transportName == "Recording")
        #expect(await transport.connectCount == 2)
    }

    // MARK: - Helpers

    /// Saves, unplug events and the replaced transport's disconnect run in other tasks; give them a few turns.
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<500 where await !condition() {
            await Task.yield()
        }
    }
}
