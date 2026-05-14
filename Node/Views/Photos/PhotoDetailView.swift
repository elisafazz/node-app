import SwiftUI

struct PhotoDetailView: View {
    let photo: Photo
    let members: [NodeMember]
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @State private var showEdit = false
    @State private var showReport = false
    @State private var showBlockConfirm = false
    @State private var deleteConfirm = false
    @State private var deleteError: String?
    @State private var imageLoadId = UUID()
    @State private var isLoadingShare = false

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
                            case .failure:
                                VStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text("Couldn't load")
                                    Button("Retry") { imageLoadId = UUID() }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.white)
                                }
                                .foregroundStyle(.white)
                                .frame(height: 400)
                                .frame(maxWidth: .infinity)
                            @unknown default: EmptyView()
                            }
                        }
                        .id(imageLoadId)

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
                    HStack(spacing: 14) {
                        if isMyPhoto {
                            Button {
                                Task {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    try? await PhotoService.shared.toggleFavorite(photo)
                                }
                            } label: {
                                Image(systemName: photo.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(photo.isFavorite ? .yellow : .white)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: photo.isFavorite)
                            }
                            .accessibilityLabel(photo.isFavorite ? "Unfavorite photo" : "Favorite photo")
                        }
                        Button { Task { await shareImage() } } label: {
                            if isLoadingShare {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.up").foregroundStyle(.white)
                            }
                        }
                        .accessibilityLabel("Share photo")
                        Menu {
                            if isMyPhoto {
                                Button("Edit", systemImage: "pencil") { showEdit = true }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirm = true }
                            } else {
                                Button("Report", systemImage: "flag") { showReport = true }
                                if let author {
                                    Button("Block \(author.displayName)", systemImage: "person.slash", role: .destructive) { showBlockConfirm = true }
                                }
                            }
                        } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.white) }
                    }
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
                        do {
                            try await PhotoService.shared.deletePhoto(photo)
                            dismiss()
                        } catch {
                            deleteError = UserFacingError.message(for: error)
                        }
                    }
                }
            }
            .alert("Couldn't delete photo", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            .confirmationDialog(
                author.map { "Block \($0.displayName)?" } ?? "",
                isPresented: $showBlockConfirm,
                titleVisibility: .visible
            ) {
                Button("Block", role: .destructive) {
                    if let author {
                        Task {
                            try? await BlockService.shared.block(userId: author.user.id)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their content will be hidden across every node you share. They won't be notified.")
            }
        }
    }

    /// Download the full-size Cloudinary image and present the system share
    /// sheet. iOS handles the actual sharing surface (Messages, AirDrop, save
    /// to Photos, etc.) so we don't have to build a per-channel UI.
    private func shareImage() async {
        guard let url = photo.fullURL else { return }
        isLoadingShare = true
        defer { isLoadingShare = false }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        await MainActor.run {
            let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            var top = root
            while let presented = top.presentedViewController { top = presented }
            vc.popoverPresentationController?.sourceView = top.view
            top.present(vc, animated: true)
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
