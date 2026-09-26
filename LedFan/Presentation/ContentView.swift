import SwiftUI

struct ContentView: View {
    @State private var viewModel: FanMessageViewModel
    @FocusState private var focusedField: Int?

    init(viewModel: FanMessageViewModel = FanMessageViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Layout.loose) {
                controlsColumn
                preview
            }
            VStack(spacing: Layout.loose) {
                preview
                controlsColumn
            }
        }
        .padding(Layout.loose)
        .frame(minWidth: Layout.minimumWindowWidth, idealWidth: Layout.idealWindowWidth)
        .task { await viewModel.restore() }
        .onChange(of: focusedField) { _, field in viewModel.focusedField = field }
        .animation(.default, value: viewModel.lastError)
        .animation(.default, value: viewModel.lastSuccess)
        .animation(.default, value: viewModel.status)
        .animation(.default, value: viewModel.transportKind)
    }

    // MARK: - Columns

    private var preview: some View {
        ScrollingPreview(viewModel: viewModel)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var controlsColumn: some View {
        VStack(alignment: .leading, spacing: Layout.standard) {
            controls
                .padding(Layout.standard)
                .background(.regularMaterial, in: .rect(cornerRadius: Layout.cornerRadius))

            if let lastError = viewModel.lastError {
                ErrorBanner(message: lastError)
            }
        }
        // The ideal width equals the minimum so ViewThatFits keeps two columns at any window
        // width above the minimum; the column then grows into whatever space there is.
        .frame(minWidth: Layout.controlsMinimumWidth, idealWidth: Layout.controlsMinimumWidth, maxWidth: .infinity)
    }

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

            VStack(spacing: Layout.tight) {
                ForEach(FanMessageViewModel.fields, id: \.self) { index in
                    messageField(index)
                }
            }

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

            if let lastSuccess = viewModel.lastSuccess {
                Label(lastSuccess, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func messageField(_ index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Layout.tight) {
            TextField("Message \(index + 1)", text: Binding(
                get: { viewModel.text(forField: index) },
                set: { viewModel.setText($0, forField: index) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.body)
            .focused($focusedField, equals: index)
            .accessibilityLabel("Message \(index + 1)")

            Text(viewModel.counterText(forField: index))
                .font(.callout.monospacedDigit())
                .frame(width: Layout.counterWidth, alignment: .trailing)
                .foregroundStyle(viewModel.fieldFitsTheFan(index) ? Palette.counterWithinLimit : Palette.counterOverLimit)
                .accessibilityLabel("Message \(index + 1): \(viewModel.characterCount(forField: index)) of \(FanMessage.maximumCharacters) characters")
        }
    }

    @ViewBuilder
    private var captions: some View {
        if let problem = viewModel.lengthProblem {
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
            Caption(text: caveat, systemImage: "cable.connector", tint: .secondary, prefix: "Note")
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

            Button("Send") {
                Task { await viewModel.sendMessage() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send the filled messages to the fan")
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
            .fixedSize(horizontal: false, vertical: true)
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
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Error: \(message)")
    }
}

#Preview {
    ContentView(viewModel: FanMessageViewModel(messageStore: TransientMessageStore(), transportKind: .simulated))
}
