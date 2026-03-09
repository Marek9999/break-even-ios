import Network
import Observation

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
        monitor.start(queue: DispatchQueue(label: "com.breakeven.NetworkMonitor"))
    }
}
