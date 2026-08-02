import SwiftUI

/// Cross-tab navigation: lets one tab send the user to another (e.g. Profile's
/// "Courses played" row opens the Lists tab on the Played segment).
@Observable
@MainActor
final class AppNavigation {
    enum Tab: Hashable {
        case feed, map, lists, profile
    }

    var selectedTab: Tab = .feed
    var listsSegment: ListsView.Segment = .played

    /// One navigation path per tab, so deep chains survive tab switches and
    /// re-tapping the active tab can pop its stack to the root.
    let feedRouter = Router()
    let mapRouter = Router()
    let listsRouter = Router()
    let profileRouter = Router()

    func router(for tab: Tab) -> Router {
        switch tab {
        case .feed: feedRouter
        case .map: mapRouter
        case .lists: listsRouter
        case .profile: profileRouter
        }
    }

    func showLists(_ segment: ListsView.Segment) {
        listsSegment = segment
        selectedTab = .lists
    }
}
