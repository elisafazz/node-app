import SwiftUI

/// Doodle-style week grid. Tapping a cell selects it as a proposed slot start.
/// Each selected cell represents a slot from that hour to that hour + durationMinutes.
struct WeekCalendarGrid: View {
    let weekStart: Date          // Monday of the week to display
    let durationMinutes: Int
    let proposedSlotStarts: Set<Date>?  // nil = selection mode; non-nil = response mode (only these are tappable)
    let responseCounts: [Date: Int]?    // slot start -> yes-response count (response mode)
    let totalRespondents: Int           // for showing X/total badge
    @Binding var selectedStarts: Set<Date>

    private let hourRange = 6...23      // 6am slot through 11pm slot start (covers early/late cross-timezone needs)
    private let timeGutterWidth: CGFloat = 38
    private let cellHeight: CGFloat = 44

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(hourRange), id: \.self) { hour in
                        hourRow(hour: hour)
                    }
                } header: {
                    dayHeaderRow
                        .background(Color.nodeBackground)
                }
            }
        }
    }

    // MARK: - Header

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: timeGutterWidth)
            ForEach(0..<7, id: \.self) { offset in
                dayHeader(calendar.date(byAdding: .day, value: offset, to: weekStart)!)
            }
        }
        .padding(.bottom, 6)
    }

    private func dayHeader(_ date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        return VStack(spacing: 3) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Color.nodeBrand : .secondary)
            Text(date.formatted(.dateTime.day()))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isToday ? Color.nodeBrand : Color.nodeText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Hour row

    private func hourRow(hour: Int) -> some View {
        HStack(spacing: 0) {
            Text(hourLabel(hour))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: timeGutterWidth, alignment: .trailing)
                .padding(.trailing, 6)

            ForEach(0..<7, id: \.self) { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
                let slotStart = slotDate(date: date, hour: hour)
                cell(slotStart: slotStart)
            }
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(slotStart: Date) -> some View {
        if let proposedSlotStarts {
            // Response mode: only proposed slots are interactive
            let isProposed = proposedSlotStarts.contains(slotStart)
            if isProposed {
                responseCell(slotStart: slotStart)
            } else {
                emptyCell(dimmed: true)
            }
        } else {
            // Selection mode: any future slot is tappable
            selectionCell(slotStart: slotStart)
        }
    }

    private func selectionCell(slotStart: Date) -> some View {
        let isSelected = selectedStarts.contains(slotStart)
        let isPast = slotStart <= Date()
        return Button {
            guard !isPast else { return }
            if isSelected { selectedStarts.remove(slotStart) }
            else { selectedStarts.insert(slotStart) }
        } label: {
            cellRect(
                fill: isSelected ? Color.nodeBrand : Color.nodeSurface,
                opacity: isPast ? 0.35 : 1.0
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }

    private func responseCell(slotStart: Date) -> some View {
        let isSelected = selectedStarts.contains(slotStart)
        let count = responseCounts?[slotStart] ?? 0
        let showBadge = count > 0 || isSelected
        return Button {
            if isSelected { selectedStarts.remove(slotStart) }
            else { selectedStarts.insert(slotStart) }
        } label: {
            ZStack(alignment: .topTrailing) {
                cellRect(
                    fill: isSelected ? Color.nodeBrand : Color.nodeSurface,
                    opacity: 1.0
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.nodeBrand, lineWidth: isSelected ? 0 : 1.5)
                )
                if showBadge {
                    Text(totalRespondents > 0 ? "\(count)/\(totalRespondents)" : "\(count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Color.nodeBrand)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isSelected ? Color.white.opacity(0.25) : Color.nodeBrand.opacity(0.12))
                        )
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }

    private func emptyCell(dimmed: Bool) -> some View {
        cellRect(fill: Color.nodeSurface, opacity: dimmed ? 0.3 : 1.0)
    }

    private func cellRect(fill: Color, opacity: Double) -> some View {
        Rectangle()
            .fill(fill)
            .frame(height: cellHeight)
            .overlay(Rectangle().stroke(Color.nodeBorder.opacity(0.3), lineWidth: 0.5))
            .opacity(opacity)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func slotDate(date: Date, hour: Int) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps) ?? date
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return hour < 12 ? "\(h)a" : "\(h)p"
    }

    private var calendar: Calendar { .current }
}
