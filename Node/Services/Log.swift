import Foundation
import os

/// Lightweight structured logger.
/// All log calls funnel through `os.Logger` so output is filterable in Console.app and visible in Xcode.
/// In production (TestFlight + App Store), `.debug` lines are stripped at runtime by the OS.
@MainActor
final class Log {
    static let shared = Log()

    private let auth = Logger(subsystem: "com.elisafazzari.node", category: "auth")
    private let push = Logger(subsystem: "com.elisafazzari.node", category: "push")
    private let net = Logger(subsystem: "com.elisafazzari.node", category: "net")
    private let app = Logger(subsystem: "com.elisafazzari.node", category: "app")

    func auth(_ event: String, _ detail: String? = nil) {
        log(auth, level: .info, event: event, detail: detail)
    }

    func push(_ event: String, _ detail: String? = nil) {
        log(push, level: .info, event: event, detail: detail)
    }

    func net(_ event: String, _ detail: String? = nil) {
        log(net, level: .info, event: event, detail: detail)
    }

    func app(_ event: String, _ detail: String? = nil) {
        log(app, level: .info, event: event, detail: detail)
    }

    func error(_ event: String, error: Error) {
        let nsError = error as NSError
        // Privacy: redact the error description in shipped logs (could contain user identifiers).
        // Keep domain + code visible for debugging.
        let logger = self.app
        logger.error("\(event, privacy: .public) [\(nsError.domain, privacy: .public):\(nsError.code, privacy: .public)] \(nsError.localizedDescription, privacy: .private)")
    }

    private func log(_ logger: Logger, level: OSLogType, event: String, detail: String?) {
        if let detail {
            logger.log(level: level, "\(event, privacy: .public): \(detail, privacy: .private)")
        } else {
            logger.log(level: level, "\(event, privacy: .public)")
        }
    }
}
