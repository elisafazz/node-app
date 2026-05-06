import SwiftUI

/// Archive of all past stories for one node, grouped by year then by day. Tap a thumbnail to open the player for that single story.
struct StoryArchiveView: View {
    let nodeId: UUID
    let authors: [NodeMember]
    @Environment(StoryService.self) private var stories
    @Environment(BlockService.self) private var blocks

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var loadingYears: Set<Int> = []
    @State private var openedStory: Story?

    private static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private var availableYears: [Int] {
        let nowYear = Calendar.current.component(.year, from: Date())
        return Array((nowYear - 4)...nowYear).reversed()
    }

    private var key: String { "\(nodeId.uuidString)-\(selectedYear)" }
    private var yearStories: [Story] {
        (stories.archiveByNodeIdYear[key] ?? []).filter { !blocks.isBlocked($0.authorUserId) }
    }

    private var byDay: [(date: Date, stories: [Story])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: yearStories) { cal.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { day in (day, groups[day] ?? []) }
    }

    private func authorFor(_ userId: UUID) -> NodeMember? {
        authors.first { $0.user.id == userId }
    }

    var body: some View {
        ZStack {
            Color.nodeBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    yearPicker
                    if loadingYears.contains(selectedYear) && yearStories.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if yearStories.isEmpty {
                        Text("No stories archived for \(String(selectedYear)).")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(byDay, id: \.date) { day in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(Self.dayHeader.string(from: day.date))
                                    .font(.headline)
                                    .padding(.horizontal, 16)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                    ForEach(day.stories) { story in
                                        Button { openedStory = story } label: {
                                            ZStack(alignment: .bottomLeading) {
                                                AsyncImage(url: story.thumbnailURL) { phase in
                                                    switch phase {
                                                    case .success(let img): img.resizable().scaledToFill()
                                                    default: Color.nodeSurface
                                                    }
                                                }
                                                .frame(height: 120).clipped()
                                                if let author = authorFor(story.authorUserId) {
                                                    Text(author.emoji ?? String(author.displayName.prefix(1)))
                                                        .font(.caption2)
                                                        .foregroundStyle(.white)
                                                        .padding(4)
                                                        .background(Color.black.opacity(0.4))
                                                        .clipShape(Capsule())
                                                        .padding(4)
                                                }
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .task { await ensureYearLoaded(selectedYear) }
        .onChange(of: selectedYear) { _, year in
            Task { await ensureYearLoaded(year) }
        }
        .fullScreenCover(item: $openedStory) { story in
            singleStoryPlayer(story: story)
        }
    }

    private var yearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableYears, id: \.self) { year in
                    Button { selectedYear = year } label: {
                        Text(String(year))
                            .font(.subheadline.weight(selectedYear == year ? .semibold : .regular))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selectedYear == year ? Color.nodeAccent : Color.nodeSurface)
                            .foregroundStyle(selectedYear == year ? Color.white : Color.nodeText)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func ensureYearLoaded(_ year: Int) async {
        guard !loadingYears.contains(year), yearStories.isEmpty else { return }
        loadingYears.insert(year)
        await stories.fetchArchive(nodeId: nodeId, year: year)
        loadingYears.remove(year)
    }

    @ViewBuilder
    private func singleStoryPlayer(story: Story) -> some View {
        if let author = authorFor(story.authorUserId) {
            StoryPlayerView(
                stories: [story],
                author: author,
                onDismiss: { openedStory = nil }
            )
        } else {
            // Fallback if author membership is missing -- still show the photo
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: story.fullURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    default: ProgressView().tint(.white)
                    }
                }
                Button { openedStory = nil } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .foregroundStyle(.white)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }
}
