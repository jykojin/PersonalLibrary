import Foundation

enum PublicationDateParser {
    static func parse(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let englishDate = parseEnglishMonthDate(value) {
            return englishDate
        }

        let excelYear = value.range(
            of: #"^\d{4}\.0+$"#,
            options: .regularExpression
        ) != nil ? String(value.prefix(4)) : value
        let normalized = excelYear
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "．", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "／", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard normalized.range(
            of: #"^\d{4}(?:-\d{1,2})?(?:-\d{1,2})?$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }

        let parts = normalized.split(separator: "-").compactMap { Int($0) }
        guard parts.count == normalized.split(separator: "-").count,
              let year = parts.first,
              (1...9999).contains(year) else {
            return nil
        }

        let month = parts.count > 1 ? parts[1] : 1
        let day = parts.count > 2 ? parts[2] : 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let requested = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: requested),
              calendar.dateComponents([.year, .month, .day], from: date) == requested else {
            return nil
        }
        return date
    }

    private static func parseEnglishMonthDate(_ value: String) -> Date? {
        let format: String
        switch value {
        case _ where value.range(
            of: #"^[A-Za-z]+\s+\d{1,2},\s*\d{4}$"#,
            options: .regularExpression
        ) != nil:
            format = "MMMM d, yyyy"
        case _ where value.range(
            of: #"^[A-Za-z]+\s+\d{4}$"#,
            options: .regularExpression
        ) != nil:
            format = "MMM yyyy"
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

    /// 修复旧版 Excel 导入把 `yyyy.0M` / `yyyy.0M.0d` 拼成 5～6 位年份的记录。
    /// 只接受异常日期落在一月一日且后缀能组成有效月日，避免修改其他数据。
    static func repairMalformedImportDate(
        _ date: Date,
        calendar inputCalendar: Calendar = .current
    ) -> Date? {
        let calendar = inputCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard components.month == 1,
              components.day == 1,
              let malformedYear = components.year else {
            return nil
        }

        let digits = String(malformedYear)
        guard digits.count == 5 || digits.count == 6,
              let year = Int(digits.prefix(4)),
              let month = Int(String(digits[digits.index(digits.startIndex, offsetBy: 4)])),
              (1...9).contains(month) else {
            return nil
        }
        let day: Int
        if digits.count == 6 {
            guard let parsedDay = Int(String(digits.last!)), (1...9).contains(parsedDay) else {
                return nil
            }
            day = parsedDay
        } else {
            day = 1
        }

        return parse("\(year)-\(month)-\(day)")
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
