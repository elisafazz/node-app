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
    @State private var showBulkImport = false
    @State private var favoritesOnly = false
    @State private var members: [NodeMember] = []
    @State private var lastRefreshed: Date = .distantPast

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    private var nodePhotos: [Photo] {
        let visible = (photos.photosByNodeId[nodeId] ?? []).filter { !blocks.isBlocked($0.authorUserId) }
        let filtered = favoritesOnly ? visible.filter(\.isFavorite) : visible
        // Pin favorites to the top; the underlying fetch already orders by created_at desc.
        return filtered.filter(\.isFavorite) + filtered.filter { !$0.isFavorite }
    }

    var body: some View {
        // No NavigationStack here -- parent NodeRootView is inside RootView's TabView NavigationStack.
        ZStack(alignment: .bottomTrailing) {
                Color.nodeBackground.ignoresSafeArea()
                if nodePhotos.isEmpty && !favoritesOnly {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        favoritesFilterBar
                        ScrollView {
                            if nodePhotos.isEmpty {
                                Text("No favorites yet. Tap the star on any photo to keep it here.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 40)
                            } else {
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
                        }
                        .refreshable { await photos.fetchPhotos(nodeId: nodeId) }
                    }
                }
                HStack {
                    bulkImportFAB
                        .padding(.leading, 20)
                    Spacer()
                    addFAB
                        .padding(.trailing, 20)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
        .navigationTitle("Gallery")
        .sheet(isPresented: $showAdd) {
            AddPhotoView(nodeId: nodeId)
        }
        .sheet(isPresented: $showBulkImport) {
            BulkImportView(nodeId: nodeId)
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

    private var favoritesFilterBar: some View {
        HStack(spacing: 8) {
            Button {
                favoritesOnly.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Favorites")
                        .font(.system(size: 13, weight: favoritesOnly ? .semibold : .regular))
                }
                .foregroundStyle(favoritesOnly ? Color.nodeBrand : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(favoritesOnly ? Color.nodeBrand.opacity(0.12) : Color.nodeSurface, in: Capsule())
                .overlay(
                    Capsule().stroke(
                        favoritesOnly ? Color.nodeBrand.opacity(0.8) : Color.clear,
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var addFAB: some View {
        Button { showAdd = true } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.nodeBrand))
                .shadow(radius: 6, y: 2)
        }
        .accessibilityLabel("Add photo")
    }

    private var bulkImportFAB: some View {
        Button { showBulkImport = true } label: {
            Image(systemName: "photo.stack.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.nodeBrand)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.nodeSurface))
                .shadow(radius: 4, y: 2)
        }
        .accessibilityLabel("Add multiple photos")
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
