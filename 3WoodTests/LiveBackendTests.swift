import Foundation
import Testing
@testable import ThreeWood

/// Integration tests against the local Supabase stack (`supabase start`).
/// Uses bare URLSession + the test1 account so the app's stored session is
/// never touched.
struct LiveBackendTests {
    private func accessToken() async throws -> String {
        var url = URLComponents(url: Config.supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": "test1@example.com", "password": "testpass123"])
        let (data, _) = try await URLSession.shared.data(for: request)
        struct TokenResponse: Decodable { let access_token: String }
        return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
    }

    private func callRPC(_ name: String, body: [String: String], token: String) async throws -> Data {
        var request = URLRequest(url: Config.supabaseURL.appendingPathComponent("rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    @Test func courseModelDecodesLiveSearchResults() async throws {
        let token = try await accessToken()
        let data = try await callRPC("search_courses", body: ["p_query": "pebble beach"], token: token)
        let courses = try JSONDecoder().decode([Course].self, from: data)
        #expect(!courses.isEmpty)
        #expect(courses.contains { $0.name.contains("Pebble Beach") })
        #expect(courses.allSatisfy { $0.ratingCount == 0 && $0.avgScore == nil })
    }

    @Test func courseModelDecodesLiveRegionResults() async throws {
        let token = try await accessToken()
        let data = try await callRPC("courses_in_region", body: [
            "min_lat": "36.4", "min_lng": "-122.1", "max_lat": "36.7", "max_lng": "-121.8",
        ], token: token)
        let courses = try JSONDecoder().decode([Course].self, from: data)
        #expect(courses.contains { $0.name.contains("Pebble Beach") })
    }
}
