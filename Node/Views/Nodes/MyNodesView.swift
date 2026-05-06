import SwiftUI

struct MyNodesView: View {
    @Environment(NodeService.self) private var nodes
    @Environment(AuthService.self) private var auth

    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                if nodes.myNodes.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Your Nodes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Create node", systemImage: "plus.circle") { showCreate = true }
                        Button("Join with code", systemImage: "rectangle.inset.filled.and.person.filled") { showJoin = true }
                        Divider()
                        Button("Settings", systemImage: "gearshape") { showSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task { await nodes.loadMyNodes() }
            .refreshable { await nodes.loadMyNodes() }
            .sheet(isPresented: $showCreate) { CreateNodeView() }
            .sheet(isPresented: $showJoin) { JoinNodeView() }
            .sheet(isPresented: $showSettings) { GlobalSettingsView() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.grid.3x3.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("You're not in any nodes yet")
                .font(.headline)
            Text("Create a node and invite up to 9 friends, or join one with a code from a friend.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("Create node") { showCreate = true }
                    .buttonStyle(.borderedProminent)
                Button("Join with code") { showJoin = true }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
    }

    private var list: some View {
        List {
            ForEach(nodes.myNodes) { node in
                NavigationLink(value: node) {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.forMembership(hex: nodes.myMembershipsByNodeId[node.id]?.perNodeAccentColor, fallbackSeed: node.id.uuidString))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(nodes.myMembershipsByNodeId[node.id]?.perNodeEmoji ?? String(node.name.prefix(1)))
                                    .font(.title3)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name).font(.headline)
                            Text(nodes.myMembershipsByNodeId[node.id]?.role.rawValue.capitalized ?? "Member")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: NodeRecord.self) { node in
            NodeRootView(node: node)
        }
    }
}
