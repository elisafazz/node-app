import Foundation

struct Meeting: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let organizerUserId: UUID
    let title: String
    let durationMinutes: Int
    let status: MeetingStatus
    let confirmedSlotId: UUID?
    let createdAt: Date

    enum MeetingStatus: String, Codable, Sendable {
        case polling, confirmed, cancelled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case organizerUserId = "organizer_user_id"
        case title
        case durationMinutes = "duration_minutes"
        case status
        case confirmedSlotId = "confirmed_slot_id"
        case createdAt = "created_at"
    }
}

struct MeetingSlot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let meetingId: UUID
    let startAt: Date
    let endAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case meetingId = "meeting_id"
        case startAt = "start_at"
        case endAt = "end_at"
    }
}

struct MeetingResponse: Codable, Hashable, Sendable {
    let meetingId: UUID
    let slotId: UUID
    let userId: UUID
    let available: Bool
    let respondedAt: Date

    enum CodingKeys: String, CodingKey {
        case meetingId = "meeting_id"
        case slotId = "slot_id"
        case userId = "user_id"
        case available
        case respondedAt = "responded_at"
    }
}
