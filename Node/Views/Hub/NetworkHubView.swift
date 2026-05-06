import SwiftUI

struct NetworkHubView: View {
    @Environment(NodeService.self) private var nodes
    @Environment(AuthService.self) private var auth
    @Environment(StoryService.self) private var stories

    @State private var showCompose = false
    @State private var showBoop = false
    @State private var showMeeting = false
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.nodeBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {
                        graphSection
                        quickActionsSection
                        recentActivitySection
                    }
                    .padding(.bottom, 100)
                }
                boopFAB
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .foregroundStyle(Color.nodeBrand)
                        Text("Node")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.nodeBrand)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: {
                        Image(systemName: "bell")
                            .foregroundStyle(Color.nodeText)
                    }
                }
            }
            .navigationDestination(for: NodeRecord.self) { node in
                NodeRootView(node: node)
            }
            .sheet(isPresented: $showCompose) {
                // nil defaultNodeId: compose launched from Hub pre-selects all nodes
                StoryComposeView()
            }
            .sheet(isPresented: $showBoop) {
                BoopComposeView()
            }
            .sheet(isPresented: $showMeeting) {
                ScheduleMeetingView()
            }
            .task { await stories.fetchAllVisible() }
            .refreshable { await stories.fetchAllVisible() }
        }
    }

    // MARK: - Graph section

    private var graphSection: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, 380)
            let radius = size * 0.36
            let center = CGPoint(x: geo.size.width / 2, y: size * 0.52)
            let nodeList = nodes.myNodes
            let positions = ringPositions(count: nodeList.count, radius: radius, center: center)

            ZStack {
                Path { path in
                    for p in positions {
                        path.move(to: center)
                        path.addLine(to: p)
                    }
                }
                .stroke(Color.nodeBrand.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                Circle()
                    .stroke(Color.nodeBrand.opacity(0.15), lineWidth: 1)
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .position(center)

                centerAvatar.position(center)

                ForEach(Array(nodeList.enumerated()), id: \.element.id) { idx, node in
                    hubNodeCircle(node: node).position(positions[idx])
                }
            }
            .frame(height: size)
            .onAppear {
                withAnimation(.easeOut(duration: 2.6).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
        .frame(height: 280)
        .padding(.horizontal, 8)
    }

    private var centerAvatar: some View {
        let name = auth.profile?.displayName ?? "You"
        return ZStack {
            Circle()
                .fill(Color.nodeBrand)
                .frame(width: 84, height: 84)
                .shadow(color: Color.nodeBrand.opacity(0.3), radius: 10, y: 2)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.nodeText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.nodeSurface))
                .offset(y: 56)
                .lineLimit(1)
                .frame(maxWidth: 100)
        }
    }

    /// Hub node circles: white fill, coral border, coral emoji/initial — per Stitch mockup.
    private func hubNodeCircle(node: NodeRecord) -> some View {
        let m = nodes.myMembershipsByNodeId[node.id]
        let glyph = m?.perNodeEmoji ?? String(node.name.prefix(1))
        return NavigationLink(value: node) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 60, height: 60)
                        .overlay(Circle().stroke(Color.nodeBrand, lineWidth: 2))
                        .shadow(color: Color.nodeBrand.opacity(0.2), radius: 5, y: 2)
                    Text(glyph)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.nodeBrand)
                }
                Text(node.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.nodeText)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            }
        }
        .buttonStyle(.plain)
    }

    private func ringPositions(count: Int, radius: CGFloat, center: CGPoint) -> [CGPoint] {
        guard count > 0 else { return [] }
        let step = (2 * .pi) / CGFloat(count)
        let start: CGFloat = -.pi / 2
        return (0..<count).map { i in
            let angle = start + CGFloat(i) * step
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            HStack(spacing: 12) {
                quickActionButton(
                    title: "Post Update",
                    icon: "photo.badge.plus",
                    action: { showCompose = true }
                )
                quickActionButton(
                    title: "Schedule Meeting",
                    icon: "calendar.badge.plus",
                    action: { showMeeting = true }
                )
            }
            .padding(.horizontal, 16)
        }
    }

    private func quickActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.nodeBrand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            if stories.allVisible.isEmpty {
                emptyActivityState
            } else {
                recentStoriesCarousel
            }
        }
    }

    private var emptyActivityState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(Color.nodeBrand.opacity(0.5))
            Text("Nothing yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("When members post stories or updates, they'll appear here.")
                .font(.caption)
                .foregroundStyle(Color.nodeText.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var recentStoriesCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(stories.allVisible.prefix(10)) { story in
                    StoryThumbnailCell(story: story)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Boop FAB

    private var boopFAB: some View {
        Button { showBoop = true } label: {
            Image(systemName: "bolt.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.nodeBrand, in: Circle())
                .shadow(color: Color.nodeBrand.opacity(0.4), radius: 8, y: 3)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .accessibilityLabel("Boop your nodes")
    }

}
