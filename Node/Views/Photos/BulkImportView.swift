import SwiftUI
import PhotosUI

/// Multi-photo import for one node. PhotosPicker selects up to 50 images,
/// then they upload concurrently (3 at a time) so a 30-photo dump finishes in
/// well under the user's patience window. Each photo flows through the same
/// Cloudinary signed-upload path AddPhotoView uses, so RLS / membership
/// checks behave identically.
struct BulkImportView: View {
    let nodeId: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var uploadStates: [UploadState] = []
    @State private var isUploading = false
    @State private var isDone = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nodeBackground.ignoresSafeArea()
                if uploadStates.isEmpty {
                    pickerPrompt
                } else {
                    progressList
                }
            }
            .navigationTitle("Add multiple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isUploading { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    private var pickerPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.nodeAccent)
            Text("Add multiple photos")
                .font(.title2.weight(.semibold))
            Text("Pick up to 50 photos and they'll all upload to this node automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 50,
                matching: .images
            ) {
                Label("Choose photos", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.nodeBrand, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
            }
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                uploadStates = items.map { UploadState(item: $0) }
                Task { await uploadAll() }
            }
            Spacer()
        }
    }

    private var progressList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Uploading \(uploadStates.count) photos").font(.headline)
                            Text("\(doneCount) of \(uploadStates.count) complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                        }
                    }
                    .padding(16)
                    .background(Color.nodeSurface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(16)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.nodeSurface).frame(height: 6)
                            RoundedRectangle(cornerRadius: 4).fill(Color.nodeBrand)
                                .frame(width: geo.size.width * progress, height: 6)
                                .animation(.easeInOut, value: progress)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    LazyVStack(spacing: 8) {
                        ForEach(uploadStates.indices, id: \.self) { i in
                            UploadRow(state: uploadStates[i], index: i + 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            if isDone {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.nodeBrand, in: RoundedRectangle(cornerRadius: 14))
                        .padding(16)
                }
            }
        }
    }

    private var doneCount: Int {
        uploadStates.filter { $0.status == .done || $0.status == .failed }.count
    }

    private var progress: CGFloat {
        guard !uploadStates.isEmpty else { return 0 }
        return CGFloat(doneCount) / CGFloat(uploadStates.count)
    }

    private func uploadAll() async {
        guard auth.session?.user.id != nil else { return }
        isUploading = true
        // Concurrent up to 3 at a time -- protects against Cloudinary rate
        // limits and avoids saturating the user's uplink on a 30-photo batch.
        await withTaskGroup(of: Void.self) { group in
            var active = 0
            for i in uploadStates.indices {
                if active >= 3 {
                    await group.next()
                    active -= 1
                }
                group.addTask { await uploadOne(index: i) }
                active += 1
            }
        }
        isUploading = false
        isDone = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func uploadOne(index: Int) async {
        await MainActor.run { uploadStates[index].status = .uploading }
        guard let data = try? await uploadStates[index].item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            await MainActor.run { uploadStates[index].status = .failed }
            return
        }
        // Downsample large assets before upload for the same OOM-safety reasons
        // as the story composer.
        let target = CGSize(width: 1920, height: 1920)
        let downsized = image.preparingThumbnail(of: target) ?? image
        do {
            guard let me = auth.session?.user.id else {
                await MainActor.run { uploadStates[index].status = .failed }
                return
            }
            let publicId = try await CloudinaryService.shared.upload(image: downsized, kind: .photo, nodeId: nodeId)
            _ = try await PhotoService.shared.createPhoto(
                nodeId: nodeId,
                authorUserId: me,
                cloudinaryPublicId: publicId,
                caption: nil,
                tag: nil
            )
            await MainActor.run { uploadStates[index].status = .done }
        } catch {
            await MainActor.run { uploadStates[index].status = .failed }
        }
    }
}

struct UploadState: Identifiable {
    let id = UUID()
    let item: PhotosPickerItem
    var status: Status = .pending

    enum Status: Equatable { case pending, uploading, done, failed }
}

private struct UploadRow: View {
    let state: UploadState
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch state.status {
                case .pending:
                    Image(systemName: "circle").foregroundStyle(.secondary)
                case .uploading:
                    ProgressView().scaleEffect(0.8)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 24)
            Text("Photo \(index)").font(.subheadline)
            Spacer()
            Text(state.status.label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.nodeSurface, in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension UploadState.Status {
    var label: String {
        switch self {
        case .pending:   return "Waiting"
        case .uploading: return "Uploading..."
        case .done:      return "Saved"
        case .failed:    return "Failed"
        }
    }
}
