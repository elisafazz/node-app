import SwiftUI

/// Stub implementation. Full IG-parity port from Miracles `StoriesView.swift` lands in Phase 4.
/// What's here: list of active stories with thumbnails, +button to compose.
struct StoriesView: View {
    let nodeId: UUID
    @Environment(StoryService.self) private var stories = StoryService.shared
    @State private var showCompose = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    let active = stories.activeByNodeId[nodeId] ?? []
                    ForEach(active) { story in
                        AsyncImage(url: story.thumbnailURL) { phase in
                            switch phase {
                            case .empty: Color.gray.opacity(0.2)
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Image(systemName: "exclamationmark.triangle")
                            @unknown default: Color.gray.opacity(0.2)
                            }
                        }
                        .frame(height: 200)
                        .clipped()
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Stories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCompose = true } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showCompose) {
                StoryComposeView(nodeId: nodeId)
            }
            .refreshable { await stories.fetchActive(nodeId: nodeId) }
        }
    }
}

/// Stub. Full implementation from Miracles `StoryComposeView.swift` lands in Phase 4.
struct StoryComposeView: View {
    let nodeId: UUID
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack {
                Text("Story composer -- port from Miracles in Phase 4.")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("New story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
