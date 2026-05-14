import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// Camera-first compose view with cross-node posting (ADR-012).
/// Pass a defaultNodeId to pre-select one node; nil pre-selects all nodes (Hub flow).
struct StoryComposeView: View {
    let defaultNodeId: UUID?
    let onPosted: ((Story) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(NodeService.self) private var nodes

    init(defaultNodeId: UUID? = nil, onPosted: ((Story) -> Void)? = nil) {
        self.defaultNodeId = defaultNodeId
        self.onPosted = onPosted
    }

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var caption: String = ""
    @State private var location: String = ""
    @State private var selectedNodeIds: Set<UUID> = []
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showSourceChoice = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var didAutoLaunchCamera = false
    // Cached publicID for retry: if Cloudinary upload succeeded but the
    // subsequent createStory RPC failed, hold the publicID so a retry does
    // not re-upload (which would orphan the first asset in Cloudinary).
    @State private var lastUploadedPublicID: String?

    // Caption preview overlay placement. Starts at .bottomLeading anchor
    // (offset 0,0). User can drag to reposition; offset is clamped on drag
    // end so the rendered text stays inside the photo's frame.
    @State private var captionOffset: CGSize = .zero
    @State private var captionDragInProgress: CGSize = .zero

    private static let photoHeight: CGFloat = 480
    // Conservative drag clamps -- text wider than the bounds just hits the
    // wall, much better than letting the caption render off the photo.
    private static let captionDragMaxX: CGFloat = 100
    private static let captionDragMaxY: CGFloat = 400

    var body: some View {
        NavigationStack {
            ZStack {
                Color.nodeBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        photoArea
                        if image != nil {
                            captionField
                            locationField
                            nodeSelector
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
                            .disabled(image == nil || selectedNodeIds.isEmpty)
                    }
                }
            }
            .task {
                // Initialize selected nodes once the node list is available.
                if selectedNodeIds.isEmpty {
                    if let defaultNodeId, nodes.myNodes.contains(where: { $0.id == defaultNodeId }) {
                        selectedNodeIds = [defaultNodeId]
                    } else {
                        selectedNodeIds = Set(nodes.myNodes.map(\.id))
                    }
                }
                await maybeAutoLaunchCamera()
            }
        }
    }

    // MARK: - Photo area

