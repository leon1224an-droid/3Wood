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
}
