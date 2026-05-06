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
    // Source-choice state. Simulator has no camera, so isSourceTypeAvailable
    // returns false there and the dialog only shows "Choose from Library".
    @State private var showSourceChoice = false
    @State private var showCamera = false
    @State private var showLibrary = false
    // One-shot guard: open the camera automatically the first time the sheet
    // appears (Snap-style camera-first compose).
    @State private var didAutoLaunchCamera = false

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
            .task {
                // Camera-first compose: open the camera as soon as the sheet
                // appears. Cancel from the camera returns to the empty
                // placeholder, where a tap gives Take Photo / Choose from Library.
                guard !didAutoLaunchCamera,
                      image == nil,
                      UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                didAutoLaunchCamera = true
                showCamera = true
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
                Button {
                    showSourceChoice = true
                } label: {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.nodeAccent)
                        Text("Add a photo").font(.headline)
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
                .confirmationDialog("Add a photo", isPresented: $showSourceChoice, titleVisibility: .hidden) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") { showCamera = true }
                    }
                    Button("Choose from Library") { showLibrary = true }
                    Button("Cancel", role: .cancel) {}
                }
                .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
                .onChange(of: pickerItem) { _, newItem in
                    Task { await loadPicked(newItem) }
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraPicker { captured in
                        if let captured {
                            self.image = captured
                            self.errorMessage = nil
                        }
                    }
                    .ignoresSafeArea()
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

/// SwiftUI wrapper for UIImagePickerController in camera mode. PhotosUI has no
/// camera-capture equivalent, so we drop down to UIKit. Closure-based instead
/// of @Binding so the caller can clear errorMessage atomically with setting
/// the image. nil = user cancelled.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCaptured: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onCaptured(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCaptured(nil)
            parent.dismiss()
        }
    }
}
