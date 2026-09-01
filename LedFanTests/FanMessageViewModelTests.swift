import Foundation
import Testing
@testable import LedFan

/// Records what the ViewModel sends, so the ViewModel can be tested without hardware.
actor RecordingTransport: FanDisplayTransport {
    nonisolated let displayName = "Recording"
    private(set) var displayedFrames: [POVFrame] = []
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
        if connectShouldFail { throw FanTransportError.deviceNotFound }
    }

    func display(_ frame: POVFrame) async throws {
        if displayShouldFail { throw FanTransportError.writeFailed(code: -536870201) }
        displayedFrames.append(frame)
    }

    func disconnect() async {}
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
}
