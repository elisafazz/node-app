import SwiftUI

struct BlockedUsersView: View {
    @Environment(BlockService.self) private var blocks
    @State private var users: [AppUser] = []
    @State private var loading = true
    @State private var error: String?
    @State private var pendingUnblock: AppUser?

    var body: some View {
        List {
            if loading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if users.isEmpty {
                Section {
                    Text("You have not blocked anyone.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Section {
                    Text("Blocking a user hides their stories, photos, and thoughts everywhere they appear -- across every node you share with them. They are not notified.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Blocked") {
                    ForEach(users) { user in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.forMembership(hex: nil, fallbackSeed: user.id.uuidString))
                                .frame(width: 32, height: 32)
                                .overlay(Text(String(user.displayName.prefix(1))).font(.caption.weight(.bold)).foregroundStyle(.white))
                            Text(user.displayName).font(.body)
                            Spacer()
                            Button("Unblock") { pendingUnblock = user }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("Blocked users")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            pendingUnblock.map { "Unblock \($0.displayName)?" } ?? "",
            isPresented: Binding(get: { pendingUnblock != nil }, set: { if !$0 { pendingUnblock = nil } }),
            titleVisibility: .visible
        ) {
            Button("Unblock", role: .destructive) {
                if let user = pendingUnblock {
                    Task { await unblock(user) }
                }
                pendingUnblock = nil
            }
            Button("Cancel", role: .cancel) { pendingUnblock = nil }
        } message: {
            Text("They will be able to see your activity in nodes you share, and you will see theirs.")
        }
    }

    private func load() async {
        loading = true
        error = nil
        await blocks.loadBlockedUsers()
        let ids = Array(blocks.blockedUserIds)
        guard !ids.isEmpty else {
            users = []
            loading = false
            return
        }
        do {
            let rows: [AppUser] = try await SupabaseService.shared.database
                .from("users")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
            users = rows.sorted { $0.displayName < $1.displayName }
        } catch {
            self.error = UserFacingError.message(for: error)
        }
        loading = false
    }

    private func unblock(_ user: AppUser) async {
        do {
            try await blocks.unblock(userId: user.id)
            users.removeAll { $0.id == user.id }
        } catch {
            self.error = UserFacingError.message(for: error)
        }
    }
}
