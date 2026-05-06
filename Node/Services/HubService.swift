import Foundation

/// Aggregates cross-node data for the Network Hub home screen.
/// Delegates story fetching to StoryService; extended in Phase C/D for Boops and Meetings.
@MainActor
@Observable
final class HubService {
    static let shared = HubService()

    var allVisibleStories: [Story] { StoryService.shared.allVisible }
    private(set) var lastError: String?

    func refresh() async {
        await StoryService.shared.fetchAllVisible()
    }
}
