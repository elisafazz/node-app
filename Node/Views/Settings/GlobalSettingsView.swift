import SwiftUI

struct GlobalSettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var saving = false
    @State private var showDeleteConfirm = false
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Display name", text: $displayName)
                    Button(saving ? "Saving…" : "Save") { saveProfile() }
                        .disabled(saving)
                }

                Section("Legal") {
                    Link("Terms of Service", destination: Constants.URLs.tos)
                    Link("Privacy Policy", destination: Constants.URLs.privacy)
                    Link("EULA", destination: Constants.URLs.eula)
                    Link("Contact", destination: Constants.URLs.contact)
                }

                Section("Safety") {
                    NavigationLink("Blocked users") { BlockedUsersView() }
                    NavigationLink("Report a problem") { ReportProblemView() }
                }

                Section("Account") {
                    Button("Sign out") { signOut() }
                    Button("Delete account", role: .destructive) { showDeleteConfirm = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { displayName = auth.profile?.displayName ?? "" }
            .alert("Delete account?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete permanently", role: .destructive) { deleteAccount() }
            } message: {
                Text("All your nodes, photos, stories, and thoughts will be permanently deleted. Your Apple ID grant will be revoked. This cannot be undone.")
            }
        }
    }

    private func saveProfile() {
        saving = true
        Task {
            struct UserPatch: Encodable { let display_name: String }
            try? await SupabaseService.shared.database
                .from("users")
                .update(UserPatch(display_name: displayName))
                .execute()
            try? await auth.fetchProfile()
            saving = false
        }
    }

    private func signOut() {
        Task {
            try? await auth.signOut()
            dismiss()
        }
    }

    private func deleteAccount() {
        deleting = true
        Task {
            try? await auth.deleteAccount()
            dismiss()
            deleting = false
        }
    }
}

struct BlockedUsersView: View {
    @State private var blocked: [AppUser] = []

    var body: some View {
        List(blocked) { user in
            HStack {
                Text(user.displayName)
                Spacer()
                Button("Unblock") {
                    Task { try? await BlockService.shared.unblock(userId: user.id) }
                }
                .buttonStyle(.borderless)
            }
        }
        .navigationTitle("Blocked")
        .task { await load() }
    }

    private func load() async {
        await BlockService.shared.loadBlockedUsers()
        let ids = BlockService.shared.blockedUserIds
        guard !ids.isEmpty else { blocked = []; return }
        let users: [AppUser] = (try? await SupabaseService.shared.database
            .from("users")
            .select()
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value) ?? []
        blocked = users
    }
}

struct ReportProblemView: View {
    @State private var reason = ""
    @State private var submitting = false
    @State private var feedback: String?

    var body: some View {
        Form {
            Section("Tell us what happened") {
                TextEditor(text: $reason)
                    .frame(minHeight: 120)
            }
            if let feedback {
                Section { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                Button(submitting ? "Submitting…" : "Submit report") { submit() }
                    .disabled(submitting || reason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Report a problem")
    }

    private func submit() {
        submitting = true
        Task {
            do {
                guard let me = AuthService.shared.session?.user.id else { return }
                try await ReportService.shared.submit(
                    targetKind: .user,
                    targetId: me,
                    nodeId: nil,
                    reason: reason
                )
                feedback = "Report submitted. Thanks."
                reason = ""
            } catch {
                feedback = "Could not submit: \(error.localizedDescription)"
            }
            submitting = false
        }
    }
}
