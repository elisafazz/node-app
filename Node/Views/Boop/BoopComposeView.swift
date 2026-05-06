import SwiftUI

/// Multi-node Boop compose sheet. User picks nodes + optional 100-char message, taps Send.
struct BoopComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NodeService.self) private var nodes

    @State private var message = ""
    @State private var selectedNodeIds: Set<UUID> = []
    @State private var isSending = false
    @State private var errorMessage: String?

    private let messageLimit = 100

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nodeBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    headerSection
                    Divider()
                    ScrollView {
                        VStack(spacing: 24) {
                            messageSection
                            nodeSelectorSection
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                            .fontWeight(.semibold)
                            .tint(Color.nodeBrand)
                            .disabled(selectedNodeIds.isEmpty)
                    }
                }
            }
            // Do NOT default-select all nodes -- an accidental Send would ping all members.
            // User must explicitly choose who to boop.
        }
    }

    private var headerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.nodeBrand)
            VStack(alignment: .leading, spacing: 2) {
                Text("Boop")
                    .font(.title3.weight(.semibold))
                Text("Send a quick ping to your selected nodes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Message", systemImage: "text.bubble")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(message.count)/\(messageLimit)")
                    .font(.caption2)
                    .foregroundStyle(message.count > messageLimit ? .red : .secondary)
            }
            TextField("Optional - say something (100 chars max)", text: $message, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(Color.nodeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: message) { _, new in
                    if new.count > messageLimit {
                        message = String(new.prefix(messageLimit))
                    }
                }
        }
    }

    private var nodeSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Send to", systemImage: "circle.hexagongrid")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(nodes.myNodes) { node in
                nodeRow(node)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func nodeRow(_ node: NodeRecord) -> some View {
        let isSelected = selectedNodeIds.contains(node.id)
        let m = nodes.myMembershipsByNodeId[node.id]
        let label = m?.perNodeDisplayName ?? node.name
        let accent = Color.forMembership(hex: m?.perNodeAccentColor, fallbackSeed: node.id.uuidString)
        return Button {
            if isSelected && selectedNodeIds.count == 1 { return }
            if isSelected { selectedNodeIds.remove(node.id) }
            else { selectedNodeIds.insert(node.id) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(accent).frame(width: 40, height: 40)
                    Text(m?.perNodeEmoji ?? String(node.name.prefix(1)))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Text(label)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.nodeText)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.nodeBrand : Color.nodeText.opacity(0.3))
            }
            .padding(14)
            .background(Color.nodeSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func send() async {
        guard !selectedNodeIds.isEmpty else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await BoopService.shared.sendBoop(
                message: trimmed.isEmpty ? nil : trimmed,
                nodeIds: Array(selectedNodeIds)
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
