import Foundation
import SwiftData
import Testing
@testable import PersonalLibrary

@Suite("BookDraft Tests")
struct BookDraftTests {
    @Test("统一识别空白、未知作者、无效页数和折叠简介")
    func detectsEveryMissingField() {
        let draft = BookDraft(
            title: "  ",
            author: "未知作者",
            translator: "\n",
            isbn: "9787000000001",
            publisher: "",
            publishDate: nil,
            totalPages: 0,
            price: " ",
            bookDescription: "内容待续，展开全部",
            authorDescription: nil,
            aiIntroduction: "\t"
        )

        #expect(draft.missingFields == Set(EnrichmentField.allCases))
    }

    @Test("候选值只填缺失字段且不覆盖已有内容")
    func candidatesOnlyFillMissingValues() {
        let original = BookDraft(
            title: "已有书名",
            author: "",
            publisher: "已有出版社",
            totalPages: 0,
            aiIntroduction: "已有 AI 简介"
        )
        let candidate = BookDraft(
            title: "候选书名",
            author: "候选作者",
            publisher: "候选出版社",
            totalPages: 320,
            aiIntroduction: "候选 AI 简介"
        )

        let merged = original.fillingMissingFields(
            from: candidate,
            limitedTo: [.title, .author, .publisher, .totalPages, .aiIntroduction]
        )

        #expect(merged == BookDraft(
            title: "已有书名",
            author: "候选作者",
            publisher: "已有出版社",
            totalPages: 320,
            aiIntroduction: "已有 AI 简介"
        ))
    }

    @Test("出版日期统一解析年、年月和完整日期")
    func parsesSupportedPublicationDates() {
        let calendar = Calendar(identifier: .gregorian)

        #expect(calendar.dateComponents([.year, .month, .day], from: PublicationDateParser.parse("2024-03-18")!)
            == DateComponents(year: 2024, month: 3, day: 18))
        #expect(calendar.dateComponents([.year, .month, .day], from: PublicationDateParser.parse("2024-03")!)
            == DateComponents(year: 2024, month: 3, day: 1))
        #expect(calendar.dateComponents([.year, .month, .day], from: PublicationDateParser.parse("2024")!)
            == DateComponents(year: 2024, month: 1, day: 1))
        #expect(PublicationDateParser.parse("2024-19-42") == nil)
    }

    @Test("豆瓣非补零月份和日期可以解析")
    func parsesNonPaddedDoubanPublicationDates() {
        let calendar = Calendar(identifier: .gregorian)

        #expect(PublicationDateParser.parse("2026-8").map {
            calendar.dateComponents([.year, .month, .day], from: $0)
        } == DateComponents(year: 2026, month: 8, day: 1))
        #expect(PublicationDateParser.parse("2017-7-1").map {
            calendar.dateComponents([.year, .month, .day], from: $0)
        } == DateComponents(year: 2017, month: 7, day: 1))
    }

    @Test("出版日期兼容点号、斜杠和中文年月日")
    func parsesCommonPublicationDateFormats() {
        let calendar = Calendar(identifier: .gregorian)
        let examples: [(String, DateComponents)] = [
            ("2023.09", DateComponents(year: 2023, month: 9, day: 1)),
            ("2019.09.01", DateComponents(year: 2019, month: 9, day: 1)),
            ("2022/8", DateComponents(year: 2022, month: 8, day: 1)),
            ("2022/8/7", DateComponents(year: 2022, month: 8, day: 7)),
            ("2010年4月", DateComponents(year: 2010, month: 4, day: 1)),
            ("2010年4月5日", DateComponents(year: 2010, month: 4, day: 5))
        ]

        for (value, expected) in examples {
            #expect(PublicationDateParser.parse(value).map {
                calendar.dateComponents([.year, .month, .day], from: $0)
            } == expected, "应解析 \(value)")
        }
    }

    @Test("出版日期兼容数据源中的年份小数、英文月份和全角分隔符")
    func parsesSourceSpecificPublicationDateFormats() {
        let calendar = Calendar(identifier: .gregorian)
        let examples: [(String, DateComponents)] = [
            ("2023.0", DateComponents(year: 2023, month: 1, day: 1)),
            ("April 1, 1999", DateComponents(year: 1999, month: 4, day: 1)),
            ("Apr 1999", DateComponents(year: 1999, month: 4, day: 1)),
            ("2023／9／1", DateComponents(year: 2023, month: 9, day: 1))
        ]

        for (value, expected) in examples {
            #expect(PublicationDateParser.parse(value).map {
                calendar.dateComponents([.year, .month, .day], from: $0)
            } == expected, "应解析 \(value)")
        }
        #expect(PublicationDateParser.parse("February 30, 2024") == nil)
    }

    @Test("历史点号导入产生的异常年份可以确定性还原")
    func repairsMalformedImportedPublicationDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let malformedYearMonth = try #require(calendar.date(from: DateComponents(year: 20239)))
        let malformedFullDate = try #require(calendar.date(from: DateComponents(year: 201991)))
        let validDate = try #require(calendar.date(from: DateComponents(year: 2023, month: 9, day: 1)))

        #expect(PublicationDateParser.repairMalformedImportDate(
            malformedYearMonth,
            calendar: calendar
        ).map(PublicationDateParser.format) == "2023-09-01")
        #expect(PublicationDateParser.repairMalformedImportDate(
            malformedFullDate,
            calendar: calendar
        ).map(PublicationDateParser.format) == "2019-09-01")
        #expect(PublicationDateParser.repairMalformedImportDate(validDate, calendar: calendar) == nil)
    }

    @Test("新书的 AI 补全时间默认为空且可设置")
    func aiEnrichmentDateIsPersistable() {
        let book = Book(title: "测试", author: "作者")
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(book.lastAIEnrichmentDate == nil)
        book.lastAIEnrichmentDate = date
        #expect(book.lastAIEnrichmentDate == date)
    }

    @Test("Book 可以完整转换为 BookDraft")
    func bookConvertsToDraft() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let book = Book(
            title: "书名",
            author: "作者",
            translator: "译者",
            isbn: "9787000000001",
            publisher: "出版社",
            publishDate: date,
            totalPages: 320,
            price: "¥58.00",
            bookDescription: "图书简介",
            authorDescription: "作者简介"
        )
        book.bookIntroduction = "AI 简介"
        book.rating = 4
        book.notes = "用户备注"

        #expect(BookDraft(book: book) == BookDraft(
            title: "书名",
            author: "作者",
            translator: "译者",
            isbn: "9787000000001",
            publisher: "出版社",
            publishDate: date,
            totalPages: 320,
            price: "¥58.00",
            bookDescription: "图书简介",
            authorDescription: "作者简介",
            aiIntroduction: "AI 简介",
            rating: 4,
            notes: "用户备注"
        ))
    }

    @Test("Outcome 写回时保留补全过程中的用户编辑")
    func outcomePreservesConcurrentUserEdits() {
        let book = Book(title: "书名", author: "")
        let original = BookDraft(book: book)
        let candidate = BookDraft(title: "书名", author: "候选作者", publisher: "候选出版社")
        let final = original.fillingMissingFields(from: candidate, limitedTo: [.author, .publisher])
        let outcome = EnrichmentOutcome(originalDraft: original, draft: final)

        book.author = "用户刚刚编辑的作者"
        outcome.apply(to: book)

        #expect(book.author == "用户刚刚编辑的作者")
        #expect(book.publisher == "候选出版社")
    }
}

