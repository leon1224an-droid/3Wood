import Foundation

/// Normalizes user-entered and contact-book phone numbers to E.164 so the
/// same number always matches, however it was formatted. US-first (the course
/// catalog is US-only): bare 10-digit numbers are assumed to be +1.
enum PhoneNumber {
    static func normalize(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        let hadPlus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        if hadPlus {
            guard (8...15).contains(digits.count) else { return nil }
            return "+" + digits
        }
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return nil
    }

    /// "+14085551234" → "(408) 555-1234" for display; non-US passes through.
    static func display(_ e164: String) -> String {
        guard e164.hasPrefix("+1"), e164.count == 12 else { return e164 }
        let d = Array(e164.dropFirst(2))
        return "(\(String(d[0...2]))) \(String(d[3...5]))-\(String(d[6...9]))"
    }
}
