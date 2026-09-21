import Foundation

enum PublicationDateParser {
    static func parse(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let format: String
        switch value.count {
        case 4 where value.range(of: #"^\d{4}$"#, options: .regularExpression) != nil:
            format = "yyyy"
        case 7 where value.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil:
            format = "yyyy-MM"
        case 10 where value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil:
            format = "yyyy-MM-dd"
        default:
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    static func format(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
