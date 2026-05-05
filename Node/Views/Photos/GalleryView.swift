import SwiftUI

/// Stub. Full implementation ports from Miracles `GalleryView.swift` in Phase 5.
struct GalleryView: View {
    let nodeId: UUID
    @Environment(PhotoService.self) private var photos = PhotoService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    let nodePhotos = photos.photosByNodeId[nodeId] ?? []
                    ForEach(nodePhotos) { photo in
                        AsyncImage(url: photo.thumbnailURL) { phase in
                            switch phase {
                            case .empty: Color.gray.opacity(0.15)
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Image(systemName: "exclamationmark.triangle")
                            @unknown default: Color.gray.opacity(0.15)
                            }
                        }
                        .frame(height: 120)
                        .clipped()
                    }
                }
                .padding(2)
            }
            .navigationTitle("Gallery")
            .refreshable { await photos.fetchPhotos(nodeId: nodeId) }
        }
    }
}
