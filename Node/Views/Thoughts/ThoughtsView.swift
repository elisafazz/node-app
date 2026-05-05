import SwiftUI

/// Stub. Full implementation ports from Miracles `ThoughtsView.swift` in Phase 6.
struct ThoughtsView: View {
    let nodeId: UUID
    @Environment(ThoughtService.self) private var thoughts = ThoughtService.shared
    @State private var newThought = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        let nodeThoughts = thoughts.thoughtsByNodeId[nodeId] ?? []
                        ForEach(nodeThoughts) { thought in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thought.body)
                                Text(thought.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }

                HStack(spacing: 8) {
                    TextField("Share a thought…", text: $newThought, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    Button {
                        Task { await postThought() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(newThought.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Thoughts")
            .refreshable { await thoughts.fetchThoughts(nodeId: nodeId) }
        }
    }

    private func postThought() async {
        guard let me = AuthService.shared.session?.user.id else { return }
        let body = newThought.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        do {
            _ = try await ThoughtService.shared.createThought(nodeId: nodeId, authorUserId: me, body: body)
            newThought = ""
        } catch {
            print("post_thought_failed:", error)
        }
    }
}
