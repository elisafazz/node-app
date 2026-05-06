import SwiftUI

struct MeetingsListView: View {
    @Environment(AuthService.self) private var auth

    @State private var meetings: [Meeting] = []
    @State private var showCreate = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var me: UUID? { auth.session?.user.id }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nodeBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.nodeBrand)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                ScheduleMeetingView()
                    .onDisappear { Task { await load() } }
            }
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(meeting: meeting)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && meetings.isEmpty {
            ProgressView()
        } else if let errorMessage, meetings.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Retry") { Task { await load() } }
                    .tint(Color.nodeBrand)
            }
        } else if meetings.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    let polling = meetings.filter { $0.status == .polling }
                    let confirmed = meetings.filter { $0.status == .confirmed }
                    let cancelled = meetings.filter { $0.status == .cancelled }

                    if !polling.isEmpty {
                        sectionHeader("Open Polls")
                        ForEach(polling) { meetingRow($0) }
                    }
                    if !confirmed.isEmpty {
                        sectionHeader("Confirmed")
                        ForEach(confirmed) { meetingRow($0) }
                    }
                    if !cancelled.isEmpty {
                        sectionHeader("Cancelled")
                        ForEach(cancelled) { meetingRow($0) }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func meetingRow(_ meeting: Meeting) -> some View {
        NavigationLink(value: meeting) {
            HStack(spacing: 14) {
                statusIcon(meeting.status)
                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.nodeText)
                    Text(subtitleText(meeting))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider().padding(.leading, 62)
    }

    private func statusIcon(_ status: Meeting.MeetingStatus) -> some View {
        ZStack {
            Circle()
                .fill(iconBackground(status))
                .frame(width: 40, height: 40)
            Image(systemName: iconName(status))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconForeground(status))
        }
    }

    private func iconName(_ status: Meeting.MeetingStatus) -> String {
        switch status {
        case .polling: return "calendar.badge.clock"
        case .confirmed: return "calendar.badge.checkmark"
        case .cancelled: return "calendar.badge.minus"
        }
    }

    private func iconBackground(_ status: Meeting.MeetingStatus) -> Color {
        switch status {
        case .polling: return Color.nodeBrand.opacity(0.12)
        case .confirmed: return Color.green.opacity(0.12)
        case .cancelled: return Color.nodeSurface
        }
    }

    private func iconForeground(_ status: Meeting.MeetingStatus) -> Color {
        switch status {
        case .polling: return Color.nodeBrand
        case .confirmed: return .green
        case .cancelled: return .secondary
        }
    }

    private func subtitleText(_ meeting: Meeting) -> String {
        let isOrganizer = meeting.organizerUserId == me
        let durationStr = durationLabel(meeting.durationMinutes)
        let createdStr = meeting.createdAt.formatted(.dateTime.month(.abbreviated).day())
        switch meeting.status {
        case .polling:
            return "\(durationStr) - \(isOrganizer ? "You created" : "Poll open") - \(createdStr)"
        case .confirmed:
            return "\(durationStr) - Confirmed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.nodeBrand.opacity(0.4))
            Text("No meetings yet")
                .font(.title3.weight(.semibold))
            Text("Create a poll to find a time that works for everyone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showCreate = true
            } label: {
                Text("New Poll")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.nodeBrand, in: Capsule())
            }
            .padding(.top, 4)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        await MeetingService.shared.fetchMyMeetings()
        meetings = MeetingService.shared.myMeetings
        errorMessage = MeetingService.shared.lastError
        isLoading = false
    }

    private func durationLabel(_ mins: Int) -> String {
        let h = mins / 60, m = mins % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h)h \(m)m"
    }
}
