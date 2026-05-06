import SwiftUI
import PhotosUI
import UIKit

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
    @State private var selectedNodeIds: Set<UUID> = []
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showSourceChoice = false
    @State private var showCamera = false
    @State private var showLibrary = false
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
                // Camera-first: open camera automatically on first appearance if available.
                guard !didAutoLaunchCamera,
                      image == nil,
                      UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                didAutoLaunchCamera = true
                showCamera = true
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
                        .accessibilityLabel("Remove photo")
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
        guard let image else { return }
        guard !selectedNodeIds.isEmpty else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }

        do {
            let publicId = try await CloudinaryService.shared.upload(image: image, kind: .story)
            let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let story = try await StoryService.shared.createStory(
                nodeIds: Array(selectedNodeIds),
                cloudinaryPublicId: publicId,
                caption: trimmedCaption.isEmpty ? nil : trimmedCaption,
                originNodeId: defaultNodeId
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
