import Foundation

struct DoubanBookPage: Equatable, Sendable {
    let title: String
    let author: String?
    let translator: String?
    let publisher: String?
    let publishDate: String?
    let totalPages: Int?
    let price: String?
    let isbn: String?
    let bookDescription: String?
    let authorDescription: String?
    let coverImageURL: String?

    static func parse(_ html: String) -> DoubanBookPage? {
        guard let capturedTitle = capture(#"property="v:itemreviewed"[^>]*>([^<]+)</span>"#, in: html),
              let title = capturedTitle.cleaned else {
            return nil
        }
        let info = capture(#"<div id="info"[^>]*>(.*?)</div>"#, in: html, dotMatchesNewlines: true) ?? ""

        return DoubanBookPage(
            title: title,
            author: names(after: "作者", in: info),
            translator: names(after: "译者", in: info),
            publisher: labeledText("出版社", in: info),
            publishDate: labeledText("出版年", in: info),
            totalPages: labeledText("页数", in: info).flatMap { Int($0.filter(\.isNumber)) },
            price: labeledText("定价", in: info),
            isbn: labeledText("ISBN", in: info),
            bookDescription: DoubanDescriptionFetcher.extractBookDescription(from: html),
            authorDescription: DoubanDescriptionFetcher.extractAuthorDescription(from: html),
            coverImageURL: capture(#"property="og:image"\s+content="([^"]+)""#, in: html)
                ?? capture(#"content="([^"]+)"\s+property="og:image""#, in: html)
        )
    }

    private static func names(after label: String, in info: String) -> String? {
        guard let area = capture(
            #"<span[^>]*class="pl"[^>]*>\s*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*:?\s*</span>\s*:?\s*(.*?)(?:<br\s*/?>|<span[^>]*class="pl")"#,
            in: info,
            dotMatchesNewlines: true
        ) else { return nil }

        let linkedNames = captures(#"<a[^>]*>(.*?)</a>"#, in: area, dotMatchesNewlines: true)
            .compactMap(\.cleaned)
            .filter { !$0.isEmpty }
        let plain = area
            .replacingOccurrences(of: #"(?s)<a[^>]*>.*?</a>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let plainNames = plain
            .components(separatedBy: CharacterSet(charactersIn: "/、,，"))
            .compactMap(\.cleaned)
            .filter { !$0.isEmpty }
        let names = linkedNames + plainNames
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private static func labeledText(_ label: String, in info: String) -> String? {
        guard let area = capture(
            #"<span[^>]*class="pl"[^>]*>\s*"# + NSRegularExpression.escapedPattern(for: label) + #"\s*:?\s*</span>(.*?)(?:<br\s*/?>|<span[^>]*class="pl")"#,
            in: info,
            dotMatchesNewlines: true
        ) else { return nil }
        return area
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .cleaned
    }

    private static func capture(
        _ pattern: String,
        in text: String,
        dotMatchesNewlines: Bool = false
    ) -> String? {
        let options: NSRegularExpression.Options = dotMatchesNewlines ? [.dotMatchesLineSeparators] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func captures(
        _ pattern: String,
        in text: String,
        dotMatchesNewlines: Bool = false
    ) -> [String] {
        let options: NSRegularExpression.Options = dotMatchesNewlines ? [.dotMatchesLineSeparators] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

private extension String {
    var cleaned: String? {
        let result = replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
