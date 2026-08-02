import Foundation
import UIKit
import Supabase

/// A photo someone added to a course.
struct CoursePhoto: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let userID: UUID
    let username: String
    let storagePath: String
    let createdAt: Date
    let isMine: Bool

    enum CodingKeys: String, CodingKey {
        case id, username
        case userID = "user_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
        case isMine = "is_mine"
    }
}

enum PhotoRepo {
    static let bucket = "course-photos"

    static func photos(courseID: Int) async throws -> [CoursePhoto] {
        try await supa.rpc("course_photos", params: ["p_course_id": courseID])
            .execute()
            .value
    }

    static func publicURL(for path: String) -> URL? {
        try? supa.storage.from(bucket).getPublicURL(path: path)
    }

    /// Downscales and re-encodes, uploads to `{user}/{course}/{uuid}.jpg`, then
    /// records the row the course page reads.
    ///
    /// Re-encoding is not just about size: it drops the original EXIF, and a
    /// photo taken at a course otherwise carries the GPS coordinates of
    /// wherever the user was standing.
    static func upload(image: UIImage, courseID: Int) async throws {
        guard let userID = supa.auth.currentSession?.user.id else {
            throw PhotoError.notSignedIn
        }
        guard let data = jpegData(from: image) else {
            throw PhotoError.encodingFailed
        }
        let path = "\(userID.uuidString.lowercased())/\(courseID)/\(UUID().uuidString.lowercased()).jpg"
        _ = try await supa.storage.from(bucket).upload(
            path, data: data, options: FileOptions(contentType: "image/jpeg")
        )

        struct Row: Encodable {
            let course_id: Int
            let user_id: UUID
            let storage_path: String
        }
        do {
            try await supa.from("course_photos")
                .insert(Row(course_id: courseID, user_id: userID, storage_path: path))
                .execute()
        } catch {
            // Don't leave a file with no row pointing at it — nothing would
            // ever show it, and nothing would ever clean it up.
            try? await supa.storage.from(bucket).remove(paths: [path])
            throw error
        }
    }

    static func delete(_ photo: CoursePhoto) async throws {
        try await supa.from("course_photos").delete().eq("id", value: photo.id).execute()
        try? await supa.storage.from(bucket).remove(paths: [photo.storagePath])
    }

    /// Long edge capped so a modern phone photo doesn't ship 4 MB of pixels
    /// nobody will see at this size.
    private static let maxEdge: CGFloat = 1600

    private static func jpegData(from image: UIImage) -> Data? {
        let longEdge = max(image.size.width, image.size.height)
        let scale = longEdge > maxEdge ? maxEdge / longEdge : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

enum PhotoError: LocalizedError {
    case notSignedIn
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You need to be signed in to add a photo."
        case .encodingFailed: "That image couldn't be prepared for upload."
        }
    }
}
