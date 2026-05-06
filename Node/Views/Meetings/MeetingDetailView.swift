import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    @State private var slots: [MeetingSlot] = []
    @State private var responses: [MeetingResponse] = []
    @State private var myResponses: [UUID: Bool] = [UUID: Bool]()
    @State private var pendingChanges: [UUID: Bool] = [UUID: Bool]()
    @State private var weekStart: Date = Date().startOfWeek
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isConfirming = false
    @State private var confirmSlot: MeetingSlot? = nil
    @State private var errorMessage: String?

    private var me: UUID? { auth.session?.user.id }
    private var isOrganizer: Bool { meeting.organizerUserId == me }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nodeBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    if meeting.status == .confirmed {
                        confirmedBanner
                    } else if meeting.status == .cancelled {
                        cancelledBanner
                    }

                    switch meeting.status {
                    case .polling:
                        pollingContent
                    case .confirmed:
                        confirmedContent
                    case .cancelled:
                        cancelledContent
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                    }
                }

                if isLoading {
                    ProgressView()
                }
            }
            .navigationTitle(meeting.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if meeting.status == .polling && !pendingChanges.isEmpty {
                        Button("Save") { Task { await saveResponses() } }
                            .fontWeight(.semibold)
                            .tint(Color.nodeBrand)
                            .disabled(isSaving)
                    }
                }
            }
            .task {
                await load()
                weekStart = slots.first?.startAt.startOfWeek ?? Date().startOfWeek
            }
            .alert("Confirm this time?", isPresented: .init(
                get: { confirmSlot != nil },
                set: { if !$0 { confirmSlot = nil } }
            )) {
                Button("Confirm") { Task { await confirmSelected() } }
                Button("Cancel", role: .cancel) { confirmSlot = nil }
            } message: {
                if let s = confirmSlot {
                    Text(slotLabel(s))
                }
            }
        }
    }

    // MARK: - Banners

    private var confirmedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let slotId = meeting.confirmedSlotId,
               let slot = slots.first(where: { $0.id == slotId }) {
                Text("Confirmed: \(slotLabel(slot))")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
    }

    private var cancelledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            Text("This poll was cancelled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nodeSurface)
    }

    // MARK: - Polling content

    private var pollingContent: some View {
        VStack(spacing: 0) {
            weekNavHeader
            Divider()

            let proposedStarts = Set(slots.map(\.startAt))
            let counts = responseCounts()
            let respondentCount = Set(responses.map(\.userId)).count

            WeekCalendarGrid(
                weekStart: weekStart,
                durationMinutes: meeting.durationMinutes,
                proposedSlotStarts: proposedStarts,
                responseCounts: counts,
                totalRespondents: respondentCount,
                selectedStarts: responseBinding()
            )

            if isOrganizer && !slots.isEmpty {
                Divider()
                organizerActions
            }
        }
    }

    private var weekNavHeader: some View {
        HStack {
            Button {
                weekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            Spacer()
            Text(weekRangeLabel)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                weekStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .foregroundStyle(Color.nodeText)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var organizerActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(topSlots()) { slot in
                    Button {
                        confirmSlot = slot
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Confirm")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            Text(slotLabel(slot))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            let count = responseCounts()[slot.startAt] ?? 0
                            let total = Set(responses.map(\.userId)).count
                            Text("\(count) of \(total) available")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.nodeBrand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isConfirming)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Confirmed / cancelled content

    private var confirmedContent: some View {
        VStack(spacing: 24) {
            Spacer()
            if let slotId = meeting.confirmedSlotId,
               let slot = slots.first(where: { $0.id == slotId }) {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.nodeBrand)
                    Text(slotLabel(slot))
                        .font(.title3.weight(.semibold))
                    Text("Duration: \(durationLabel(meeting.durationMinutes))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
    }

    private var cancelledContent: some View {
        VStack {
            Spacer()
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        errorMessage = nil
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await MeetingService.shared.fetchSlots(meetingId: meeting.id) }
            group.addTask { await MeetingService.shared.fetchResponses(meetingId: meeting.id) }
        }
        slots = MeetingService.shared.slotsByMeetingId[meeting.id] ?? []
        responses = MeetingService.shared.responsesByMeetingId[meeting.id] ?? []
        errorMessage = MeetingService.shared.lastError
        if let me {
            myResponses = Dictionary(uniqueKeysWithValues:
                responses
                    .filter { $0.userId == me }
                    .map { ($0.slotId, $0.available) }
            )
        }
        isLoading = false
    }

    private func saveResponses() async {
        guard !pendingChanges.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let merged = myResponses.merging(pendingChanges) { _, new in new }
            try await MeetingService.shared.respondToSlots(meetingId: meeting.id, responses: merged)
            myResponses = merged
            pendingChanges.removeAll()
            responses = MeetingService.shared.responsesByMeetingId[meeting.id] ?? []
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func confirmSelected() async {
        guard let slot = confirmSlot else { return }
        isConfirming = true
        defer { isConfirming = false }
        do {
            try await MeetingService.shared.confirmSlot(meetingId: meeting.id, slotId: slot.id)
            confirmSlot = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    // MARK: - Helpers

    private func responseBinding() -> Binding<Set<Date>> {
        Binding(
            get: {
                let currentYes = Set(myResponses.filter(\.value).keys.compactMap { slotId in
                    slots.first(where: { $0.id == slotId })?.startAt
                })
                let pendingYes = Set(pendingChanges.filter(\.value).keys.compactMap { slotId in
                    slots.first(where: { $0.id == slotId })?.startAt
                })
                let pendingNo = Set(pendingChanges.filter { !$0.value }.keys.compactMap { slotId in
                    slots.first(where: { $0.id == slotId })?.startAt
                })
                return currentYes.union(pendingYes).subtracting(pendingNo)
            },
            set: { newSelected in
                for slot in slots {
                    let wasSelected = (myResponses[slot.id] == true && pendingChanges[slot.id] != false) ||
                                      (pendingChanges[slot.id] == true)
                    let isNowSelected = newSelected.contains(slot.startAt)
                    if wasSelected != isNowSelected {
                        pendingChanges[slot.id] = isNowSelected
                    }
                }
            }
        )
    }

    private func responseCounts() -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for response in responses where response.available {
            if let slot = slots.first(where: { $0.id == response.slotId }) {
                counts[slot.startAt, default: 0] += 1
            }
        }
        return counts
    }

    private func topSlots() -> [MeetingSlot] {
        let counts = responseCounts()
        return slots
            .sorted {
                let lhsCount = counts[$0.startAt] ?? 0
                let rhsCount = counts[$1.startAt] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return $0.startAt < $1.startAt  // tie-break: earlier slot first
            }
            .prefix(5)
            .map { $0 }
    }

    private var weekRangeLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func slotLabel(_ slot: MeetingSlot) -> String {
        let day = slot.startAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        let time = slot.startAt.formatted(.dateTime.hour().minute())
        return "\(day) at \(time)"
    }

    private func durationLabel(_ mins: Int) -> String {
        let h = mins / 60, m = mins % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}
