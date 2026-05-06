import SwiftUI
import Supabase

/// Stories landing screen for one node. Carousel of author rings (current user first, then others by recency),
/// tap-to-play opens StoryTrayView. Compose FAB bottom-right. Pull-to-refresh + scenePhase foreground refresh.
/// Cellular-gated prefetch warms thumbnails on Wi-Fi only.
struct StoriesView: View {
    let nodeId: UUID
    @Environment(StoryService.self) private var stories
    @Environment(AuthService.self) private var auth
    @Environment(BlockService.self) private var blocks
    @Environment(\.scenePhase) private var scenePhase

    @State private var members: [NodeMember] = []
    @State private var isLoading = false
    @State private var showCompose = false
    @State private var playingAuthor: NodeMember? = nil
    @State private var showArchive = false

    private static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private var activeStories: [Story] {
        (stories.activeByNodeId[nodeId] ?? []).filter { !blocks.isBlocked($0.authorUserId) }
    }

    /// Carousel order: current user first, then authors with active stories (newest-first), then others.
    /// Blocked users are excluded from the carousel entirely.
    private var rankedAuthors: [NodeMember] {
        let latestByUserId: [UUID: Date] = activeStories.reduce(into: [:]) { acc, s in
            if let prev = acc[s.authorUserId], prev > s.createdAt { return }
            acc[s.authorUserId] = s.createdAt
        }
        let myId = auth.session?.user.id
        let me = members.first(where: { $0.user.id == myId })
        let others = members.filter { $0.user.id != myId && !blocks.isBlocked($0.user.id) }
        let activeOthers = others
            .filter { latestByUserId[$0.user.id] != nil }
            .sorted { (latestByUserId[$0.user.id] ?? .distantPast) > (latestByUserId[$1.user.id] ?? .distantPast) }
        let inactiveOthers = others.filter { latestByUserId[$0.user.id] == nil }
        return [me].compactMap { $0 } + activeOthers + inactiveOthers
    }

    /// Reel for one author, newest-first per Sunzzari S57 + Miracles S9 user decision.
    private func reel(for author: NodeMember) -> [Story] {
        activeStories.filter { $0.authorUserId == author.user.id }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.nodeBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    if isLoading && activeStories.isEmpty {
                        Spacer()
                        ProgressView()
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                Text(Self.dayHeader.string(from: Date()))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 20)
                                authorCarousel
                                    .padding(.horizontal, 4)
                                if activeStories.isEmpty {
                                    emptyState
                                } else {
                                    Button { showArchive = true } label: {
                                        HStack {
                                            Image(systemName: "rectangle.stack")
                                            Text("Archive")
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.nodeAccent)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 100)
                        }
                        .refreshable { await load(force: true) }
                    }
                }
                composeFAB
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Stories")
            .navigationDestination(isPresented: $showArchive) {
                StoryArchiveView(nodeId: nodeId, authors: members)
            }
        }
        .sheet(isPresented: $showCompose) {
            StoryComposeView(defaultNodeId: nodeId, onPosted: { _ in })
        }
        .fullScreenCover(item: $playingAuthor) { author in
            // Self is excluded from the swipe carousel per user spec: the
            // player is for catching up on others, not re-watching your own.
            // Tapping self in the avatar carousel routes to compose instead
            // (see authorCarousel below).
            StoryTrayView(
                authors: rankedAuthors.filter { $0.user.id != auth.session?.user.id && !reel(for: $0).isEmpty },
                startingAuthor: author,
                reelFor: { reel(for: $0) },
                onDismiss: { playingAuthor = nil }
            )
        }
        .task(id: nodeId) { await load(force: false) }
        .task(id: nodeId) { await subscribeToStories() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load(force: false) } }
        }
    }

    private var authorCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(rankedAuthors) { author in
                    Button {
                        let isMe = author.user.id == auth.session?.user.id
                        if isMe {
                            // Tapping self always routes to compose, even if
                            // self has stories. Self is excluded from the
                            // player's swipe carousel per user spec.
                            showCompose = true
                        } else if !reel(for: author).isEmpty {
                            playingAuthor = author
                        } else {
                            // No-op for others without stories
                        }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .strokeBorder(reel(for: author).isEmpty ? Color.nodeBorder : Color.forMembership(hex: author.accentColorHex, fallbackSeed: author.user.id.uuidString), lineWidth: reel(for: author).isEmpty ? 1.5 : 3)
                                    .frame(width: 72, height: 72)
                                Circle()
                                    .fill(Color.forMembership(hex: author.accentColorHex, fallbackSeed: author.user.id.uuidString))
                                    .frame(width: 60, height: 60)
                                    .overlay(Text(author.emoji ?? String(author.displayName.prefix(1))).font(.title3.weight(.semibold)).foregroundStyle(.white))
                                if author.user.id == auth.session?.user.id && reel(for: author).isEmpty {
                                    Circle()
                                        .fill(Color.nodeAccent)
                                        .frame(width: 22, height: 22)
                                        .overlay(Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.white))
                                        .offset(x: 24, y: 24)
                                }
                            }
                            Text(author.displayName)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(Color.nodeText)
                                .frame(maxWidth: 80)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No stories yet today")
                .font(.headline)
            Text("Tap the + below to post the first story.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }

    private var composeFAB: some View {
        Button { showCompose = true } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.nodeAccent))
                .shadow(radius: 6, y: 2)
        }
    }

    /// Live-updates the carousel whenever any member posts a story visible in this node.
    /// Subscribes to story_visibility inserts (the cross-node junction) rather than stories.origin_node_id,
    /// because origin_node_id is telemetry-only after migration 0002 -- a story shared to this node may
    /// have been authored from a different one. We also handle visibility deletes so un-shares clear live.
    private func subscribeToStories() async {
        let channel = SupabaseService.shared.client.channel("story_visibility:\(nodeId.uuidString)")
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "story_visibility",
            filter: "node_id=eq.\(nodeId.uuidString)"
        )
        let deletions = channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "story_visibility",
            filter: "node_id=eq.\(nodeId.uuidString)"
        )
        await channel.subscribe()
        defer { Task { await channel.unsubscribe() } }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in insertions {
                    await stories.fetchActive(nodeId: nodeId)
                }
            }
            group.addTask {
                for await _ in deletions {
                    await stories.fetchActive(nodeId: nodeId)
                }
            }
        }
    }

    private func load(force: Bool) async {
        isLoading = true
        async let storiesLoad: () = stories.fetchActive(nodeId: nodeId)
        async let membersLoad: [NodeMember] = (try? await NodeService.shared.members(of: nodeId)) ?? []
        _ = await storiesLoad
        members = await membersLoad
        isLoading = false
    }
}
