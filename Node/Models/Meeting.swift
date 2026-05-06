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
}

struct MeetingSlot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let meetingId: UUID
    let startAt: Date
    let endAt: Date
}

struct MeetingResponse: Codable, Hashable, Sendable {
    let meetingId: UUID
    let slotId: UUID
    let userId: UUID
    let available: Bool
    let respondedAt: Date
}
