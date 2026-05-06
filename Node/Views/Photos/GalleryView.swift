import SwiftUI

/// Per-node photo gallery. Grid of thumbnails, tap for full detail, FAB to add.
/// Pull-to-refresh + scenePhase foreground refresh.
struct GalleryView: View {
    let nodeId: UUID
    @Environment(PhotoService.self) private var photos
    @Environment(BlockService.self) private var blocks
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedPhoto: Photo?
    @State private var showAdd = false
    @State private var members: [NodeMember] = []
    @State private var lastRefreshed: Date = .distantPast

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    private var nodePhotos: [Photo] {
        (photos.photosByNodeId[nodeId] ?? []).filter { !blocks.isBlocked($0.authorUserId) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Color.nodeBackground.ignoresSafeArea()
                if nodePhotos.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(nodePhotos) { photo in
                                Button { selectedPhoto = photo } label: {
                                    GalleryCell(photo: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                    }
                    .refreshable { await photos.fetchPhotos(nodeId: nodeId) }
                }
                addFAB
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Gallery")
        }
        .sheet(isPresented: $showAdd) {
            AddPhotoView(nodeId: nodeId)
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, members: members)
        }
        .task {
            await photos.fetchPhotos(nodeId: nodeId)
            members = (try? await NodeService.shared.members(of: nodeId)) ?? []
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Debounce: skip if we refreshed within the last 30 seconds.
            guard Date().timeIntervalSince(lastRefreshed) > 30 else { return }
            // Skip background refresh on expensive (cellular/constrained) connections.
            guard !NetworkMonitor.shared.isExpensive else { return }
            lastRefreshed = Date()
            Task { await photos.fetchPhotos(nodeId: nodeId) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No photos yet").font(.headline)
            Text("Tap the + below to add the first photo to this node.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var addFAB: some View {
        Button { showAdd = true } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.nodeAccent))
                .shadow(radius: 6, y: 2)
        }
    }
}

private struct GalleryCell: View {
    let photo: Photo
    var body: some View {
        AsyncImage(url: photo.thumbnailURL) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFill()
            case .empty: Color.nodeSurface
            case .failure: Image(systemName: "photo").foregroundStyle(.secondary)
            @unknown default: Color.nodeSurface
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if let tag = photo.tag, !tag.isEmpty {
                Text(tag)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .padding(4)
            }
        }
    }
}