    private var photoArea: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.photoHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottomLeading) { captionPreviewOverlay }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            self.image = nil
                            self.pickerItem = nil
                            self.captionOffset = .zero
                            self.captionDragInProgress = .zero
                            self.lastUploadedPublicID = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Remove photo")
                        .padding(10)
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
                    .frame(height: Self.photoHeight)
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

    /// Live caption preview rendered on the photo. Anchored bottom-leading so
    /// offset 0,0 = anchor position. User can drag to reposition; offsets are
    /// clamped on drag end so the rendered text stays inside the photo's frame.
    /// At upload time the caption is BAKED into the JPEG via ImageRenderer so
    /// every viewer sees it at the exact dragged position.
    @ViewBuilder
    private var captionPreviewOverlay: some View {
        if !caption.isEmpty {
            Text(caption)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(16)
                .offset(
                    x: captionOffset.width + captionDragInProgress.width,
                    y: captionOffset.height + captionDragInProgress.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            captionDragInProgress = value.translation
                        }
                        .onEnded { value in
                            let newX = captionOffset.width + value.translation.width
                            let newY = captionOffset.height + value.translation.height
                            captionOffset.width = max(-Self.captionDragMaxX, min(Self.captionDragMaxX, newX))
                            captionOffset.height = max(-Self.captionDragMaxY, min(0, newY))
                            captionDragInProgress = .zero
                        }
                )
        }
    }

    // MARK: - Caption

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

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Where (optional)", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("Sunset Park", text: $location)
                .padding(12)
                .background(Color.nodeSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Node selector

    private var nodeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Post to", systemImage: "circle.hexagongrid")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            if nodes.myNodes.count <= 1 {
                // Single-node: nothing to pick, just show which node
                if let node = nodes.myNodes.first {
                    nodePill(node, forced: true)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(nodes.myNodes) { node in
                            nodePill(node, forced: false)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func nodePill(_ node: NodeRecord, forced: Bool) -> some View {
        let isSelected = selectedNodeIds.contains(node.id)
        let m = nodes.myMembershipsByNodeId[node.id]
        let label = m?.perNodeDisplayName ?? node.name
        return Button {
            if forced { return }
            // Prevent deselecting the last selected node
            if isSelected && selectedNodeIds.count == 1 { return }
            if isSelected {
                selectedNodeIds.remove(node.id)
            } else {
                selectedNodeIds.insert(node.id)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : Color.nodeBrand)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.nodeBrand : Color.nodeSurface,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(Color.nodeBrand.opacity(isSelected ? 0 : 0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Helpers

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                // Downsample large Photos library assets (up to 48MP on newer
                // iPhones) before holding them in memory. Without this the
                // compose sheet can OOM-crash on older devices the moment a
                // Pro photo is selected. 1080x1920 is the maximum resolution
                // Cloudinary will serve from an active story.
                let target = CGSize(width: 1080, height: 1920)
                let downsized = img.preparingThumbnail(of: target) ?? img
                self.image = downsized
                self.errorMessage = nil
                self.lastUploadedPublicID = nil
            } else {
                self.pickerItem = nil
                self.errorMessage = "Couldn't load that photo. Try another."
            }
        } catch {
            self.pickerItem = nil
            self.errorMessage = "Couldn't load that photo. Try another."
        }
    }

    private func maybeAutoLaunchCamera() async {
        // Camera-first compose: open camera as soon as the sheet appears.
        // Permission gate avoids the black-screen UX on denied access.
        guard !didAutoLaunchCamera,
              image == nil,
              UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        didAutoLaunchCamera = true

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { showCamera = true }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    private func post() async {
        guard let originalImage = image else { return }
        guard !selectedNodeIds.isEmpty else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            // Bake the user's caption at its dragged position into the upload.
            // If we have a cached publicID from a previous attempt that failed
            // post-upload, skip the upload to avoid orphaning the prior asset.
            let imageToUpload = bakeCaptionIntoImage() ?? originalImage

            let publicId: String
            if let cached = lastUploadedPublicID {
                publicId = cached
            } else {
                publicId = try await CloudinaryService.shared.upload(image: imageToUpload, kind: .story)
                lastUploadedPublicID = publicId
            }

            // When the caption was baked into the image, pass nil to the service
            // so the player's overlay does not double-render text on top of the
            // baked text. If bakeCaptionIntoImage returned nil (empty caption)
            // we send nil regardless. The push body still uses trimmedCaption
            // for the notification preview.
            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            let story = try await StoryService.shared.createStory(
                nodeIds: Array(selectedNodeIds),
                cloudinaryPublicId: publicId,
                caption: nil,
                location: trimmedLocation.isEmpty ? nil : trimmedLocation,
                originNodeId: defaultNodeId
            )
            lastUploadedPublicID = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onPosted?(story)
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// Render the photo + caption preview at the user's dragged position into
    /// a single UIImage at upload time. ImageRenderer maps the SwiftUI preview
    /// 1:1 onto the baked output -- gesture state is the source of truth, no
    /// CoreGraphics math required. Returns nil if there's nothing to bake
    /// (no image OR empty caption -- in the empty-caption case the caller
    /// just uploads the original).
    @MainActor
    private func bakeCaptionIntoImage() -> UIImage? {
        guard let originalImage = image else { return nil }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let displayWidth = UIScreen.main.bounds.width - 40
        let displayHeight = Self.photoHeight

        let composed = ZStack(alignment: .bottomLeading) {
            Image(uiImage: originalImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: displayWidth, height: displayHeight)
                .clipped()

            Text(caption)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(16)
                .offset(x: captionOffset.width, y: captionOffset.height)
        }
        .frame(width: displayWidth, height: displayHeight)

        let renderer = ImageRenderer(content: composed)
        renderer.scale = 3
        return renderer.uiImage
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
            let img = info[.originalImage] as? UIImage
            parent.onCaptured(img)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCaptured(nil)
            parent.dismiss()
        }
    }
}
