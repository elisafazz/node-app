import SwiftUI

/// Compact thumbnail for the Hub recent activity carousel.
struct StoryThumbnailCell: View {
    let story: Story

    var body: some View {
        AsyncImage(url: story.thumbnailURL) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            default:
                Color.nodeSurface
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(Color.nodeText.opacity(0.3))
                    )
            }
        }
        .frame(width: 88, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.nodeSurface, lineWidth: 1)
        )
    }
}
