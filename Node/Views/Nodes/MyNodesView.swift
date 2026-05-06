import SwiftUI

struct MyNodesView: View {
    @Environment(NodeService.self) private var nodes
    @Environment(AuthService.self) private var auth

    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nodeBackground.ignoresSafeArea()
                if nodes.myNodes.isEmpty {
                    emptyState
                } else {
                    nodeList
                }
            }
            .navigationTitle("My Nodes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Create node", systemImage: "plus.circle") { showCreate = true }
                        Button("Join with code", systemImage: "rectangle.inset.filled.and.person.filled") { showJoin = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: NodeRecord.self) { node in
                NodeRootView(node: node)
            }
            .task { await nodes.loadMyNodes() }
            .refreshable { await nodes.loadMyNodes() }
            .sheet(isPresented: $showCreate) { CreateNodeView() }
            .sheet(isPresented: $showJoin) { JoinNodeView() }
        }
    }

    private var nodeList: some View {
        List {
            ForEach(nodes.myNodes) { node in
                NavigationLink(value: node) {
                    nodeRow(node)
                }
                .listRowBackground(Color.nodeSurface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func nodeRow(_ node: NodeRecord) -> some View {
        let m = nodes.myMembershipsByNodeId[node.id]
        let accent = Color.forMembership(hex: m?.perNodeAccentColor, fallbackSeed: node.id.uuidString)
        let glyph = m?.perNodeEmoji ?? String(node.name.prefix(1))
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent)
                    .frame(width: 44, height: 44)
                Text(glyph)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(m?.perNodeDisplayName ?? node.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.nodeText)
                if let alias = m?.perNodeDisplayName, alias != node.name {
                    Text(node.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 56))
                .foregroundStyle(Color.nodeBrand.opacity(0.6))
            Text("You're not in any nodes yet")
                .font(.headline)
            Text("Create a node and invite up to 9 friends, or join one with a code.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("Create node") { showCreate = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.nodeBrand)
                Button("Join with code") { showJoin = true }
                    .buttonStyle(.bordered)
                    .tint(Color.nodeBrand)
            }
            .padding(.top, 8)
        }
    }
}
