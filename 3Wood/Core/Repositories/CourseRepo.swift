import Foundation
import Supabase

enum CourseRepo {
    static func search(_ query: String) async throws -> [Course] {
        try await supa.rpc("search_courses", params: ["p_query": query])
            .execute()
            .value
    }

    static func inRegion(minLat: Double, minLng: Double, maxLat: Double, maxLng: Double) async throws -> [Course] {
        try await supa.rpc("courses_in_region", params: [
            "min_lat": minLat,
            "min_lng": minLng,
            "max_lat": maxLat,
            "max_lng": maxLng,
        ])
        .execute()
        .value
    }

    static func course(id: Int) async throws -> Course? {
        let rows: [Course] = try await supa.rpc("course_by_id", params: ["p_id": id])
            .execute()
            .value
        return rows.first
    }

    /// Bounding box of a state's courses, for recentering the map.
    static func stateRegion(_ state: String) async throws -> Region? {
        let rows: [Region] = try await supa.rpc("state_region", params: ["p_state": state])
            .execute()
            .value
        guard let r = rows.first, r.minLat != nil else { return nil }
        return r
    }
}

struct Region: Decodable, Sendable {
    let minLat: Double?
    let minLng: Double?
    let maxLat: Double?
    let maxLng: Double?

    enum CodingKeys: String, CodingKey {
        case minLat = "min_lat"
        case minLng = "min_lng"
        case maxLat = "max_lat"
        case maxLng = "max_lng"
    }
}
