import SwiftUI

struct CreateNodeView: View {
    @Environment(NodeService.self) private var nodes
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var creating = false
    @State private var createdInviteCode: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Node name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name your node")
                } footer: {
                    Text("Up to 60 characters. You can rename it later.")
                }

                if let code = createdInviteCode {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Share this code with your friends")
                                .font(.headline)
                            Text(code)
                                .font(.system(.title2, design: .monospaced))
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(8)
                            HStack(spacing: 12) {
                                Button {
                                    #if canImport(UIKit)
                                    UIPasteboard.general.string = code
                                    #endif
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                ShareLink(item: "Join my Node with code: \(code)") {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("New node")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if createdInviteCode == nil {
                        Button(creating ? "Creating…" : "Create") { create() }
                            .disabled(creating || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private func create() {
        creating = true
        error = nil
        Task {
            do {
                let result = try await nodes.createNode(name: name.trimmingCharacters(in: .whitespaces))
                self.createdInviteCode = result.inviteCode
                await PushService.shared.requestAuthorizationIfNeeded()
            } catch {
                self.error = UserFacingError.message(for: error)
            }
            self.creating = false
        }
    }
}
