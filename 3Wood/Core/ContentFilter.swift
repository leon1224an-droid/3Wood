import Foundation

/// A minimal objectionable-content filter, checked client-side before a
/// review, comment, or username is submitted. Guideline 1.2 requires a
/// filtering method distinct from report/block — this is intentionally a
/// blunt denylist, not a moderation system: report + block + the 24-hour
/// takedown commitment in the Terms carry the real enforcement weight.
enum ContentFilter {
    /// Whole-word matches only. Plain substring matching has the
    /// "Scunthorpe problem" — "spic" ⊂ "spicy", "rape" ⊂ "grape", "kys" ⊂
    /// "skys" — which silently rejects ordinary words and, worse, ordinary
    /// usernames with no way to tell the user why.
    private static let words: Set<String> = [
        "nigger", "nigga", "faggot", "retard", "spic", "kike", "chink",
        "cunt", "whore", "rape", "kys",
    ]

    /// Multi-word phrases, checked as substrings since they can't collide
    /// with a single innocent word the way the tokens above can.
    private static let phrases: [String] = [
        "kill yourself",
    ]

    /// True if the text contains a denylisted term as a whole word (or, for
    /// phrases, a substring). A false positive just asks someone to
    /// rephrase, which is cheap; a false negative ships a slur — so this
    /// stays a blunt denylist, not a moderation system.
    static func isObjectionable(_ text: String) -> Bool {
        let normalized = text.lowercased()
        if phrases.contains(where: { normalized.contains($0) }) { return true }
        let tokens = normalized.split { !$0.isLetter && !$0.isNumber }
        return tokens.contains { words.contains(String($0)) }
    }
}
