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

    // MARK: - Preview follows focus

    @Test func editingTheFocusedFieldRefreshesThePreview() {
        let viewModel = viewModel()
        viewModel.focusedField = 0
        let before = viewModel.previewFrame

        viewModel.setText("DIFFERENT", forField: 0)

        #expect(viewModel.previewFrame != before)
        #expect(viewModel.previewFrame.columns.count == FanGeometry.preview.columnsPerRevolution)
    }

    @Test func thePreviewCentresAShortMessageOnTheTopOfTheDisc() {
        let viewModel = viewModel()
        viewModel.focusedField = 0
        viewModel.setText("HELLO", forField: 0)
        let strip = ColumnRasterizer().strip(for: "HELLO", ledsPerArm: 11)
        let expected = RevolutionComposer().frame(from: strip, geometry: .preview, columnOffset: -(strip.columns.count / 2))
        #expect(viewModel.previewFrame == expected)
    }

    @Test func withNoFocusThePreviewShowsTheFirstFilledField() {
        let viewModel = viewModel()
        viewModel.setText("THIRD", forField: 2)
        viewModel.setText("FIFTH", forField: 4)
        #expect(viewModel.previewField == 2)
        #expect(viewModel.previewText == "THIRD")
        #expect(viewModel.previewDescription == "Fan preview showing THIRD (message 3)")
    }

    @Test func focusWinsOverTheFirstFilledField() {
        let viewModel = viewModel()
        viewModel.setText("THIRD", forField: 2)
        viewModel.focusedField = 5
        #expect(viewModel.previewField == 5)
        #expect(viewModel.previewDescription == "Fan preview, message 6, empty")
        #expect(viewModel.previewFrame.isBlank)
        viewModel.focusedField = nil
        #expect(viewModel.previewDescription == "Fan preview showing THIRD (message 3)")
    }

    @Test func withNothingFilledAndNoFocusThePreviewIsBlank() {
        let viewModel = viewModel()
        #expect(viewModel.previewField == nil)
        #expect(viewModel.previewFrame.isBlank)
        #expect(viewModel.previewDescription == "Fan preview, nothing to show")
    }

    // MARK: - Scrolling

    @Test func aMessageThatFitsOneRevolutionDoesNotScroll() {
        let viewModel = viewModel()
        viewModel.setText(twentySix, forField: 0)          // 156 columns < 180
        #expect(!viewModel.scrollingIsPossible)
        #expect(viewModel.previewFrame(at: .now.addingTimeInterval(5)) == viewModel.previewFrame)
    }

    @Test func aMessageLongerThanARevolutionScrollsAtTheDesignSystemSpeed() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(geometry: narrow), messageStore: TransientMessageStore())
        await viewModel.connect()                       // adopts the 60-column geometry
        viewModel.setText(twentySix, forField: 0)       // 156 columns > 60
        #expect(viewModel.scrollingIsPossible)

        let strip = ColumnRasterizer().strip(for: twentySix, ledsPerArm: 11)
        let padded = ColumnStrip(ledsPerArm: 11, columns: strip.columns + [UInt16](repeating: 0, count: Motion.scrollGapColumns))
        let later = viewModel.scrollEpoch.addingTimeInterval(2)
        let expected = RevolutionComposer().frame(from: padded, geometry: narrow, columnOffset: -Int(2 * Motion.scrollColumnsPerSecond))

        #expect(viewModel.previewFrame(at: later) == expected)
        #expect(viewModel.previewFrame(at: nil) == viewModel.previewFrame, "nil date means the static frame")
    }

    @Test func aScrollingMessageWrapsThroughAGapNotASeam() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(geometry: narrow), messageStore: TransientMessageStore())
        await viewModel.connect()
        viewModel.setText(twentySix, forField: 0)
        let strip = ColumnRasterizer().strip(for: twentySix, ledsPerArm: 11)
        let period = Double(strip.columns.count + Motion.scrollGapColumns) / Motion.scrollColumnsPerSecond

        #expect(viewModel.previewFrame(at: viewModel.scrollEpoch.addingTimeInterval(period)) == viewModel.previewFrame)
        let frame = viewModel.previewFrame(at: viewModel.scrollEpoch.addingTimeInterval(Double(strip.columns.count) / Motion.scrollColumnsPerSecond))
        #expect(frame.columns[0..<Motion.scrollGapColumns].allSatisfy { $0 == 0 })
    }

    // MARK: - Persistence

    @Test func restoringLoadsEveryField() async {
        let saved = SavedDrafts(slotTexts: ["ONE", "TWO", "", "", "", "", "", "EIGHT"], selectedSlot: 7)
        let viewModel = viewModel(store: RecordingMessageStore(stored: saved))

        await viewModel.restore()

        #expect(viewModel.fieldTexts == saved.slotTexts)
        #expect(viewModel.previewDescription == "Fan preview showing ONE (message 1)")
    }

    @Test func restoringWithNothingSavedLeavesEveryFieldEmpty() async {
        let viewModel = viewModel(store: RecordingMessageStore(stored: nil))
        await viewModel.restore()
        #expect(viewModel.fieldTexts == SavedDrafts.empty.slotTexts)
    }

    @Test func everyEditIsSaved() async {
        let store = RecordingMessageStore()
        let viewModel = viewModel(store: store)

        viewModel.setText("A", forField: 0)
        viewModel.setText("D", forField: 3)
        await waitUntil { await store.saves.count >= 2 }

        #expect(await store.saves.last?.slotTexts == ["A", "", "", "D", "", "", "", ""])
    }

    @Test func aFailedSaveSurfacesAsAnErrorNotACrash() async {
        let viewModel = viewModel(store: RecordingMessageStore(saveShouldFail: true))
        viewModel.setText("A", forField: 0)
        await waitUntil { viewModel.lastError != nil }
        #expect(viewModel.lastError?.isEmpty == false)
        #expect(viewModel.text(forField: 0) == "A", "the draft is kept even when saving fails")
    }

    // MARK: - Limits

    @Test func eachFieldHasItsOwnCounter() {
        let viewModel = viewModel()
        viewModel.setText(twentySix, forField: 1)
        #expect(viewModel.counterText(forField: 1) == "26/26")
        #expect(viewModel.counterText(forField: 0) == "0/26")
        #expect(viewModel.fieldFitsTheFan(1))
        viewModel.setText(twentySix + "?", forField: 1)
        #expect(viewModel.counterText(forField: 1) == "27/26")
        #expect(!viewModel.fieldFitsTheFan(1))
    }

    @Test func overLengthFieldsAreNamedAndBlockSendWithoutBeingCut() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()
        viewModel.setText("FINE", forField: 0)
        viewModel.setText(twentySix + "?", forField: 2)
        viewModel.setText(twentySix + "??", forField: 6)

        #expect(viewModel.overLengthFields == [2, 6])
        #expect(viewModel.lengthProblem == "Message 3 is 1 character over the fan's limit of 26. Message 7 is 2 characters over the fan's limit of 26.")
        #expect(!viewModel.canSend)
        await viewModel.sendMessage()
        #expect(await transport.storedSets.isEmpty)
        #expect(viewModel.text(forField: 2) == twentySix + "?", "the draft must not be silently cut")
    }

    @Test func blankGlyphsAreNamedOnceForThePreviewedMessage() {
        let viewModel = viewModel()
        viewModel.setText("HÉLLO 🙂🙂", forField: 0)
        #expect(viewModel.blankGlyphHint == "No glyph for “É”, “🙂”. Shown blank.")
        viewModel.setText("Hello", forField: 0)
        #expect(viewModel.blankGlyphHint == nil)
    }

    // MARK: - Sending publishes the filled fields, compacted (D22)

    @Test func sendingIsBlockedUntilConnected() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        viewModel.setText("HI", forField: 0)
        await viewModel.sendMessage()
        #expect(await transport.storedSets.isEmpty)
        #expect(!viewModel.canSend)
    }

    @Test func threeFilledFieldsBecomeThreeMessagesNumberedFromZero() async throws {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        viewModel.setText("FIRST", forField: 0)
        viewModel.setText("FOURTH", forField: 3)
        viewModel.setText("EIGHTH", forField: 7)

        await viewModel.connect()
        await viewModel.sendMessage()

        let sent = await transport.storedMessages
        #expect(sent.map(\.slot) == [0, 1, 2])
        #expect(sent.map(\.text) == ["FIRST", "FOURTH", "EIGHTH"])
        #expect(viewModel.filledCount == 3)
    }

    @Test func aGapInTheMiddleCompacts() {
        let viewModel = viewModel()
        viewModel.setText("A", forField: 1)
        viewModel.setText("C", forField: 5)
        #expect(viewModel.filledMessages.map(\.slot) == [0, 1])
        #expect(viewModel.filledMessages.map(\.text) == ["A", "C"])
    }

    @Test func allEmptyDisablesSendEvenWhenConnected() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()
        #expect(viewModel.filledCount == 0)
        #expect(!viewModel.canSend)
        await viewModel.sendMessage()
        #expect(await transport.storedSets.isEmpty)
    }

    @Test func theExplanationSaysSendReplacesEverythingAndSkipsEmptyFields() {
        #expect(FanMessageViewModel.sendExplanation.contains("replaces everything the fan holds"))
        #expect(FanMessageViewModel.sendExplanation.contains("Empty fields are not sent"))
    }

    // MARK: - Plain copy (D24)

    @Test func successIsPlainAndCarriesNoDiagnostics() async {
        let receipt = FanStoreReceipt(summary: "Published all 3 slots: 120 reports (960 bytes) in 1.0 s. Every report was confirmed by the fan's echo.",
                                      reportCount: 120, byteCount: 960, confirmedCount: 120)
        let viewModel = viewModel(transport: RecordingTransport(receipt: receipt))
        viewModel.setText("A", forField: 0)
        viewModel.setText("B", forField: 4)
        await viewModel.connect()
        await viewModel.sendMessage()

        let success = viewModel.lastSuccess ?? ""
        #expect(success.hasSuffix("Sent 2 messages to Recording."))
        #expect(!success.contains("report") && !success.contains("byte") && !success.contains("echo"))
        #expect(viewModel.lastError == nil)
    }

    @Test func oneMessageReadsSingular() async {
        let viewModel = viewModel()
        viewModel.setText("A", forField: 6)
        await viewModel.connect()
        await viewModel.sendMessage()
        #expect(viewModel.lastSuccess?.hasSuffix("Sent 1 message to Recording.") == true)
    }

    @Test func anUnconfirmedTransferIsAnErrorNotASuccess() async {
        let receipt = FanStoreReceipt(summary: "diagnostics", reportCount: 120, byteCount: 960, confirmedCount: 118, mismatchedCount: 2)
        let viewModel = viewModel(transport: RecordingTransport(receipt: receipt))
        viewModel.setText("A", forField: 0)
        await viewModel.connect()
        await viewModel.sendMessage()

        #expect(viewModel.lastSuccess == nil)
        #expect(viewModel.lastError?.contains("did not confirm") == true)
        #expect(viewModel.lastError?.contains("118") == false, "no counts in the interface")
    }

    @Test func transportErrorsSurviveVerbatim() async {
        let viewModel = viewModel(transport: RecordingTransport(storeError: .tableTooLarge(bytes: 3000, limit: 2048)))
        viewModel.setText("A", forField: 0)
        await viewModel.connect()
        await viewModel.sendMessage()
        #expect(viewModel.lastError == FanTransportError.tableTooLarge(bytes: 3000, limit: 2048).localizedDescription)
        #expect(viewModel.status == .connected)
    }

    @Test func connectingAdoptsTheTransportGeometry() async {
        let geometry = FanGeometry(ledsPerArm: 7, columnsPerRevolution: 90)
        let viewModel = viewModel(transport: RecordingTransport(geometry: geometry))
        await viewModel.connect()
        #expect(viewModel.geometry == geometry)
        #expect(viewModel.previewFrame.columns.count == 90)
    }

    @Test func aFailedConnectionSurfacesTheReason() async {
        let viewModel = viewModel(transport: RecordingTransport(connectShouldFail: true))
        await viewModel.connect()
        #expect(viewModel.status != .connected)
        #expect(!viewModel.canSend)
        #expect(viewModel.status.summary == FanTransportError.deviceNotFound.localizedDescription)
    }

    @Test func aTransportThatCannotStoreDisablesSendAndExplainsWhy() async {
        let transport = RecordingTransport(storeAvailability: .unavailable(reason: "Not yet."))
        let viewModel = viewModel(transport: transport)
        viewModel.setText("A", forField: 0)
        await viewModel.connect()
        #expect(!viewModel.canSend)
        #expect(viewModel.storeUnavailableReason == "Not yet.")
    }

    @Test func anExperimentalTransportKeepsSendEnabledAndShowsItsCaveat() async {
        let transport = RecordingTransport(storeAvailability: .experimental(caveat: "Program it switched off."))
        let viewModel = viewModel(transport: transport)
        viewModel.setText("HI", forField: 0)
        await viewModel.connect()
        #expect(viewModel.canSend)
        #expect(viewModel.storeCaveat == "Program it switched off.")
    }

    // MARK: - Device removal (D21)

    @Test func aRemovedDeviceOnSendLandsInDisconnectedWithTheUnpluggedCopy() async {
        let viewModel = viewModel(transport: RecordingTransport(storeError: .deviceRemoved))
        viewModel.setText("HI", forField: 0)
        await viewModel.connect()
        await viewModel.sendMessage()
        #expect(viewModel.status == .disconnected)
        #expect(!viewModel.canSend)
        #expect(viewModel.lastError == FanTransportError.deviceRemoved.localizedDescription)
    }

    @Test func anUnplugEventDisconnectsOnItsOwn() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()
        transport.unplug()
        await waitUntil { viewModel.status == .disconnected }
        #expect(viewModel.status == .disconnected)
        #expect(viewModel.lastError?.contains("unplugged") == true)
    }

    @Test func disconnectingStopsListeningForUnplugs() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()
        await viewModel.disconnect()
        transport.unplug()
        await waitUntil { false }
        #expect(viewModel.lastError == nil)
    }

    @Test func theRemovalWatchFollowsATransportSwitch() async {
        let provider = RecordingTransportProvider()
        let viewModel = providerViewModel(provider, kind: .hardware)
        await viewModel.connect()

        viewModel.transportKind = .simulated
        provider.hardware.unplug()
        await waitUntil { false }
        #expect(viewModel.lastError == nil, "the old transport's unplug is ignored after a switch")

        await viewModel.connect()
        provider.simulated.unplug()
        await waitUntil { viewModel.status == .disconnected }
        #expect(viewModel.lastError?.contains("unplugged") == true)
    }

    // MARK: - Transport selection (D23)

    @Test func theUSBFanIsFirstAndTheDefault() {
        #expect(FanTransportKind.allCases.first == .hardware)
        let viewModel = FanMessageViewModel(transportProvider: RecordingTransportProvider(), messageStore: TransientMessageStore())
        #expect(viewModel.transportKind == .hardware)
    }

    @Test func launchingWithoutAFanIsARestingStateNotAnError() {
        let viewModel = FanMessageViewModel(transportProvider: RecordingTransportProvider(), messageStore: TransientMessageStore())
        #expect(viewModel.status == .disconnected)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.status.summary == "Not connected")
    }

    @Test func switchingKindDisconnectsThePreviousTransportAndResetsState() async {
        let provider = RecordingTransportProvider()
        let viewModel = providerViewModel(provider, kind: .hardware)
        await viewModel.connect()
        #expect(viewModel.previewFrame.geometry.ledsPerArm == 7)

        viewModel.transportKind = .simulated

        #expect(viewModel.status == .disconnected)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.previewFrame.geometry == .preview)
        await waitUntil { await provider.hardware.disconnectCount == 1 }
        #expect(await provider.hardware.disconnectCount == 1)
    }

    @Test func selectingTheSameKindAgainKeepsTheConnection() async {
        let provider = RecordingTransportProvider()
        let viewModel = providerViewModel(provider)
        await viewModel.connect()
        viewModel.transportKind = .simulated
        #expect(viewModel.status == .connected)
    }

    @Test func aPinnedTransportIgnoresTheKind() async {
        let transport = RecordingTransport()
        let viewModel = viewModel(transport: transport)
        await viewModel.connect()
        viewModel.transportKind = .simulated
        await viewModel.connect()
        #expect(viewModel.transportName == "Recording")
        #expect(await transport.connectCount == 2)
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<500 where await !condition() {
            await Task.yield()
        }
    }
}
