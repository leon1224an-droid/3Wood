import Foundation
import CoreLocation

/// A golf course as returned by the search/map RPCs, including community
/// rating columns (null until users have ranked it).
struct Course: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let city: String?
    let state: String?
    let latitude: Double
    let longitude: Double
    let holes: Int?
    let courseType: String?
    let avgScore: Double?
    let ratingCount: Int

    enum CodingKeys: String, CodingKey {
        case id, name, city, state, latitude, longitude, holes
        case courseType = "course_type"
        case avgScore = "avg_score"
        case ratingCount = "rating_count"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// "Pebble Beach, CA" — or whichever parts exist.
    var locationText: String {
        [city, state].compactMap(\.self).joined(separator: ", ")
    }

    /// A short access-type label for row tags, e.g. "public/municipal" → "Public".
    var shortType: String? {
        guard let type = courseType, !type.isEmpty else { return nil }
        let primary = type.split(separator: "/").first.map(String.init) ?? type
        return primary.capitalized
    }
}
