import SwiftUI

struct NodeRootView: View {
    let node: NodeRecord

    var body: some View {
        TabView {
            StoriesView(nodeId: node.id)
                .tabItem { Label("Stories", systemImage: "circle.dotted") }

            GalleryView(nodeId: node.id)
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }

            ThoughtsView(nodeId: node.id)
                .tabItem { Label("Thoughts", systemImage: "bubble.left.and.bubble.right") }

            NodeSettingsView(node: node)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .navigationTitle(node.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await StoryService.shared.fetchActive(nodeId: node.id)
            await PhotoService.shared.fetchPhotos(nodeId: node.id)
            await ThoughtService.shared.fetchThoughts(nodeId: node.id)
        }
    }
}
