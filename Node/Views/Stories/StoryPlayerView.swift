import SwiftUI

/// Full-bleed IG-style player. Tap right to advance, tap left to go back, hold to pause.
/// Dismiss is via the X button only -- swipe-down was removed because partial drags left
/// a stuck black bar at the top of the screen.
/// Ported verbatim from Miracles `StoryPlayerView` with one swap: per-author identity comes from a `NodeMember`
/// runtime record (display_name + accent color from membership overrides) instead of a compile-time Person enum.
struct StoryPlayerView: View {
    let stories: [Story]
    let author: NodeMember
    let onDismiss: () -> Void
    var onReelComplete: (() -> Void)? = nil
    var onRequestPrevious: (() -> Void)? = nil
    var isActive: Bool = true

    @Environment(AuthService.self) private var auth
    @State private var currentIndex: Int = 0
    @State private var progress: Double = 0
    @State private var isPaused: Bool = false
    @State private var prefetchedURLs: Set<URL> = []
    @State private var showReport = false
    @State private var showBlockConfirm = false

    private let storyDuration: TimeInterval = 5.0
    private let tickInterval: TimeInterval = 0.05
    private let headerTapInset: CGFloat = 60

    private static let postedAtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTimeLabel(for date: Date) -> String {
        let now = Date()
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0 && elapsed < 3600 {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        let cal = Calendar.current
        let timeStr = Self.postedAtFormatter.string(from: date)
        if cal.isDateInToday(date) { return timeStr }
        if cal.isDateInYesterday(date) { return "Yesterday \(timeStr)" }
        return timeStr
    }

    private var currentStory: Story? {
        guard stories.indices.contains(currentIndex) else { return nil }
        return stories[currentIndex]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let currentStory {
                    AsyncImage(url: currentStory.fullURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.white)
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle").font(.system(size: 32))
                                Text("Couldn't load photo").font(.subheadline)
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()
                }

                if let caption = currentStory?.caption, !caption.isEmpty {
                    VStack {
                        Spacer()
                        Text(caption)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 20)
                            .padding(.bottom, 60)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Tap zones below the header so progress bars / X / author chip don't fall through
                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.safeAreaInsets.top + headerTapInset)
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { goBack() }
                            .accessibilityLabel("Previous story")
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { advance() }
                            .accessibilityLabel("Next story")
                    }
                }

                VStack(spacing: 10) {
                    progressBars
                    headerRow
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 50) {
                // perform: required closure, intentionally empty
            } onPressingChanged: { pressing in
                isPaused = pressing
            }
            .task(id: PlayKey(index: currentIndex, active: isActive)) {
                guard isActive else { return }
                await runProgressLoop()
            }
            .statusBarHidden(true)
        }
        .sheet(isPresented: $showReport) {
            if let story = currentStory {
                ReportSheet(targetKind: .story, targetId: story.id, nodeId: story.nodeId)
            }
        }
        .confirmationDialog(
            "Block \(author.displayName)?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { try? await BlockService.shared.block(userId: author.user.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their content will be hidden across every node you share. They won't be notified.")
        }
    }

    private struct PlayKey: Hashable {
        let index: Int
        let active: Bool
    }

    private var progressBars: some View {
        HStack(spacing: 4) {
            ForEach(stories.indices, id: \.self) { i in
                GeometryReader { rowGeo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: rowGeo.size.width * fillFraction(for: i))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.forMembership(hex: author.accentColorHex, fallbackSeed: author.id.uuidString))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(author.emoji ?? String(author.displayName.prefix(1)))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(author.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if let story = currentStory {
                    Text(relativeTimeLabel(for: story.createdAt))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            Spacer()

            if author.user.id != auth.session?.user.id {
                Menu {
                    Button("Report story", systemImage: "flag") { showReport = true; isPaused = true }
                    Button("Block \(author.displayName)", systemImage: "person.slash", role: .destructive) { showBlockConfirm = true; isPaused = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Circle())
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
        }
    }

    private func fillFraction(for i: Int) -> Double {
        if i < currentIndex { return 1.0 }
        if i == currentIndex { return progress }
        return 0
    }

    /// Wall-clock-anchored progress loop. Pause works by accumulating paused time and subtracting from elapsed-since-start.
    /// Resume-on-swipe-back: anchor startDate so elapsed equals saved progress, bar continues smoothly.
    @MainActor
    private func runProgressLoop() async {
        if progress >= 1.0 { progress = 0 }
        let anchor = progress
        let startDate = Date().addingTimeInterval(-anchor * storyDuration)
        var pausedAt: Date? = nil
        var totalPaused: TimeInterval = 0
        var didPrefetch = anchor >= 0.5
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
            if !didPrefetch, progress >= 0.5 {
                didPrefetch = true
                prefetchNextImage()
            }
        }
        if !Task.isCancelled { advance() }
    }

    private func prefetchNextImage() {
        guard NetworkMonitor.shared.isUnconstrained else { return }
        guard currentIndex + 1 < stories.count,
              let url = stories[currentIndex + 1].fullURL,
              !prefetchedURLs.contains(url) else { return }
        prefetchedURLs.insert(url)
        Task.detached { _ = try? await URLSession.shared.data(from: url) }
    }

    private func advance() {
        progress = 0
        if currentIndex + 1 < stories.count {
            currentIndex += 1
        } else {
            (onReelComplete ?? onDismiss)()
        }
    }

    private func goBack() {
        if currentIndex == 0 {
            if let onRequestPrevious {
                onRequestPrevious()
            } else {
                progress = 0
            }
        } else {
            progress = 0
            currentIndex -= 1
        }
    }
}
