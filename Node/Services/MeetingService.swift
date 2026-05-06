import Foundation

@MainActor
@Observable
final class MeetingService {
    static let shared = MeetingService()

    private(set) var myMeetings: [Meeting] = []
    private(set) var slotsByMeetingId: [UUID: [MeetingSlot]] = [:]
    private(set) var responsesByMeetingId: [UUID: [MeetingResponse]] = [:]
    private(set) var lastError: String?

    func fetchMyMeetings() async {
        do {
            let meetings: [Meeting] = try await SupabaseService.shared.database
                .from("meetings")
                .select("*")
                .order("created_at", ascending: false)
                .execute()
                .value
            myMeetings = meetings
        } catch {
            lastError = UserFacingError.message(for: error)
        }
    }

    func fetchSlots(meetingId: UUID) async {
        do {
            let slots: [MeetingSlot] = try await SupabaseService.shared.database
                .from("meeting_slots")
                .select("*")
                .eq("meeting_id", value: meetingId)
                .order("start_at", ascending: true)
                .execute()
                .value
            slotsByMeetingId[meetingId] = slots
        } catch {
            lastError = UserFacingError.message(for: error)
        }
    }

    func fetchResponses(meetingId: UUID) async {
        do {
            let responses: [MeetingResponse] = try await SupabaseService.shared.database
                .from("meeting_responses")
                .select("*")
                .eq("meeting_id", value: meetingId)
                .execute()
                .value
            responsesByMeetingId[meetingId] = responses
        } catch {
            lastError = UserFacingError.message(for: error)
        }
    }

    func createMeeting(
        title: String,
        durationMinutes: Int,
        nodeIds: [UUID],
        slots: [(start: Date, end: Date)]
    ) async throws -> UUID {
        struct RPCParams: Encodable {
            let p_title: String
            let p_duration_minutes: Int
            let p_node_ids: [UUID]
            let p_slot_starts: [Date]
            let p_slot_ends: [Date]
        }
        let params = RPCParams(
            p_title: title,
            p_duration_minutes: durationMinutes,
            p_node_ids: nodeIds,
            p_slot_starts: slots.map(\.start),
            p_slot_ends: slots.map(\.end)
        )
        let meetingId: UUID = try await SupabaseService.shared.database
            .rpc("create_meeting_with_slots", params: params)
            .single()
            .execute()
            .value
        await fetchMyMeetings()
        return meetingId
    }

    func respondToSlots(meetingId: UUID, responses: [UUID: Bool]) async throws {
        struct ResponseRow: Encodable {
            let meeting_id: UUID
            let slot_id: UUID
            let user_id: UUID
            let available: Bool
        }
        guard let me = AuthService.shared.session?.user.id else {
            throw MeetingError.notAuthenticated
        }
        let rows = responses.map { slotId, available in
            ResponseRow(meeting_id: meetingId, slot_id: slotId, user_id: me, available: available)
        }
        try await SupabaseService.shared.database
            .from("meeting_responses")
            .upsert(rows, onConflict: "meeting_id,slot_id,user_id")
            .execute()
        await fetchResponses(meetingId: meetingId)
    }

    func confirmSlot(meetingId: UUID, slotId: UUID) async throws {
        struct RPCParams: Encodable {
            let p_meeting_id: UUID
            let p_slot_id: UUID
        }
        try await SupabaseService.shared.database
            .rpc("confirm_meeting_slot", params: RPCParams(p_meeting_id: meetingId, p_slot_id: slotId))
            .execute()
        if let idx = myMeetings.firstIndex(where: { $0.id == meetingId }) {
            await fetchMyMeetings()
            _ = idx
        }
    }

    enum MeetingError: Error {
        case notAuthenticated
    }
}
