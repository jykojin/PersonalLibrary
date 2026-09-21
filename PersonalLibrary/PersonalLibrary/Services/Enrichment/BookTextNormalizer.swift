import Foundation

enum BookTextNormalizer {
    static func normalizedTitle(_ value: String) -> String {
        let withoutParenthesizedEdition = value.replacingOccurrences(
            of: #"[（(\[].*?(新版|版|edition|精装|平装|修订).*?[）)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let withoutEditionSuffix = withoutParenthesizedEdition.replacingOccurrences(
            of: #"\s*(?:第\s*[0-9一二三四五六七八九十百零〇两]+\s*版|新版|修订版|增订版|精装版?|平装版?|[:：,，\-–—]?\s*(?:(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|\d+(?:st|nd|rd|th)?)\s+edition|revised\s+edition|hardcover|paperback))\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return normalized(withoutEditionSuffix)
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
