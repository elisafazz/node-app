import SwiftUI

struct JoinNodeView: View {
    @Environment(NodeService.self) private var nodes
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var attempting = false
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced))
                        .onChange(of: code) { _, newValue in
                            code = String(newValue.prefix(8))
                        }
                } header: {
                    Text("Enter the 8-character code")
                } footer: {
                    Text("Ask the node owner for the code. Codes can be rotated by the owner if leaked.")
                }

                if let feedback {
                    Section {
                        Text(feedback).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Join node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(attempting ? "Joining…" : "Join") { attempt() }
                        .disabled(attempting || code.count != 8)
                }
            }
        }
    }

    private func attempt() {
        attempting = true
        feedback = nil
        Task {
            do {
                let result = try await nodes.joinByInviteCode(code)
                if case .joined = result {
                    await PushService.shared.requestAuthorizationIfNeeded()
                    dismiss()
                } else if let message = UserFacingError.inviteCodeMessage(for: result) {
                    feedback = message
                }
            } catch {
                feedback = UserFacingError.message(for: error)
            }
            attempting = false
        }
    }
}
