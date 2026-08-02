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

    /// Raw REST call against a table, returning body + status.
    private func rest(
        _ method: String, _ path: String, token: String,
        body: Data? = nil, prefer: String? = nil
    ) async throws -> (Data, Int) {
        var request = URLRequest(url: Config.supabaseURL.appendingPathComponent("rest/v1/\(path)"))
        request.httpMethod = method
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Swipe-to-save adds a course without knowing whether it is already
    /// bookmarked, so WantToPlayRepo.add upserts with ignore-duplicates.
    /// That resolution has to survive the (user_id, course_id) primary key
    /// *and* the fact that want_to_play grants insert but not update —
    /// a mismatch there fails at runtime, not compile time.
    @Test func repeatedWantToPlayInsertIsIdempotent() async throws {
        let token = try await accessToken()

        let searched = try await callRPC("search_courses", body: ["p_query": "pebble beach"], token: token)
        let course = try #require(try JSONDecoder().decode([Course].self, from: searched).first)

        // Restore whatever state the fixture user was in afterwards.
        let (existingData, _) = try await rest("POST", "rpc/my_want_to_play", token: token, body: Data("{}".utf8))
        let wasSavedAlready = (try? JSONDecoder().decode([Course].self, from: existingData))?
            .contains { $0.id == course.id } ?? false

        // Same Prefer header supabase-swift sends for
        // upsert(ignoreDuplicates: true) — INSERT ... ON CONFLICT DO NOTHING.
        let prefer = "resolution=ignore-duplicates,return=minimal"

        let first = try await rest(
            "POST", "want_to_play", token: token,
            body: try insertBody(courseID: course.id, token: token), prefer: prefer
        )
        #expect(first.1 == 201, "first insert failed: \(String(decoding: first.0, as: UTF8.self))")

        let second = try await rest(
            "POST", "want_to_play", token: token,
            body: try insertBody(courseID: course.id, token: token), prefer: prefer
        )
        #expect(second.1 == 201,
                "duplicate insert was rejected — swipe-to-save would surface an error: \(String(decoding: second.0, as: UTF8.self))")

        if !wasSavedAlready {
            _ = try await rest("DELETE", "want_to_play?course_id=eq.\(course.id)", token: token)
        }
    }

    /// The insert body the app sends: explicit user_id, taken from the JWT.
    private func insertBody(courseID: Int, token: String) throws -> Data {
        let userID = try Self.subject(ofJWT: token)
        return Data("{\"user_id\":\"\(userID)\",\"course_id\":\(courseID)}".utf8)
    }

    /// Pulls `sub` out of the access token so the test doesn't need a separate
    /// profile lookup.
    private static func subject(ofJWT token: String) throws -> String {
        let parts = token.split(separator: ".")
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload += "=" }
        let data = try #require(Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")))
        struct Claims: Decodable { let sub: String }
        return try JSONDecoder().decode(Claims.self, from: data).sub
    }

    /// Storage policies key on the first path segment being the uploader's
    /// user id. That rule is the only thing stopping one user writing into
    /// another's folder, and it lives in SQL where the compiler can't check it.
    @Test func photoUploadIsConfinedToTheUsersOwnFolder() async throws {
        let token = try await accessToken()
        let userID = try Self.subject(ofJWT: token)

        // Smallest valid JPEG payload; the point is the path, not the pixels.
        let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==")!

        func put(path: String) async throws -> Int {
            var request = URLRequest(url: Config.supabaseURL
                .appendingPathComponent("storage/v1/object/course-photos/\(path)"))
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.httpBody = jpeg
            let (_, response) = try await URLSession.shared.upload(for: request, from: jpeg)
            return (response as? HTTPURLResponse)?.statusCode ?? 0
        }

        // Someone else's folder must be refused.
        let foreign = try await put(path: "00000000-0000-0000-0000-0000000000ff/1/probe.jpg")
        #expect(foreign == 400 || foreign == 403,
                "upload into another user's folder was not rejected (got \(foreign))")

        // The caller's own folder is allowed.
        let ownPath = "\(userID.lowercased())/1/\(UUID().uuidString.lowercased()).jpg"
        let own = try await put(path: ownPath)
        #expect(own == 200, "upload into the caller's own folder failed (got \(own))")

        // Clean up so repeated runs don't accumulate objects.
        var delete = URLRequest(url: Config.supabaseURL
            .appendingPathComponent("storage/v1/object/course-photos/\(ownPath)"))
        delete.httpMethod = "DELETE"
        delete.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        delete.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: delete)
    }

    @Test func courseModelDecodesLiveSearchResults() async throws {
        let token = try await accessToken()
        let data = try await callRPC("search_courses", body: ["p_query": "pebble beach"], token: token)
        let courses = try JSONDecoder().decode([Course].self, from: data)
        #expect(!courses.isEmpty)
        let pebble = courses.first { $0.name == "Pebble Beach Golf Links" }
        #expect(pebble != nil)
        // The test1 fixture user has ranked Pebble Beach, so a community
        // average must be present and within the 0-10 scale.
        #expect(pebble?.ratingCount ?? 0 >= 1)
        if let avg = pebble?.avgScore {
            #expect((0.0...10.0).contains(avg))
        }
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
