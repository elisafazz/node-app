import SwiftUI

struct NodeSettingsView: View {
    let node: NodeRecord
    @Environment(NodeService.self) private var nodes
    @Environment(AuthService.self) private var auth

    @State private var perNodeName = ""
    @State private var perNodeEmoji = ""
    @State private var perNodeAccentHex = ""
    @State private var accentColor: Color = .nodeBrand
    @State private var saving = false
    @State private var saveError: String?
    @State private var actionError: String?
    @State private var showRotateConfirm = false
    @State private var showLeaveConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("This node") {
                    LabeledContent("Name", value: node.name)
                    LabeledContent("Members") { Text("Up to \(node.memberCap)") }
                    if isOwner {
                        LabeledContent("Invite code", value: liveInviteCode)
                        Button("Rotate invite code") { showRotateConfirm = true }
                    }
                }

                Section("My identity in this node") {
                    TextField("Display name override", text: $perNodeName)
                    TextField("Emoji", text: $perNodeEmoji)
                    ColorPicker("Accent color", selection: $accentColor, supportsOpacity: false)
                        .onChange(of: accentColor) { _, c in perNodeAccentHex = c.hexString }
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(saving)
                    if let saveError {
                        Text(saveError).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("Members") {
                    NavigationLink("View members") {
                        NodeMembersView(nodeId: node.id)
                    }
                }

                Section {
                    Button("Leave node", role: .destructive) { showLeaveConfirm = true }
                    if let actionError {
                        Text(actionError).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .onAppear { loadFromMembership() }
            .navigationTitle("Settings")
            .alert("Rotate invite code?", isPresented: $showRotateConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Rotate", role: .destructive) { rotateCode() }
            } message: {
                Text("The current code will stop working. Anyone who hasn't joined yet will need the new code.")
            }
            .alert("Leave node?", isPresented: $showLeaveConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Leave", role: .destructive) { leave() }
            } message: {
                Text("You will lose access to all content in \(node.name). You can rejoin with an invite code.")
            }
        }
    }

    private var liveInviteCode: String {
        nodes.myNodes.first { $0.id == node.id }?.inviteCode ?? node.inviteCode
    }

    private var isOwner: Bool {
        nodes.myMembershipsByNodeId[node.id]?.role == .owner
    }

    private func loadFromMembership() {
        let m = nodes.myMembershipsByNodeId[node.id]
        perNodeName = m?.perNodeDisplayName ?? ""
        perNodeEmoji = m?.perNodeEmoji ?? ""
        let hex = m?.perNodeAccentColor ?? ""
        perNodeAccentHex = hex
        accentColor = Color(hex: hex) ?? .nodeBrand
    }

    private func save() {
        saving = true
        saveError = nil
        Task {
            defer { saving = false }
            do {
                try await nodes.updateMyMembership(
                    nodeId: node.id,
                    displayName: perNodeName.isEmpty ? nil : perNodeName,
                    accentColorHex: perNodeAccentHex.isEmpty ? nil : perNodeAccentHex,
                    emoji: perNodeEmoji.isEmpty ? nil : perNodeEmoji
                )
            } catch {
                saveError = UserFacingError.message(for: error)
            }
        }
    }

    private func rotateCode() {
        actionError = nil
        Task {
            do {
                _ = try await nodes.rotateInviteCode(nodeId: node.id)
            } catch {
                actionError = UserFacingError.message(for: error)
            }
        }
    }

    private func leave() {
        guard let me = auth.session?.user.id else { return }
        actionError = nil
        Task {
            do {
                try await nodes.leaveNode(nodeId: node.id, userId: me)
            } catch {
                actionError = UserFacingError.message(for: error)
            }
        }
    }
}

struct NodeMembersView: View {
    let nodeId: UUID
    @Environment(AuthService.self) private var auth
    @State private var members: [NodeMember] = []
    @State private var reportTarget: NodeMember?
    @State private var blockTarget: NodeMember?

    var body: some View {
        List(members) { member in
            let isMe = member.user.id == auth.session?.user.id
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.forMembership(hex: member.accentColorHex, fallbackSeed: member.id.uuidString))
                    .frame(width: 36, height: 36)
                    .overlay(Text(member.emoji ?? String(member.displayName.prefix(1))).font(.body))
                VStack(alignment: .leading) {
                    Text(member.displayName).font(.body)
                    Text(member.membership.role.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !isMe {
                    Menu {
                        Button("Report", systemImage: "flag") { reportTarget = member }
                        Button("Block", systemImage: "person.slash", role: .destructive) { blockTarget = member }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Members")
        .task {
            members = (try? await NodeService.shared.members(of: nodeId)) ?? []
        }
        .sheet(item: $reportTarget) { member in
            ReportSheet(targetKind: .user, targetId: member.user.id, nodeId: nodeId)
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
}
