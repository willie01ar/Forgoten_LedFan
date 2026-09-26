import Foundation

/// The transports a user can choose between. The USB fan comes first and is the default (D23).
nonisolated enum FanTransportKind: String, CaseIterable, Identifiable, Sendable {
    case hardware
    case simulated

    var id: Self { self }

    var title: String {
        switch self {
        case .simulated: "Simulated fan"
        case .hardware: "USB fan"
        }
    }
}

/// Builds a transport for a kind. The ViewModel depends on this, never on a concrete transport.
nonisolated protocol FanTransportProviding: Sendable {
    func makeTransport(for kind: FanTransportKind) -> any FanDisplayTransport
}

/// Hands back the same transport whatever the kind. For tests and previews.
nonisolated struct FixedTransportProvider: FanTransportProviding {
    let transport: any FanDisplayTransport

    func makeTransport(for kind: FanTransportKind) -> any FanDisplayTransport { transport }
}
