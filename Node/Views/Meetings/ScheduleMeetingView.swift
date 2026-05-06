import SwiftUI

/// 2-step wizard: (1) title + duration + nodes, (2) week calendar to pick time blocks.
struct ScheduleMeetingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NodeService.self) private var nodes

    var defaultNodeId: UUID? = nil

    @State private var step = 1
    @State private var title = ""
    @State private var durationMinutes = 60
    @State private var selectedNodeIds: Set<UUID> = []
    @State private var selectedSlots: Set<Date> = []
    @State private var weekStart: Date = Date().startOfWeek
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let durations = [15, 30, 45, 60, 90, 120, 180, 240]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nodeBackground.ignoresSafeArea()
                if step == 1 { detailsStep } else { calendarStep }
            }
            .navigationTitle(step == 1 ? "New Poll" : "Pick Times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 1 ? "Cancel" : "Back") {
                        if step == 1 { dismiss() } else { step = 1 }
                    }
                    .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else if step == 1 {
                        Button("Next") { step = 2 }
                            .fontWeight(.semibold)
                            .tint(Color.nodeBrand)
                            .disabled(!step1Valid)
                    } else {
                        Button("Create") { Task { await create() } }
                            .fontWeight(.semibold)
                            .tint(Color.nodeBrand)
                            .disabled(selectedSlots.isEmpty || isCreating)
                    }
                }
            }
            .task {
                if let defaultNodeId {
                    selectedNodeIds = [defaultNodeId]
                } else {
                    selectedNodeIds = Set(nodes.myNodes.map(\.id))
                }
            }
        }
    }

    private var step1Valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedNodeIds.isEmpty
    }

    // MARK: - Step 1: Details

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                titleSection
                durationSection
                nodeSelectorSection
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(20)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What's the meeting?", systemImage: "text.cursor")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("e.g. Weekend plans, Dinner out...", text: $title)
                .padding(12)
                .background(Color.nodeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: title) { _, new in
                    if new.count > 100 { title = String(new.prefix(100)) }
                }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Duration", systemImage: "clock")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(durations, id: \.self) { mins in
                        Button {
                            durationMinutes = mins
                        } label: {
                            Text(durationLabel(mins))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(durationMinutes == mins ? .white : Color.nodeText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    durationMinutes == mins ? Color.nodeBrand : Color.nodeSurface,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.12), value: durationMinutes)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var nodeSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Invite members from", systemImage: "circle.hexagongrid")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(nodes.myNodes) { node in
                let isSelected = selectedNodeIds.contains(node.id)
                let m = nodes.myMembershipsByNodeId[node.id]
                let accent = Color.forMembership(hex: m?.perNodeAccentColor, fallbackSeed: node.id.uuidString)
                Button {
                    if isSelected && selectedNodeIds.count == 1 { return }
                    if isSelected { selectedNodeIds.remove(node.id) }
                    else { selectedNodeIds.insert(node.id) }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(accent).frame(width: 38, height: 38)
                            Text(m?.perNodeEmoji ?? String(node.name.prefix(1)))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Text(node.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.nodeText)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(isSelected ? Color.nodeBrand : Color.nodeText.opacity(0.3))
                    }
                    .padding(14)
                    .background(Color.nodeSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.12), value: isSelected)
            }
        }
    }

    // MARK: - Step 2: Calendar

    private var calendarStep: some View {
        VStack(spacing: 0) {
            weekNavHeader
            Divider()
            WeekCalendarGrid(
                weekStart: weekStart,
                durationMinutes: durationMinutes,
                proposedSlotStarts: nil,
                responseCounts: nil,
                totalRespondents: 0,
                selectedStarts: $selectedSlots
            )
            selectionFooter
        }
    }

    private var weekNavHeader: some View {
        HStack {
            Button {
                if let prev = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart),
                   prev >= Date().startOfWeek {
                    weekStart = prev
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(weekStart <= Date().startOfWeek ? Color.nodeText.opacity(0.3) : Color.nodeText)
            }
            .disabled(weekStart <= Date().startOfWeek)

            Spacer()

            Text(weekRangeLabel)
                .font(.subheadline.weight(.semibold))

            Spacer()

            let maxWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: Date().startOfWeek) ?? weekStart
            Button {
                if let next = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStart),
                   next <= maxWeekStart {
                    weekStart = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(weekStart >= maxWeekStart ? Color.nodeText.opacity(0.3) : Color.nodeText)
            }
            .disabled(weekStart >= maxWeekStart)
        }
        .foregroundStyle(Color.nodeText)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selectionFooter: some View {
        VStack(spacing: 4) {
            Divider()
            HStack {
                if selectedSlots.isEmpty {
                    Text("Tap cells to mark times you want to propose")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(selectedSlots.count) time\(selectedSlots.count == 1 ? "" : "s") selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.nodeBrand)
                    Spacer()
                    Button("Clear") { selectedSlots.removeAll() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Create

    private func create() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let cal = Calendar.current
            let slotPairs: [(start: Date, end: Date)] = selectedSlots.sorted().compactMap { start in
                guard let end = cal.date(byAdding: .minute, value: durationMinutes, to: start) else { return nil }
                return (start, end)
            }
            _ = try await MeetingService.shared.createMeeting(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                durationMinutes: durationMinutes,
                nodeIds: Array(selectedNodeIds),
                slots: slotPairs
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    // MARK: - Helpers

    private var weekRangeLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let startStr = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let endStr = end.formatted(.dateTime.month(.abbreviated).day())
        return "\(startStr) - \(endStr)"
    }

    private func durationLabel(_ mins: Int) -> String {
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Date extension

extension Date {
    var startOfWeek: Date {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: comps) ?? self
    }
}
