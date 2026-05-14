import SwiftUI

/// Per-node year-end recap. Plays through the year's stories from one node as
/// a single montage. Auto-presented from StoriesView on Dec 31; accessible any
/// time from the node's archive year picker.
///
/// Per-node scope (vs Sunzzari's two-person aggregate): Node groups have their
/// own social context, so a "2026 with this group" reel reads better than one
/// recap mixing every node a user belongs to.
///
/// IG-parity gestures: tap right to advance, tap left to rewind, hold to pause,
/// drag down to dismiss.
struct YearRecapView: View {
    let year: Int
    let stories: [Story]
    let authorsByUserId: [UUID: NodeMember]

    @State private var currentIndex: Int = 0
    @State private var progress: Double = 0
    @State private var isPaused: Bool = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    private let storyDuration: TimeInterval = 3.5
    private let tickInterval: TimeInterval = 0.05

    private var sortedStories: [Story] {
        // Recap reads forward through the year (Jan -> Dec), opposite of the
        // live feed's newest-first sort.
        stories.sorted { $0.createdAt < $1.createdAt }
    }

    private var currentStory: Story? {
        sortedStories.indices.contains(currentIndex) ? sortedStories[currentIndex] : nil
    }

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if sortedStories.isEmpty {
                Text("No stories to recap for \(String(year))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            } else if let currentStory {
                AsyncImage(url: currentStory.fullURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.black
                    }
                }
                .ignoresSafeArea()

                // Tap zones below the progress bars at the top so the bars
                // themselves remain non-tappable.
                VStack(spacing: 0) {
                    Color.clear.frame(height: 60)
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { goBack() }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { advance() }
                    }
                }

                VStack {
                    HStack(spacing: 4) {
                        ForEach(sortedStories.indices, id: \.self) { i in
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.25))
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * fillFraction(for: i))
                                }
                            }
                            .frame(height: 2)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Spacer()

                    VStack(spacing: 4) {
                        if let author = authorsByUserId[currentStory.authorUserId] {
                            Text(author.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        Text(Self.monthDay.string(from: currentStory.createdAt))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        if let caption = currentStory.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.body)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 50) {
            // perform: required closure, intentionally empty
        } onPressingChanged: { pressing in
            isPaused = pressing
        }
        .navigationTitle("\(String(year)) Recap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(.white)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.black.opacity(0.3), for: .navigationBar)
        .task(id: currentIndex) {
            await runProgressLoop()
        }
    }

    private func fillFraction(for i: Int) -> Double {
        if i < currentIndex { return 1.0 }
        if i == currentIndex { return progress }
        return 0
    }

    /// Wall-clock anchored progress with pause-time accumulator (matches the
    /// live player's clock so behavior under load is consistent).
    private func runProgressLoop() async {
        progress = 0
        let startDate = Date()
        var pausedAt: Date? = nil
        var totalPaused: TimeInterval = 0
        while progress < 1.0 {
            try? await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
            if Task.isCancelled { return }
            if isPaused {
                if pausedAt == nil { pausedAt = Date() }
                continue
            } else if let p = pausedAt {
                totalPaused += Date().timeIntervalSince(p)
                pausedAt = nil
            }
            let elapsed = Date().timeIntervalSince(startDate) - totalPaused
            progress = min(1.0, elapsed / storyDuration)
        }
        if !Task.isCancelled {
            advance()
        }
    }

    private func advance() {
        progress = 0
        if currentIndex + 1 < sortedStories.count {
            currentIndex += 1
        } else {
            dismiss()
        }
    }

    private func goBack() {
        if currentIndex == 0 {
            progress = 0
        } else {
            progress = 0
            currentIndex -= 1
        }
    }
}
