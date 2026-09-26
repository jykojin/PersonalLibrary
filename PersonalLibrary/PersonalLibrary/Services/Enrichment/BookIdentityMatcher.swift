import Foundation

enum BookIdentityMatcher {
    enum TitleMatchPolicy {
        case exact
        case explicitSubtitleWithISBN
    }

    static func matches(
        requestedTitle: String,
        requestedAuthor: String?,
        requestedISBN: String? = nil,
        candidateTitle: String,
        candidateAuthor: String?,
        candidateISBN: String? = nil,
        titleMatchPolicy: TitleMatchPolicy = .exact
    ) -> Bool {
        let normalizedRequestedTitle = BookTextNormalizer.normalizedTitle(requestedTitle)
        let normalizedCandidateTitle = BookTextNormalizer.normalizedTitle(candidateTitle)
        guard !normalizedCandidateTitle.isEmpty else { return false }
        let hasValidRequestedISBN = normalizedISBN(requestedISBN) != nil
        if hasValidRequestedISBN,
           !isbnMatches(requestedISBN, candidateISBN) {
            return false
        }
        if normalizedRequestedTitle.isEmpty && !hasValidRequestedISBN {
            return false
        }
        let requestedNames = normalizedAuthorNames(requestedAuthor ?? "")
        let candidateNames = normalizedAuthorNames(candidateAuthor ?? "")
        let requestedAuthorText = (requestedAuthor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasKnownAuthor = !requestedAuthorText.isEmpty && requestedAuthorText != "未知作者"
        let authorsMatch = hasKnownAuthor && !requestedNames.isEmpty
            && !requestedNames.isDisjoint(with: candidateNames)
        if !normalizedRequestedTitle.isEmpty,
           normalizedRequestedTitle != normalizedCandidateTitle {
            let permitsSubtitleVariant = titleMatchPolicy == .explicitSubtitleWithISBN
                && hasValidRequestedISBN
                && (explicitMainTitle(candidateTitle) == normalizedRequestedTitle
                    || explicitMainTitle(requestedTitle) == normalizedCandidateTitle)
            var permitsSourceDecoration = false
            if hasValidRequestedISBN && authorsMatch {
                let anchoredRequestedTitle = BookTextNormalizer.normalizedISBNAnchoredTitle(requestedTitle)
                permitsSourceDecoration = !anchoredRequestedTitle.isEmpty
                    && anchoredRequestedTitle == BookTextNormalizer.normalizedISBNAnchoredTitle(candidateTitle)
            }
            guard permitsSubtitleVariant || permitsSourceDecoration else { return false }
        }

        return !hasKnownAuthor || authorsMatch
    }

    static func isbnMatches(_ requested: String?, _ candidate: String?) -> Bool {
        guard let requestedISBN = normalizedISBN(requested),
              let candidateISBN = normalizedISBN(candidate) else {
            return false
        }
        if requestedISBN == candidateISBN {
            return true
        }
        guard let requestedEquivalent = isbn13Equivalent(requestedISBN),
              let candidateEquivalent = isbn13Equivalent(candidateISBN) else {
            return false
        }
        return requestedEquivalent == candidateEquivalent
    }

    static func hasValidISBN(_ value: String?) -> Bool {
        normalizedISBN(value) != nil
    }

    private static func explicitMainTitle(_ value: String) -> String? {
        guard let separator = value.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return nil
        }
        let mainTitle = String(value[..<separator])
        let subtitle = String(value[value.index(after: separator)...])
        guard !mainTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let normalizedMainTitle = BookTextNormalizer.normalizedTitle(mainTitle)
        return normalizedMainTitle.isEmpty ? nil : normalizedMainTitle
    }

    private static func normalizedAuthorNames(_ value: String) -> Set<String> {
        let separatedConjunctions = value.replacingOccurrences(
            of: #"\s+and\s+"#,
            with: ",",
            options: [.regularExpression, .caseInsensitive]
        )
        return Set(separatedConjunctions
            .components(separatedBy: CharacterSet(charactersIn: "/、,，;；&＆\n"))
            .flatMap { name -> [String] in
                let withoutRole = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(
                        of: #"\s+(?:著|编著|主编)$"#, with: "", options: .regularExpression
                    )
                // Multiple spaces separate coauthors on source pages. A single space
                // may be part of a transliterated full name; English names stay intact.
                if withoutRole.range(
                    of: #"^\p{Han}{2,4}(?:\s{2,}\p{Han}{2,4})+$"#,
                    options: .regularExpression
                ) != nil {
                    return withoutRole.split(whereSeparator: \.isWhitespace).map(String.init)
                }
                return [withoutRole]
            }
            .map(BookTextNormalizer.normalized)
            .filter { !$0.isEmpty })
    }

    private static func normalizedISBN(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
            .uppercased()
        if normalized.count == 13 {
            return normalized.allSatisfy(\.isNumber) ? normalized : nil
        }
        if normalized.count == 10 {
            let body = normalized.prefix(9)
            let checkDigit = normalized.last
            return body.allSatisfy(\.isNumber)
                && checkDigit.map { $0.isNumber || $0 == "X" } == true
                ? normalized
                : nil
        }
        return nil
    }

    private static func isbn13Equivalent(_ value: String) -> String? {
        if value.count == 13 {
            return value.allSatisfy(\.isNumber) ? value : nil
        }

        let body = String(value.prefix(9))
        guard body.count == 9, body.allSatisfy(\.isNumber) else { return nil }
        let prefix = "978" + body
        let sum = prefix.enumerated().reduce(0) { partial, entry in
            partial + (Int(String(entry.element)) ?? 0) * (entry.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return prefix + String((10 - sum % 10) % 10)
    }

}
