import SwiftUI

/// Cross-tab navigation: lets one tab send the user to another (e.g. Profile's
/// "Courses played" row opens the Lists tab on the Played segment).
@Observable
@MainActor
final class AppNavigation {
    enum Tab: Hashable {
        case feed, search, map, lists, profile
    }

    var selectedTab: Tab = .feed
    var listsSegment: ListsView.Segment = .played

    func showLists(_ segment: ListsView.Segment) {
        listsSegment = segment
        selectedTab = .lists
    }
}
