import Foundation

enum FanConnectionStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var summary: String {
        switch self {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .failed(let reason): return reason
        }
    }

    var allowsSending: Bool { self == .connected }
    var isConnected: Bool { self == .connected }
    var isBusy: Bool { self == .connecting }
}
