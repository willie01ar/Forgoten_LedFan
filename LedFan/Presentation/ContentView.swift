import SwiftUI

struct ContentView: View {
    @State private var viewModel: FanMessageViewModel

    init(viewModel: FanMessageViewModel = FanMessageViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: Layout.loose) {
            ScrollingPreview(viewModel: viewModel)

            controls
                .padding(Layout.standard)
                .background(.regularMaterial, in: .rect(cornerRadius: Layout.cornerRadius))

            if let lastError = viewModel.lastError {
                ErrorBanner(message: lastError)
            }
        }
        .padding(Layout.loose)
        .frame(minWidth: Layout.minimumWindowWidth)
        .task { await viewModel.restore() }
        .animation(.default, value: viewModel.lastError)
        .animation(.default, value: viewModel.status)
        .animation(.default, value: viewModel.transportKind)
        .animation(.default, value: viewModel.selectedSlot)
    }

    // MARK: - Sections

    private var controls: some View {
        VStack(alignment: .leading, spacing: Layout.standard) {
            Picker("Fan", selection: $viewModel.transportKind) {
                ForEach(FanTransportKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(viewModel.status.isBusy)
            .accessibilityLabel("Fan transport")

            LabeledContent("Slot") {
                Picker("Slot", selection: $viewModel.selectedSlot) {
                    ForEach(FanMessage.slots, id: \.self) { slot in
                        Text("\(slot + 1)").tag(slot)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Message slot")
            }
            .font(.callout)

            messageField

            captions

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Layout.standard) {
                    statusLabel
                    Spacer()
                    buttons
                }
                VStack(alignment: .leading, spacing: Layout.standard) {
                    statusLabel
                    buttons
                }
            }

            if let lastStored = viewModel.lastStored {
                Label(lastStored, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var messageField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.tight) {
            TextField("Message", text: $viewModel.message)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .accessibilityLabel("Message to display on the fan")

            Text(viewModel.counterText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(viewModel.messageFitsTheFan ? Palette.counterWithinLimit : Palette.counterOverLimit)
                .accessibilityLabel("\(viewModel.characterCount) of \(FanMessage.maximumCharacters) characters")
        }
    }

    @ViewBuilder
    private var captions: some View {
        if let problem = viewModel.lengthProblem {
            Caption(text: problem, systemImage: "exclamationmark.circle.fill", tint: Palette.error, prefix: "Problem")
        }
        if let problem = viewModel.otherSlotsProblem {
            Caption(text: problem, systemImage: "exclamationmark.circle.fill", tint: Palette.error, prefix: "Problem")
        }
        if let hint = viewModel.blankGlyphHint {
            Caption(text: hint, systemImage: "character.textbox", tint: .secondary, prefix: "Note")
        }
        Caption(text: FanMessageViewModel.sendExplanation, systemImage: "square.stack.3d.up", tint: .secondary, prefix: "Note")
        if let reason = viewModel.storeUnavailableReason {
            Caption(text: reason, systemImage: "info.circle", tint: .secondary, prefix: "Note")
        }
        if let caveat = viewModel.storeCaveat {
            Caption(text: caveat, systemImage: "flask", tint: .secondary, prefix: "Note")
        }
    }

    private var statusLabel: some View {
        ConnectionStatusLabel(status: viewModel.status, transportName: viewModel.transportName)
    }

    private var buttons: some View {
        HStack(spacing: Layout.tight) {
            if viewModel.status.isConnected {
                Button("Disconnect") {
                    Task { await viewModel.disconnect() }
                }
                .accessibilityLabel("Disconnect from the fan")
            } else {
                Button("Connect") {
                    Task { await viewModel.connect() }
                }
                .disabled(viewModel.status.isBusy)
                .accessibilityLabel("Connect to the fan")
            }

            Button("Send all 8") {
                Task { await viewModel.sendMessage() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send all eight slots to the fan")
        }
    }
}

// MARK: - Preview

/// Redraws only while there is something to scroll, the window is active, and the person
/// has not asked for reduced motion. Otherwise the static frame, and no timer at all.
private struct ScrollingPreview: View {
    let viewModel: FanMessageViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let animating = viewModel.scrollingIsPossible && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: Motion.frameInterval, paused: !animating)) { context in
            FanSimulatorView(frame: viewModel.previewFrame(at: animating ? context.date : nil),
                             accessibilityDescription: viewModel.previewDescription,
                             motionDescription: animating ? "scrolling" : "still")
        }
    }
}

// MARK: - Captions

private struct Caption: View {
    let text: String
    let systemImage: String
    let tint: Color
    let prefix: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .accessibilityLabel("\(prefix): \(text)")
    }
}

// MARK: - Connection status

private struct ConnectionStatusLabel: View {
    let status: FanConnectionStatus
    let transportName: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.tight) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: status.isBusy)
            VStack(alignment: .leading) {
                Text(status.summary)
                    .font(.callout)
                Text(transportName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transportName): \(status.summary)")
    }

    private var symbolName: String {
        switch status {
        case .disconnected: "circle"
        case .connecting: "circle.dotted"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .disconnected, .connecting: Palette.statusIdle
        case .connected: Palette.statusConnected
        case .failed: Palette.statusFailed
        }
    }
}

// MARK: - Error banner

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(Palette.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Error: \(message)")
    }
}

#Preview {
    ContentView()
}
