import SwiftUI

struct NodeRootView: View {
    let node: NodeRecord
    @Environment(NodeService.self) private var nodes
    @Environment(\.dismiss) private var dismiss

    @State private var selection: NodeTab = .stories

    enum NodeTab: Hashable {
        case stories, gallery, thoughts, settings
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                Image(systemName: "circle.dotted").tag(NodeTab.stories)
                Image(systemName: "photo.on.rectangle").tag(NodeTab.gallery)
                Image(systemName: "bubble.left.and.bubble.right").tag(NodeTab.thoughts)
                Image(systemName: "gearshape").tag(NodeTab.settings)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            content
        }
        .navigationTitle(node.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await StoryService.shared.fetchActive(nodeId: node.id)
            await PhotoService.shared.fetchPhotos(nodeId: node.id)
            await ThoughtService.shared.fetchThoughts(nodeId: node.id)
        }
        .onChange(of: nodes.myNodes) { _, current in
            if !current.contains(where: { $0.id == node.id }) {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .stories:
            StoriesView(nodeId: node.id)
        case .gallery:
            GalleryView(nodeId: node.id)
        case .thoughts:
            ThoughtsView(nodeId: node.id)
        case .settings:
            NodeSettingsView(node: node)
        }
    }
}
