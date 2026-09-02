import SwiftUI

struct ContentView: View {
    @State private var viewModel = FanMessageViewModel()

    var body: some View {
        VStack(spacing: Layout.loose) {
            FanSimulatorView(frame: viewModel.previewFrame, accessibilityDescription: viewModel.message)

            controls
                .padding(Layout.standard)
                .background(.regularMaterial, in: .rect(cornerRadius: Layout.cornerRadius))

            if let lastError = viewModel.lastError {
                ErrorBanner(message: lastError)
            }
        }
        .padding(Layout.loose)
        .frame(minWidth: Layout.minimumWindowWidth)
        .animation(.default, value: viewModel.previewFrame)
        .animation(.default, value: viewModel.lastError)
        .animation(.default, value: viewModel.status)
        .animation(.default, value: viewModel.transportKind)
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

            TextField("Message", text: $viewModel.message)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .accessibilityLabel("Message to display on the fan")

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

            if let caveat = viewModel.sendCaveat {
                Label(caveat, systemImage: "flask")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Note: \(caveat)")
            }
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
            .disabled(!viewModel.status.allowsSending)
            .accessibilityLabel("Send the message to the fan")
        }
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
