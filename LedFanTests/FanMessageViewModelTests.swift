import Foundation
import Testing
@testable import LedFan

/// Records what the ViewModel sends, so the ViewModel can be tested without hardware.
actor RecordingTransport: FanDisplayTransport {
    nonisolated let displayName = "Recording"
    private(set) var displayedFrames: [POVFrame] = []
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private let arms: Int
    private let connectShouldFail: Bool
    private let displayShouldFail: Bool

    init(ledsPerArm: Int = 11, connectShouldFail: Bool = false, displayShouldFail: Bool = false) {
        arms = ledsPerArm
        self.connectShouldFail = connectShouldFail
        self.displayShouldFail = displayShouldFail
    }

    var ledsPerArm: Int { arms }

    func connect() async throws {
        connectCount += 1
        if connectShouldFail { throw FanTransportError.deviceNotFound }
    }

    func display(_ frame: POVFrame) async throws {
        if displayShouldFail { throw FanTransportError.writeFailed(code: -536870201) }
        displayedFrames.append(frame)
    }

    func disconnect() async { disconnectCount += 1 }
}

/// One recording transport per kind, so switching can be observed.
struct RecordingTransportProvider: FanTransportProviding {
    let simulated = RecordingTransport()
    let hardware = RecordingTransport(ledsPerArm: 7)

    func makeTransport(for kind: FanTransportKind) -> any FanDisplayTransport {
        switch kind {
        case .simulated: simulated
        case .hardware: hardware
        }
    }
}

@MainActor
struct FanMessageViewModelTests {
    @Test func editingTheMessageRefreshesThePreview() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        let before = viewModel.previewFrame

        viewModel.message = "DIFFERENT"

        #expect(viewModel.previewFrame != before)
        #expect(viewModel.previewFrame == ColumnRasterizer().frame(for: "DIFFERENT", ledsPerArm: 11))
    }

    @Test func clearingTheMessageProducesAnEmptyPreview() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        viewModel.message = ""
        #expect(viewModel.previewFrame.isEmpty)
    }

    @Test func sendingIsBlockedUntilConnected() async {
        let transport = RecordingTransport()
        let viewModel = FanMessageViewModel(transport: transport)

        await viewModel.sendMessage()

        #expect(await transport.displayedFrames.isEmpty)
        #expect(!viewModel.status.allowsSending)
    }

    @Test func connectingThenSendingDeliversTheFrame() async {
        let transport = RecordingTransport()
        let viewModel = FanMessageViewModel(transport: transport)

        await viewModel.connect()
        await viewModel.sendMessage()

        #expect(viewModel.status == .connected)
        #expect(await transport.displayedFrames == [viewModel.previewFrame])
    }

    @Test func connectingAdoptsTheTransportArmLength() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(ledsPerArm: 7))

        await viewModel.connect()

        #expect(viewModel.previewFrame.ledsPerArm == 7)
    }

    @Test func aFailedConnectionSurfacesTheReason() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(connectShouldFail: true))

        await viewModel.connect()

        #expect(viewModel.status != .connected)
        #expect(!viewModel.status.allowsSending)
        #expect(viewModel.status.summary == FanTransportError.deviceNotFound.localizedDescription)
    }

    @Test func aFailedSendSurfacesTheReasonAndStaysConnected() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport(displayShouldFail: true))

        await viewModel.connect()
        await viewModel.sendMessage()

        #expect(viewModel.status == .connected)
        #expect(viewModel.lastError == FanTransportError.writeFailed(code: -536870201).localizedDescription)
    }

    @Test func disconnectingReturnsToDisconnected() async {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())

        await viewModel.connect()
        await viewModel.disconnect()

        #expect(viewModel.status == .disconnected)
        #expect(!viewModel.status.allowsSending)
    }

    @Test func transportNameIsExposedForTheUI() {
        let viewModel = FanMessageViewModel(transport: RecordingTransport())
        #expect(viewModel.transportName == "Recording")
    }

    // MARK: - Transport selection

    @Test func theSimulatedTransportIsTheDefault() {
        let viewModel = FanMessageViewModel(transportProvider: RecordingTransportProvider())
        #expect(viewModel.transportKind == .simulated)
        #expect(viewModel.sendCaveat == nil)
    }

    @Test func switchingKindDisconnectsThePreviousTransportAndResetsState() async {
        let provider = RecordingTransportProvider()
        let viewModel = FanMessageViewModel(transportProvider: provider, transportKind: .hardware)
        await viewModel.connect()
        #expect(viewModel.previewFrame.ledsPerArm == 7)

        viewModel.transportKind = .simulated

        #expect(viewModel.status == .disconnected)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.previewFrame.ledsPerArm == 11, "arm length returns to the default until the new transport connects")
        await waitUntil { await provider.hardware.disconnectCount == 1 }
        #expect(await provider.hardware.disconnectCount == 1)
        #expect(await provider.simulated.connectCount == 0)
    }

    @Test func connectingAfterSwitchingUsesTheNewTransport() async {
        let provider = RecordingTransportProvider()
        let viewModel = FanMessageViewModel(transportProvider: provider)

        viewModel.transportKind = .hardware
        await viewModel.connect()
        viewModel.message = "A"
        await viewModel.sendMessage()

        #expect(viewModel.previewFrame.ledsPerArm == 7)
        #expect(await provider.hardware.displayedFrames.count == 1)
        #expect(await provider.simulated.displayedFrames.isEmpty)
    }

    @Test func selectingTheSameKindAgainKeepsTheConnection() async {
        let provider = RecordingTransportProvider()
        let viewModel = FanMessageViewModel(transportProvider: provider)
        await viewModel.connect()

        viewModel.transportKind = .simulated

        #expect(viewModel.status == .connected)
        #expect(await provider.simulated.disconnectCount == 0)
    }

    @Test func hardwareSelectionCarriesTheProtocolCaveat() {
        let viewModel = FanMessageViewModel(transportProvider: RecordingTransportProvider())
        viewModel.transportKind = .hardware
        #expect(viewModel.sendCaveat?.isEmpty == false)
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
