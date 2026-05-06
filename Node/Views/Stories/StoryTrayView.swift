import SwiftUI

/// Wraps per-author StoryPlayerView in a paged TabView so swiping moves between authors (Instagram tray gesture).
/// Only the visible player runs its timer (gated by isActive).
///
/// When the LAST author's reel finishes, instead of dismissing back to the node feed
/// we freeze on the final frame and show a Replay overlay. Replay resets to the first
/// author's first story; Close exits.
struct StoryTrayView: View {
    let authors: [NodeMember]
    let reelFor: (NodeMember) -> [Story]
    let onDismiss: () -> Void

    @State private var currentAuthor: NodeMember
    @State private var showReplay: Bool = false
    /// Bumped on Replay tap. Used as `.id()` on the TabView so SwiftUI rebuilds
    /// every child StoryPlayerView, which is the only way to reset their
    /// `@State currentIndex` and `progress` from outside.
    @State private var replayNonce: UUID = UUID()

    init(
        authors: [NodeMember],
        startingAuthor: NodeMember,
        reelFor: @escaping (NodeMember) -> [Story],
        onDismiss: @escaping () -> Void
    ) {
        self.authors = authors
        self.reelFor = reelFor
        self.onDismiss = onDismiss
        _currentAuthor = State(initialValue: authors.contains(startingAuthor)
                               ? startingAuthor
                               : (authors.first ?? startingAuthor))
    }

    var body: some View {
        ZStack {
            TabView(selection: $currentAuthor) {
                ForEach(authors) { author in
                    StoryPlayerView(
                        stories: reelFor(author),
                        author: author,
                        onDismiss: onDismiss,
                        onReelComplete: { advance(after: author) },
                        onRequestPrevious: { back(from: author) },
                        // Pause the visible player while the replay overlay is up
                        // so its progress task doesn't keep ticking past the end.
                        isActive: currentAuthor == author && !showReplay
                    )
                    .tag(author)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .id(replayNonce)

            if showReplay {
                replayOverlay
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden(true)
    }

    private var replayOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(spacing: 18) {
                Button(action: replay) {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 34, weight: .semibold))
                        Text("Replay")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 150, height: 150)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                }
                .accessibilityLabel("Replay stories")

                Button(action: onDismiss) {
                    Text("Close")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Close stories")
            }
        }
        .transition(.opacity)
    }

    private func advance(after author: NodeMember) {
        guard let idx = authors.firstIndex(of: author) else {
            showReplay = true
            return
        }
        if idx + 1 < authors.count {
            withAnimation(.easeInOut(duration: 0.25)) { currentAuthor = authors[idx + 1] }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showReplay = true }
        }
    }

    private func back(from author: NodeMember) {
        guard let idx = authors.firstIndex(of: author), idx > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) { currentAuthor = authors[idx - 1] }
    }

    private func replay() {
        currentAuthor = authors.first ?? currentAuthor
        // New UUID forces every StoryPlayerView to rebuild from scratch, which
        // resets currentIndex/progress to 0 and restarts the progress task.
        replayNonce = UUID()
        withAnimation(.easeInOut(duration: 0.2)) { showReplay = false }
    }
}