@Suite("Publication Date Migration Tests")
struct PublicationDateMigrationTests {
    @Test("历史异常日期只修复一次且不改正常日期")
    @MainActor
    func repairsOnlyMalformedDatesIdempotently() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let container = try ModelContainer(
            for: Book.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let malformed = Book(title: "异常日期", author: "作者")
        malformed.publishDate = try #require(calendar.date(from: DateComponents(year: 20239)))
        let valid = Book(title: "正常日期", author: "作者")
        valid.publishDate = try #require(calendar.date(from: DateComponents(year: 2023, month: 9, day: 1)))
        context.insert(malformed)
        context.insert(valid)
        try context.save()

        #expect(try PublicationDateMigration.repair(in: context, calendar: calendar) == 1)
        #expect(PublicationDateParser.format(malformed.publishDate) == "2023-09-01")
        #expect(PublicationDateParser.format(valid.publishDate) == "2023-09-01")
        #expect(try PublicationDateMigration.repair(in: context, calendar: calendar) == 0)
    }

    @Test("历史日期按原导入时区解码并统一存为标准日期")
    func repairedDateDoesNotShiftAcrossTimeZones() throws {
        var importCalendar = Calendar(identifier: .gregorian)
        importCalendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let malformed = try #require(importCalendar.date(from: DateComponents(year: 20239)))

        let repaired = PublicationDateParser.repairMalformedImportDate(
            malformed,
            calendar: importCalendar
        )

        #expect(PublicationDateParser.format(repaired) == "2023-09-01")
    }
}
