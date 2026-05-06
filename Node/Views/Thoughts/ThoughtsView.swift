import SwiftUI

struct ThoughtsView: View {
    let nodeId: UUID
    @Environment(ThoughtService.self) private var thoughts
    @Environment(\.scenePhase) private var scenePhase
    @State private var newThought = ""
    @State private var error: String?
    @State private var posting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        let nodeThoughts = thoughts.thoughtsByNodeId[nodeId] ?? []
                        if nodeThoughts.isEmpty {
                            emptyState
                        } else {
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
                    }
                    .padding()
                }

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
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
                        Image(systemName: posting ? "ellipsis" : "paperplane.fill")
                    }
                    .disabled(posting || newThought.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Thoughts")
            .refreshable { await thoughts.fetchThoughts(nodeId: nodeId) }
        }
        .task { await thoughts.fetchThoughts(nodeId: nodeId) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await thoughts.fetchThoughts(nodeId: nodeId) } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No thoughts yet")
                .font(.subheadline.weight(.semibold))
            Text("Share something quick with this node.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

    private func postThought() async {
        guard let me = AuthService.shared.session?.user.id else { return }
        let body = newThought.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, !posting else { return }
        posting = true
        error = nil
        do {
            _ = try await ThoughtService.shared.createThought(nodeId: nodeId, authorUserId: me, body: body)
            newThought = ""
        } catch {
            self.error = UserFacingError.message(for: error)
            Log.shared.error("post_thought_failed", error: error)
        }
        posting = false
    }
}
