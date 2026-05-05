import Foundation

@MainActor
final class ReportService {
    static let shared = ReportService()

    enum TargetKind: String { case story, photo, thought, user, node }

    func submit(targetKind: TargetKind, targetId: UUID, nodeId: UUID?, reason: String) async throws {
        struct ReportBody: Encodable {
            let target_kind: String
            let target_id: UUID
            let node_id: UUID?
            let reason: String
        }
        struct ReportResult: Decodable { let ok: Bool; let report_id: UUID? }

        let result: ReportResult = try await SupabaseService.shared.functions.invoke(
            "report-intake",
            options: .init(body: ReportBody(
                target_kind: targetKind.rawValue,
                target_id: targetId,
                node_id: nodeId,
                reason: reason
            ))
        )
        if !result.ok {
            throw NSError(domain: "ReportService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Report submission failed"])
        }
    }
}
