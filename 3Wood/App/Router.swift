import SwiftUI

/// One case per pushable screen. Every push inside a tab's NavigationStack
/// goes through this single registry — screens deep in a chain (course →
/// profile → course …) were previously pushed with navigationDestination(item:)
/// bindings scattered across views, which broke once chains nested: pushes
/// got swallowed and the back button popped out of sync.
enum Destination: Hashable {
    case course(Course)
    case courseID(Int)
    case person(ProfileSummary)
    case people(userID: UUID, mode: PeopleListView.Mode)
    case leaderboard
    case activity(FeedItem)
    case activityID(Int)
    case notifications
    case findFriends
    case contacts
    case about
    case list(CustomList)
    case listID(Int)
    case exploreLists

    /// Destinations that render the same screen share a key (a course pushed
    /// as a full Course vs just its id), so Router.push can collapse cycles.
    var dedupeKey: String {
        switch self {
        case .course(let course): "course-\(course.id)"
        case .courseID(let id): "course-\(id)"
        case .person(let person): "person-\(person.id)"
        case .people(let userID, let mode): "people-\(userID)-\(mode)"
        case .leaderboard: "leaderboard"
        case .activity(let item): "activity-\(item.activityID)"
        case .activityID(let id): "activity-\(id)"
        case .notifications: "notifications"
        case .findFriends: "findFriends"
        case .contacts: "contacts"
        case .about: "about"
        case .list(let list): "list-\(list.id)"
        case .listID(let id): "list-\(id)"
        case .exploreLists: "exploreLists"
        }
    }
}

/// The navigation path of one tab's NavigationStack. Injected into the
/// environment at each stack root; any descendant pushes programmatically via
/// push(_:) (rows with two tap targets) or declaratively via
/// NavigationLink(value: Destination...).
@Observable
@MainActor
final class Router {
    var path: [Destination] = []

    /// Push — unless the screen is already somewhere in the stack, in which
    /// case pop back to it. Going course → profile → same course collapses to
    /// the original course instead of stacking an endless chain.
    func push(_ destination: Destination) {
        if let existing = path.lastIndex(where: { $0.dedupeKey == destination.dedupeKey }) {
            path.removeSubrange(path.index(after: existing)...)
        } else {
            path.append(destination)
        }
    }

    func popToRoot() {
        path.removeAll()
    }
}

extension View {
    /// Registers every Destination. Applied once at each NavigationStack root.
    func appDestinations() -> some View {
        navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .course(let course): CourseDetailView(course: course)
            case .courseID(let id): CourseDetailByID(courseID: id)
            case .person(let person): OtherProfileView(person: person)
            case .people(let userID, let mode): PeopleListView(userID: userID, mode: mode)
            case .leaderboard: LeaderboardView()
            case .activity(let item): ActivityDetailView(item: item)
            case .activityID(let id): ActivityDetailByID(activityID: id)
            case .notifications: NotificationsView()
            case .findFriends: FindFriendsView()
            case .contacts: ContactsMatchView()
            case .about: AboutView()
            case .list(let list): ListDetailView(list: list)
            case .listID(let id): ListDetailByID(listID: id)
            case .exploreLists: ExploreListsView()
            }
        }
    }
}
