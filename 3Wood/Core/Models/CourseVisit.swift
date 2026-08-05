import Foundation

/// One round played at a course. A course can have many.
struct CourseVisit: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    /// "yyyy-MM-dd". Carried as text rather than Date because the Supabase
    /// decoder only parses full ISO-8601 timestamps — a bare date throws.
    let playedOn: String

    var date: Date? { PlayDate.parse(playedOn) }

    enum CodingKeys: String, CodingKey {
        case id
        case playedOn = "played_on"
    }
}

/// Calendar dates travel as "yyyy-MM-dd" strings; this is the one place that
/// knows how to read and write them.
enum PlayDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ string: String) -> Date? { formatter.date(from: string) }
    static func string(from date: Date) -> String { formatter.string(from: date) }

    /// "12 Mar 2026" — or the raw string if it somehow doesn't parse.
    static func display(_ string: String) -> String {
        guard let date = parse(string) else { return string }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
