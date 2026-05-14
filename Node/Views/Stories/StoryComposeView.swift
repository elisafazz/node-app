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

// MARK: - Embedded camera (ported from Sunzzari S62 / Miracles S9)

/// Instagram-style in-app camera. Renders a fullscreen AVCaptureSession live
/// preview with a shutter button, library thumbnail, flip-camera button,
/// and close (X). Handles video permission and gracefully falls back to the
/// library-only UI when access is denied or the device has no camera.
struct CameraCaptureView: View {
    let onCapture: (UIImage) -> Void
    let onPickFromLibrary: () -> Void
    let onClose: () -> Void

    @StateObject private var model = CameraCaptureModel()

    @State private var baseZoom: CGFloat = 1.0
    @State private var currentZoom: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.permissionGranted {
                CameraPreviewLayer(session: model.session)
                    .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let target = baseZoom * value
                                currentZoom = model.setZoom(target)
                            }
                            .onEnded { _ in
                                baseZoom = currentZoom
                            }
                    )

                if currentZoom > 1.05 {
                    Text(String(format: "%.1fx", currentZoom))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 130)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                }
            } else if model.permissionDenied {
                permissionDeniedView
            }

            VStack {
                topRow
                Spacer()
                bottomRow
            }
        }
        .task { await model.setup() }
        .onDisappear { model.teardown() }
        .onChange(of: model.capturedImage) { _, newValue in
            if let img = newValue {
                let cropped = img.croppedToAspectRatio(of: UIScreen.main.bounds.size)
                onCapture(cropped)
                model.capturedImage = nil
            }
        }
    }

    private var topRow: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            if model.permissionGranted {
                Button { model.flipCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Flip camera")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomRow: some View {
        HStack {
            Button(action: onPickFromLibrary) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 0.5))
            }
            .accessibilityLabel("Choose from library")

            Spacer()

            if model.permissionGranted {
                Button { model.capture() } label: {
                    ZStack {
                        Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                        Circle().fill(Color.white).frame(width: 62, height: 62)
                    }
                }
                .accessibilityLabel("Take photo")
            } else {
                Spacer().frame(width: 76, height: 76)
            }

            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera access needed")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Enable Camera in Settings to take a photo, or pick one from your library.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }
}

@MainActor
final class CameraCaptureModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var permissionGranted = false
    @Published var permissionDenied = false
    @Published var capturedImage: UIImage?

    private let sessionQueue = DispatchQueue(label: "node.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back

    func setup() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            configureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
            permissionDenied = !granted
            if granted { configureSession() }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    func teardown() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        sessionQueue.async { [photoOutput, weak self] in
            guard let self else { return }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    @discardableResult
    func setZoom(_ factor: CGFloat) -> CGFloat {
        guard let device = videoInput?.device else { return 1.0 }
        let maxFactor = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let clamped = max(1.0, min(maxFactor, factor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            return device.videoZoomFactor
        }
        return clamped
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            if let current = self.videoInput { self.session.removeInput(current) }
            let newPosition: AVCaptureDevice.Position = (self.position == .back) ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                if let prev = self.videoInput, self.session.canAddInput(prev) { self.session.addInput(prev) }
                return
            }
            self.session.addInput(input)
            self.videoInput = input
            self.position = newPosition
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.videoInput = input
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }
}

extension CameraCaptureModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        let oriented = image.normalizedOrientation()
        Task { @MainActor in self.capturedImage = oriented }
    }
}

struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

extension UIImage {
    func croppedToAspectRatio(of target: CGSize) -> UIImage {
        guard let cg = cgImage, target.width > 0, target.height > 0 else { return self }
        let pixelWidth = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)
        let targetAR = target.width / target.height
        let imageAR = pixelWidth / pixelHeight
        let cropPixelRect: CGRect
        if imageAR > targetAR {
            let newWidth = pixelHeight * targetAR
            cropPixelRect = CGRect(x: (pixelWidth - newWidth) / 2, y: 0, width: newWidth, height: pixelHeight)
        } else {
            let newHeight = pixelWidth / targetAR
            cropPixelRect = CGRect(x: 0, y: (pixelHeight - newHeight) / 2, width: pixelWidth, height: newHeight)
        }
        guard let cropped = cg.cropping(to: cropPixelRect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
