import SwiftUI

struct EditPhotoView: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss
    @State private var caption: String
    @State private var tag: String
    @State private var saving = false
    @State private var error: String?

    init(photo: Photo) {
        self.photo = photo
        _caption = State(initialValue: photo.caption ?? "")
        _tag = State(initialValue: photo.tag ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Caption") {
                    TextField("Caption", text: $caption, axis: .vertical).lineLimit(1...4)
                }
                Section("Tag") {
                    TextField("Tag", text: $tag)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Edit photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        do {
            try await PhotoService.shared.updatePhoto(
                photo,
                caption: caption.trimmingCharacters(in: .whitespaces).isEmpty ? nil : caption,
                tag: tag.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tag
            )
            dismiss()
        } catch {
            self.error = UserFacingError.message(for: error)
        }
        saving = false
    }
}
