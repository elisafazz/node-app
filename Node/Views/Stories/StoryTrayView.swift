import SwiftUI

/// Wraps per-author StoryPlayerView in a paged TabView so swiping moves between authors (Instagram tray gesture).
/// Only the visible player runs its timer (gated by isActive).
struct StoryTrayView: View {
    let authors: [NodeMember]
    let reelFor: (NodeMember) -> [Story]
    let onDismiss: () -> Void

    @State private var currentAuthor: NodeMember

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
        TabView(selection: $currentAuthor) {
            ForEach(authors) { author in
                StoryPlayerView(
                    stories: reelFor(author),
                    author: author,
                    onDismiss: onDismiss,
                    onReelComplete: { advance(after: author) },
                    onRequestPrevious: { back(from: author) },
                    isActive: currentAuthor == author
                )
                .tag(author)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden(true)
    }

    private func advance(after author: NodeMember) {
        guard let idx = authors.firstIndex(of: author) else {
            onDismiss(); return
        }
        if idx + 1 < authors.count {
            withAnimation(.easeInOut(duration: 0.25)) { currentAuthor = authors[idx + 1] }
        } else {
            onDismiss()
        }
    }

    private func back(from author: NodeMember) {
        guard let idx = authors.firstIndex(of: author), idx > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) { currentAuthor = authors[idx - 1] }
    }
}
