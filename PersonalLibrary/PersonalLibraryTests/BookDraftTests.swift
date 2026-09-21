import Foundation
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
