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
    /// The node the viewer is browsing stories from. Threaded into StoryPlayerView so
    /// reports get scoped correctly and the owner-only moderation menu can render.
    /// Nil when launched from Hub aggregated feed (no single viewing node).
    var viewingNodeId: UUID? = nil

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
        onDismiss: @escaping () -> Void,
        viewingNodeId: UUID? = nil
    ) {
        self.authors = authors
        self.reelFor = reelFor
        self.onDismiss = onDismiss
        self.viewingNodeId = viewingNodeId
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
                        isActive: currentAuthor == author && !showReplay,
                        viewingNodeId: viewingNodeId
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
        // Keep the last frame fully visible behind the controls — no full-screen
        // dim. A small glass-blur Replay button sits center, Close sits below.
        VStack(spacing: 14) {
            Button(action: replay) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Replay")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.5))
            }
            .accessibilityLabel("Replay stories")

            Button(action: onDismiss) {
                Text("Close")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .accessibilityLabel("Close stories")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
