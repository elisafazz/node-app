import SwiftUI
import PhotosUI
import UIKit

/// Ported from Miracles `StoryComposeView`. PhotosPicker -> Cloudinary upload -> Supabase insert -> push fan-out.
struct StoryComposeView: View {
    let nodeId: UUID
    let onPosted: ((Story) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    init(nodeId: UUID, onPosted: ((Story) -> Void)? = nil) {
        self.nodeId = nodeId
        self.onPosted = onPosted
    }

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var caption: String = ""
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nodeBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        photoArea
                        if image != nil {
                            captionField
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await post() } }
                            .fontWeight(.semibold)
                            .disabled(image == nil)
                    }
                }
            }
        }
    }

    private var photoArea: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 480)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            self.image = nil
                            self.pickerItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .padding(10)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if !caption.isEmpty {
                            Text(caption)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Capsule())
                                .padding(16)
                        }
                    }
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.nodeAccent)
                        Text("Pick a photo").font(.headline)
                        if let displayName = auth.profile?.displayName {
                            Text("Posting as \(displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .background(Color.nodeSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .onChange(of: pickerItem) { _, newItem in
                    Task { await loadPicked(newItem) }
                }
            }
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Caption", systemImage: "text.bubble")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Say something...", text: $caption, axis: .vertical)
                .lineLimit(1...4)
                .padding(12)
                .background(Color.nodeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                self.image = img
                self.errorMessage = nil
            } else {
                self.pickerItem = nil
                self.errorMessage = "Couldn't load that photo. Try another."
            }
        } catch {
            self.pickerItem = nil
            self.errorMessage = "Couldn't load that photo. Try another."
        }
    }

    private func post() async {
        guard let image, let me = auth.session?.user.id else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            let publicId = try await CloudinaryService.shared.upload(image: image, kind: .story, nodeId: nodeId)
            let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let story = try await StoryService.shared.createStory(
                nodeId: nodeId,
                authorUserId: me,
                cloudinaryPublicId: publicId,
                caption: trimmedCaption.isEmpty ? nil : trimmedCaption
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onPosted?(story)
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
