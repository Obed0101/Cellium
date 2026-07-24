import Foundation
import Network

@MainActor
final class WiFiNetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cellium.wifi-monitor")
    private(set) var isWiFiAvailable = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied && path.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in
                self?.isWiFiAvailable = available
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
