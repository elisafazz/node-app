import SwiftUI

struct GlobalSettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Display name", text: $displayName)
                    Button(saving ? "Saving…" : "Save") { saveProfile() }
                        .disabled(saving)
                    if let saveError {
                        Text(saveError).font(.footnote).foregroundStyle(.red)
                    }
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
                    Button(deleting ? "Deleting…" : "Delete account", role: .destructive) { showDeleteConfirm = true }
                        .disabled(deleting)
                    if let deleteError {
                        Text(deleteError).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
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
        saveError = nil
        Task {
            defer { saving = false }
            guard let userId = auth.profile?.id.uuidString else { return }
            struct UserPatch: Encodable { let display_name: String }
            do {
                try await SupabaseService.shared.database
                    .from("users")
                    .update(UserPatch(display_name: displayName))
                    .eq("id", value: userId)
                    .execute()
                try await auth.fetchProfile()
            } catch {
                saveError = UserFacingError.message(for: error)
            }
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
        deleteError = nil
        Task {
            do {
                try await auth.deleteAccount()
                dismiss()
            } catch {
                deleteError = "Deletion failed: \(UserFacingError.message(for: error)). Try again or contact support."
            }
            deleting = false
        }
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
                feedback = "Could not submit. \(UserFacingError.message(for: error))"
            }
            submitting = false
        }
    }
}
