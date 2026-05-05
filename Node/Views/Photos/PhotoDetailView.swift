import SwiftUI

struct PhotoDetailView: View {
    let photo: Photo
    let members: [NodeMember]
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @State private var showEdit = false
    @State private var showReport = false
    @State private var deleteConfirm = false

    private var author: NodeMember? { members.first { $0.user.id == photo.authorUserId } }
    private var isMyPhoto: Bool { photo.authorUserId == auth.session?.user.id }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AsyncImage(url: photo.fullURL) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFit()
                            case .empty: ProgressView().tint(.white).frame(height: 400).frame(maxWidth: .infinity)
                            case .failure: VStack { Image(systemName: "exclamationmark.triangle"); Text("Couldn't load") }.foregroundStyle(.white).frame(height: 400)
                            @unknown default: EmptyView()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            if let author {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.forMembership(hex: author.accentColorHex, fallbackSeed: author.user.id.uuidString))
                                        .frame(width: 28, height: 28)
                                        .overlay(Text(author.emoji ?? String(author.displayName.prefix(1))).font(.caption.weight(.bold)).foregroundStyle(.white))
                                    Text(author.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Spacer()
                                    Text(photo.createdAt, style: .date).font(.caption).foregroundStyle(.white.opacity(0.7))
                                }
                            }
                            if let caption = photo.caption, !caption.isEmpty {
                                Text(caption).font(.body).foregroundStyle(.white)
                            }
                            if let tag = photo.tag, !tag.isEmpty {
                                Text(tag)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.white.opacity(0.15))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if isMyPhoto {
                            Button("Edit", systemImage: "pencil") { showEdit = true }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirm = true }
                        } else {
                            Button("Report", systemImage: "flag") { showReport = true }
                        }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.white) }
                }
            }
            .sheet(isPresented: $showEdit) { EditPhotoView(photo: photo) }
            .sheet(isPresented: $showReport) {
                ReportSheet(targetKind: .photo, targetId: photo.id, nodeId: photo.nodeId)
            }
            .alert("Delete photo?", isPresented: $deleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        try? await PhotoService.shared.deletePhoto(photo)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Generic in-app report sheet, reusable from photos / stories / thoughts / member list.
struct ReportSheet: View {
    let targetKind: ReportService.TargetKind
    let targetId: UUID
    let nodeId: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var submitting = false
    @State private var feedback: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    TextEditor(text: $reason).frame(minHeight: 120)
                }
                if let feedback {
                    Section { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "Submitting…" : "Submit") { submit() }
                        .disabled(submitting || reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func submit() {
        submitting = true
        Task {
            do {
                try await ReportService.shared.submit(
                    targetKind: targetKind, targetId: targetId, nodeId: nodeId, reason: reason
                )
                dismiss()
            } catch {
                feedback = UserFacingError.message(for: error)
                submitting = false
            }
        }
    }
}
