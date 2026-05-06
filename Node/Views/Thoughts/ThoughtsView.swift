import SwiftUI

struct ThoughtsView: View {
    let nodeId: UUID
    @Environment(ThoughtService.self) private var thoughts
    @Environment(BlockService.self) private var blocks
    @Environment(\.scenePhase) private var scenePhase
    @State private var newThought = ""
    @State private var members: [NodeMember] = []
    @State private var lastRefreshed: Date = .distantPast
    @State private var reportTarget: Thought?
    @State private var blockTarget: NodeMember?
    @State private var error: String?
    @State private var posting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        let nodeThoughts = (thoughts.thoughtsByNodeId[nodeId] ?? []).filter { !blocks.isBlocked($0.authorUserId) }
                        if nodeThoughts.isEmpty {
                            emptyState
                        } else {
                            ForEach(nodeThoughts) { thought in
                                thoughtCard(thought)
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
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("Share a thought…", text: $newThought, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .onChange(of: newThought) { _, value in
                                if value.count > 2000 {
                                    newThought = String(value.prefix(2000))
                                }
                            }
                        if newThought.count > 1800 {
                            Text("\(2000 - newThought.count)")
                                .font(.caption2)
                                .foregroundStyle(newThought.count >= 2000 ? .red : .secondary)
                                .padding(.trailing, 4)
                        }
                    }
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
            .refreshable { await refresh() }
            .sheet(item: $reportTarget) { thought in
                ReportSheet(targetKind: .thought, targetId: thought.id, nodeId: nodeId)
            }
            .confirmationDialog(
                blockTarget.map { "Block \($0.displayName)?" } ?? "",
                isPresented: Binding(get: { blockTarget != nil }, set: { if !$0 { blockTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Block", role: .destructive) {
                    if let target = blockTarget {
                        Task { try? await BlockService.shared.block(userId: target.user.id) }
                    }
                    blockTarget = nil
                }
                Button("Cancel", role: .cancel) { blockTarget = nil }
            } message: {
                Text("Their content will be hidden across every node you share. They won't be notified.")
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            guard Date().timeIntervalSince(lastRefreshed) > 30 else { return }
            guard !NetworkMonitor.shared.isExpensive else { return }
            lastRefreshed = Date()
            Task { await thoughts.fetchThoughts(nodeId: nodeId) }
        }
    }

    @ViewBuilder
    private func thoughtCard(_ thought: Thought) -> some View {
        let author = members.first { $0.membership.userId == thought.authorUserId }
        let isOwn = thought.authorUserId == AuthService.shared.session?.user.id
        VStack(alignment: .leading, spacing: 6) {
            if let author {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.forMembership(hex: author.accentColorHex, fallbackSeed: author.membership.id.uuidString))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text(author.emoji ?? String(author.displayName.prefix(1)))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    Text(author.displayName)
                        .font(.footnote.weight(.semibold))
                }
            }
            Text(thought.body)
            Text(thought.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
        .contextMenu {
            if isOwn {
                Button(role: .destructive) {
                    Task { try? await ThoughtService.shared.deleteThought(thought) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button {
                    reportTarget = thought
                } label: {
                    Label("Report", systemImage: "flag")
                }
                if let author {
                    Button(role: .destructive) {
                        blockTarget = author
                    } label: {
                        Label("Block \(author.displayName)", systemImage: "person.slash")
                    }
                }
            }
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

    private func refresh() async {
        await thoughts.fetchThoughts(nodeId: nodeId)
        members = (try? await NodeService.shared.members(of: nodeId)) ?? []
    }

    private func postThought() async {
        guard let me = AuthService.shared.session?.user.id else { return }
        let body = newThought.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, !posting else { return }
        posting = true
        error = nil
        do {
            _ = try await thoughts.createThought(nodeId: nodeId, authorUserId: me, body: body)
            newThought = ""
        } catch {
            self.error = UserFacingError.message(for: error)
            Log.shared.error("post_thought_failed", error: error)
        }
        posting = false
    }
}
