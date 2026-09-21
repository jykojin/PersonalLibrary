import Foundation

enum BookIdentityMatcher {
    static func matches(
        requestedTitle: String,
        requestedAuthor: String?,
        requestedISBN: String? = nil,
        candidateTitle: String,
        candidateAuthor: String?,
        candidateISBN: String? = nil
    ) -> Bool {
        let requestedTitle = BookTextNormalizer.normalizedTitle(requestedTitle)
        let candidateTitle = BookTextNormalizer.normalizedTitle(candidateTitle)
        guard !candidateTitle.isEmpty else { return false }
        let hasValidRequestedISBN = normalizedISBN(requestedISBN) != nil
        if hasValidRequestedISBN,
           !isbnMatches(requestedISBN, candidateISBN) {
            return false
        }
        if requestedTitle.isEmpty && !hasValidRequestedISBN {
            return false
        }
        if !requestedTitle.isEmpty, requestedTitle != candidateTitle {
            return false
        }

        guard let requestedAuthor,
              !requestedAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              requestedAuthor.trimmingCharacters(in: .whitespacesAndNewlines) != "未知作者" else {
            return true
        }
        guard let candidateAuthor else { return false }

        let requestedNames = normalizedAuthorNames(requestedAuthor)
        let candidateNames = normalizedAuthorNames(candidateAuthor)
        return !requestedNames.isEmpty
            && !candidateNames.isEmpty
            && !requestedNames.isDisjoint(with: candidateNames)
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

    private static func normalizedAuthorNames(_ value: String) -> Set<String> {
        let separatedConjunctions = value.replacingOccurrences(
            of: #"\s+and\s+"#,
            with: ",",
            options: [.regularExpression, .caseInsensitive]
        )
        return Set(separatedConjunctions
            .components(separatedBy: CharacterSet(charactersIn: "/、,，;；&＆\n"))
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
