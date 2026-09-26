import Foundation

enum BookTextNormalizer {
    static func titleWithoutEditionDecoration(_ value: String) -> String {
        let withoutParenthesizedEdition = value.replacingOccurrences(
            of: #"[（(\[].*?(新版|版|edition|精装|平装|修订).*?[）)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return withoutParenthesizedEdition.replacingOccurrences(
            of: #"\s*(?:第\s*[0-9一二三四五六七八九十百零〇两]+\s*版|新版|修订版|增订版|精装版?|平装版?|[:：,，\-–—]?\s*(?:(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|\d+(?:st|nd|rd|th)?)\s+edition|revised\s+edition|hardcover|paperback))\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedTitle(_ value: String) -> String {
        normalized(titleWithoutEditionDecoration(value))
    }

    /// Comparison only: callers must first match source ISBN and a known author.
    /// Keep single-volume labels; a set must not become interchangeable with one volume.
    static func normalizedISBNAnchoredTitle(_ value: String) -> String {
        // Reject, never truncate: an oversized suffix must not consume unbounded regex work
        // or turn a clipped unrelated title into a match.
        guard value.unicodeScalars.prefix(2_049).count <= 2_048 else { return "" }
        let withoutPromotion = value.replacingOccurrences(
            of: #"(?:《[^》\r\n]{1,100}》\s*)+作者\s+[\p{Han}\s]{2,40}\s+重磅力作\s*$"#,
            with: "",
            options: .regularExpression
        )
        let withoutBindingLabels = withoutPromotion.replacingOccurrences(
            of: #"(?:\s*[（(](?:增订版|修订版|新版|精装版?|平装版?|精|平)[）)])+\s*$"#,
            with: "",
            options: .regularExpression
        )
        let withoutSetLabel = withoutBindingLabels.replacingOccurrences(
            of: #"\s*[（(]上下[卷册][）)]\s*$"#,
            with: "",
            options: .regularExpression
        )
        return normalized(withoutSetLabel)
    }

    static func normalized(_ value: String) -> String {
        let simplified = value.applyingTransform(
            StringTransform("Traditional-Simplified"),
            reverse: false
        ) ?? value
        return simplified.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}
