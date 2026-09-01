import Foundation
import Network

final class NetworkMonitor {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private(set) var isConnected = false

    var onConnectionChange: ((Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied

            DispatchQueue.main.async {
                guard let self else { return }

                let previousValue = self.isConnected
                self.isConnected = connected

                if previousValue != connected {
                    self.onConnectionChange?(connected)
                }
            }
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
