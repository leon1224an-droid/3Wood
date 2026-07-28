import Foundation

/// Username rules, shared by first-launch setup and later renames.
/// Letters keep their case for display; uniqueness is case-insensitive
/// (enforced by a lower(username) index server-side).
enum Username {
    /// The real keyboard sneaks in spaces and smart punctuation — strip
    /// anything that can't be part of a username rather than silently
    /// disabling the save button over an invisible character.
    static func sanitize(_ raw: String) -> String {
        String(
            raw.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
                .prefix(20)
        )
    }

    static func isValid(_ candidate: String) -> Bool {
        candidate.wholeMatch(of: /[A-Za-z0-9_]{3,20}/) != nil
    }
}
