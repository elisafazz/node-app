import SwiftUI
import PhotosUI
import UIKit

struct AddPhotoView: View {
    let nodeId: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var caption = ""
    @State private var tag = ""
    @State private var isUploading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    if let image {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            if isUploading {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.45))
                                    .frame(maxHeight: 280)
                                    .overlay(ProgressView().tint(.white).scaleEffect(1.4))
                            }
                        }
                        if !isUploading {
                            Button("Replace photo") { pickerItem = nil; self.image = nil }
                        }
                    } else {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Pick a photo", systemImage: "photo.badge.plus")
                        }
                    }
                }
                if image != nil {
                    Section("Caption (optional)") {
                        TextField("Say something about this photo", text: $caption, axis: .vertical)
                            .lineLimit(1...4)
                    }
                    Section("Tag (optional)") {
                        TextField("e.g. Funny, Sweet, Memorable", text: $tag)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Add photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isUploading {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(image == nil)
                    }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                Task { await loadPicked(newItem) }
            }
        }
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                self.image = img
                self.error = nil
            } else {
                self.error = "Couldn't load that photo. Try another."
            }
        } catch {
            self.error = "Couldn't load that photo. Try another."
        }
    }

    private func save() async {
        guard let image, let me = auth.session?.user.id else { return }
        isUploading = true
        error = nil
        defer { isUploading = false }
        do {
            let publicId = try await CloudinaryService.shared.upload(image: image, kind: .photo, nodeId: nodeId)
            _ = try await PhotoService.shared.createPhoto(
                nodeId: nodeId,
                authorUserId: me,
                cloudinaryPublicId: publicId,
                caption: caption.trimmingCharacters(in: .whitespaces).isEmpty ? nil : caption,
                tag: tag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tag
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            self.error = UserFacingError.message(for: error)
        }
    }
}
