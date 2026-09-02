import Foundation

/// Production wiring: one simulated fan, one USB fan.
nonisolated struct DefaultFanTransportProvider: FanTransportProviding {
    func makeTransport(for kind: FanTransportKind) -> any FanDisplayTransport {
        switch kind {
        case .simulated: SimulatedFanTransport()
        case .hardware: HIDFanTransport()
        }
    }
}
