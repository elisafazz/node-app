import Foundation
import Network

/// Singleton NWPathMonitor wrapper. Used to gate cellular-expensive prefetches
/// (mirrors NetworkMonitor pattern from Sunzzari Session 57 / Miracles Session 9).
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isExpensive = false
    private(set) var isConstrained = false
    private(set) var isCellular = false
    private(set) var isUnconstrained = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.elisafazzari.node.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.update(path: path)
            }
        }
        monitor.start(queue: queue)
    }

    private func update(path: NWPath) {
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        isCellular = path.usesInterfaceType(.cellular)
        isUnconstrained = path.status == .satisfied && !isExpensive && !isConstrained
    }
}
