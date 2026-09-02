import Foundation
import Testing
@testable import LedFan

/// Records what the ViewModel stores, so the ViewModel can be tested without hardware.
actor RecordingTransport: FanDisplayTransport {
    nonisolated let displayName = "Recording"
    nonisolated let storeAvailability: FanStoreAvailability
    private(set) var storedMessages: [FanMessage] = []
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private let fanGeometry: FanGeometry
    private let connectShouldFail: Bool
    private let storeShouldFail: Bool

    init(geometry: FanGeometry = .preview,
         connectShouldFail: Bool = false,
         storeShouldFail: Bool = false,
         storeAvailability: FanStoreAvailability = .available) {
        fanGeometry = geometry
        self.connectShouldFail = connectShouldFail
        self.storeShouldFail = storeShouldFail
        self.storeAvailability = storeAvailability
    }

    var geometry: FanGeometry { fanGeometry }

    func connect() async throws {
        connectCount += 1
        if connectShouldFail { throw FanTransportError.deviceNotFound }
    }

    func store(_ message: FanMessage) async throws {
        if storeShouldFail { throw FanTransportError.writeFailed(code: -536870201) }
        storedMessages.append(message)
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

@MainActor
struct FanMessageViewModelTests {
    private let twentySix = "THE QUICK BROWN FOX JUMPS!"

    // MARK: - Preview

    @Test func editingTheMessageRefreshesThePreview() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        let before = viewModel.previewFrame

        viewModel.message = "DIFFERENT"

        #expect(viewModel.previewFrame != before)
        #expect(viewModel.previewFrame.columns.count == FanGeometry.preview.columnsPerRevolution)
    }

    @Test func thePreviewCentresAShortMessageOnTheTopOfTheDisc() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        viewModel.message = "HELLO"
        let strip = ColumnRasterizer().strip(for: "HELLO", ledsPerArm: 11)
        let expected = RevolutionComposer().frame(from: strip, geometry: .preview, columnOffset: -(strip.columns.count / 2))
        #expect(viewModel.previewFrame == expected)
    }

    @Test func clearingTheMessageProducesABlankPreview() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        viewModel.message = ""
        #expect(viewModel.previewFrame.isBlank)
        #expect(viewModel.previewDescription == "Fan preview, slot 1, empty")
    }

    @Test func thePreviewDescriptionNamesTheMessageAndSlot() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        viewModel.selectedSlot = 2
        viewModel.message = "HI"
        #expect(viewModel.previewDescription == "Fan preview showing HI in slot 3")
    }

    // MARK: - Slots and limits

    @Test func eachSlotKeepsItsOwnDraft() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
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
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
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
        let viewModel = FanMessageViewModel(transport: transport)
        await viewModel.connect()
        viewModel.message = twentySix + "?"

        #expect(!viewModel.canSend)
        await viewModel.sendMessage()

        #expect(await transport.storedMessages.isEmpty)
        #expect(viewModel.message == twentySix + "?", "the draft must not be silently cut")
    }

    @Test func blankGlyphsAreNamedOnce() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        viewModel.message = "HÉLLO 🙂🙂"
        #expect(viewModel.blankGlyphHint == "No glyph for “É”, “🙂”. Shown blank.")
        viewModel.message = "HELLO"
        #expect(viewModel.blankGlyphHint == nil)
    }

    // MARK: - Sending

    @Test func sendingIsBlockedUntilConnected() async {
        let transport = RecordingTransport()
        let viewModel = FanMessageViewModel(transport: transport)

        await viewModel.sendMessage()

        #expect(await transport.storedMessages.isEmpty)
        #expect(!viewModel.canSend)
    }

    @Test func connectingThenSendingStoresTheSelectedSlot() async throws {
        let transport = RecordingTransport()
        let viewModel = FanMessageViewModel(transport: transport)
        viewModel.selectedSlot = 4
        viewModel.message = "FIVE"

        await viewModel.connect()
        await viewModel.sendMessage()

        #expect(viewModel.status == .connected)
        #expect(await transport.storedMessages == [try FanMessage(slot: 4, text: "FIVE")])
        #expect(viewModel.lastStored?.hasPrefix("Stored in slot 5 at ") == true)
    }

    @Test func connectingAdoptsTheTransportGeometry() async {
        let geometry = FanGeometry(ledsPerArm: 7, columnsPerRevolution: 90)
        let viewModel = FanMessageViewModel(transport: RecordingTransport(geometry: geometry))

        await viewModel.connect()

        #expect(viewModel.geometry == geometry)
        #expect(viewModel.previewFrame.geometry == geometry)
        #expect(viewModel.previewFrame.columns.count == 90)
    }

    @Test func aFailedConnectionSurfacesTheReason() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(connectShouldFail: true))

        await viewModel.connect()

        #expect(viewModel.status != .connected)
        #expect(!viewModel.canSend)
        #expect(viewModel.status.summary == FanTransportError.deviceNotFound.localizedDescription)
    }

    @Test func aFailedStoreSurfacesTheReasonAndStaysConnected() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(storeShouldFail: true))

        await viewModel.connect()
        await viewModel.sendMessage()

        #expect(viewModel.status == .connected)
        #expect(viewModel.lastError == FanTransportError.writeFailed(code: -536870201).localizedDescription)
        #expect(viewModel.lastStored == nil)
    }

    @Test func aTransportThatCannotStoreDisablesSendAndExplainsWhy() async {
        let transport = RecordingTransport(storeAvailability: .unavailable(reason: "Not yet."))
        let viewModel = FanMessageViewModel(transport: transport)

        await viewModel.connect()

        #expect(viewModel.status == .connected)
        #expect(!viewModel.canSend)
        #expect(viewModel.storeUnavailableReason == "Not yet.")
        await viewModel.sendMessage()
        #expect(await transport.storedMessages.isEmpty)
    }

    @Test func disconnectingReturnsToDisconnected() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())

        await viewModel.connect()
        await viewModel.disconnect()

        #expect(viewModel.status == .disconnected)
        #expect(!viewModel.canSend)
    }

    @Test func transportNameIsExposedForTheUI() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        #expect(viewModel.transportName == "Recording")
    }

    // MARK: - Transport selection

    @Test func theSimulatedTransportIsTheDefault() {
        let viewModel = FanMessageViewModel(transportProvider: RecordingTransportProvider())
        #expect(viewModel.transportKind == .simulated)
        #expect(viewModel.storeUnavailableReason == nil)
    }

    @Test func switchingKindDisconnectsThePreviousTransportAndResetsState() async {
        let provider = RecordingTransportProvider()
        let viewModel = FanMessageViewModel(transportProvider: provider, transportKind: .hardware)
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
        let viewModel = FanMessageViewModel(transportProvider: provider)

        viewModel.transportKind = .simulated
        await viewModel.connect()
        viewModel.message = "A"
        await viewModel.sendMessage()

        #expect(await provider.simulated.storedMessages.count == 1)
        #expect(await provider.hardware.storedMessages.isEmpty)
    }

    @Test func selectingTheSameKindAgainKeepsTheConnection() async {
        let provider = RecordingTransportProvider()
        let viewModel = FanMessageViewModel(transportProvider: provider)
        await viewModel.connect()

        viewModel.transportKind = .simulated

        #expect(viewModel.status == .connected)
        #expect(await provider.simulated.disconnectCount == 0)
    }

    @Test func theHardwareKindExplainsThatItCannotStoreAndSendStaysOff() async {
        let provider = RecordingTransportProvider()
        let viewModel = FanMessageViewModel(transportProvider: provider)
        viewModel.transportKind = .hardware
        await viewModel.connect()

        #expect(viewModel.status == .connected)
        #expect(viewModel.storeUnavailableReason == "Hardware cannot store yet.")
        #expect(!viewModel.canSend)
    }

    @Test func aPinnedTransportIgnoresTheKind() async {
        let transport = RecordingTransport()
        let viewModel = FanMessageViewModel(transport: transport)
        await viewModel.connect()

        viewModel.transportKind = .hardware
        await viewModel.connect()

        #expect(viewModel.transportName == "Recording")
        #expect(await transport.connectCount == 2)
    }

    // MARK: - Helpers

    /// The ViewModel disconnects a replaced transport in a detached task; give it a few turns.
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<200 where await !condition() {
            await Task.yield()
        }
    }
}
