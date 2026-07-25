import Foundation

/// Invitation links point at the public landing page with a ?ref= tag so the
/// page can greet the invitee (and referrals can be attributed later).
enum Invite {
    static let landingPage = URL(string: "https://leon1224an-droid.github.io/3Wood/")!

    static func link(from username: String?) -> URL {
        guard let username,
              var components = URLComponents(url: landingPage, resolvingAgainstBaseURL: false)
        else { return landingPage }
        components.queryItems = [URLQueryItem(name: "ref", value: username)]
        return components.url ?? landingPage
    }

    static func message(from username: String?) -> String {
        "Golf is meant to be shared — join me on 3Wood so we can compare course rankings. \(link(from: username).absoluteString)"
    }
}
