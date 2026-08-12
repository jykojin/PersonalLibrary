import Foundation
import SwiftData

/// 「书籍介绍」一次性回填工具。
///
/// 数据来自随包资源 `BookIntroductionSeed.json`（由 2026-08-12 的书单导出 + 外部整理的介绍生成）。
/// 只写 `bookIntroduction` 为空的书，**绝不新增书籍**，所以重复执行安全。
enum BookIntroductionSeeder {

    static let resourceName = "BookIntroductionSeed"

    /// seed 里的一条记录：`intro` 必有，四个匹配键都可能缺失。
    struct SeedEntry: Decodable {
        let title: String?
        let author: String?
        let isbn: String?
        let wereadId: String?
        let intro: String
    }

    struct Result {
        /// 实际写入介绍的书本数
        let updated: Int
        /// 在库里找不到对应书籍的 seed 条数
        let unmatched: Int
    }

    static func seedURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "json")
    }

    static func decode(_ data: Data) throws -> [SeedEntry] {
        try JSONDecoder().decode([SeedEntry].self, from: data)
    }

    /// 按 微信读书ID → ISBN → 书名+作者 的顺序匹配已有书籍，把 `intro` 写进 `bookIntroduction`。
    ///
    /// - 一个键命中多本时全部写入（库里本来就存在重复书，介绍内容相同）
    /// - 只写 `bookIntroduction` 为空的书，不会盖掉后来手改的内容
    /// - 不调用 `save()`，由调用方决定何时落盘
    @discardableResult
    static func backfill(_ entries: [SeedEntry], into context: ModelContext) -> Result {
        guard let books = try? context.fetch(FetchDescriptor<Book>()) else {
            return Result(updated: 0, unmatched: entries.count)
        }

        // 一次 fetch 建三张索引，避免逐条查询
        var byWereadId: [String: [Book]] = [:]
        var byISBN: [String: [Book]] = [:]
        var byTitleAuthor: [String: [Book]] = [:]
        for book in books {
            if let key = normalized(book.wereadBookId) {
                byWereadId[key, default: []].append(book)
            }
            if let key = normalized(book.isbn) {
                byISBN[key, default: []].append(book)
            }
            if let key = titleAuthorKey(title: book.title, author: book.author) {
                byTitleAuthor[key, default: []].append(book)
            }
        }

        var updated = 0
        var unmatched = 0

        for entry in entries {
            let matched: [Book]
            if let key = normalized(entry.wereadId), let hit = byWereadId[key] {
                matched = hit
            } else if let key = normalized(entry.isbn), let hit = byISBN[key] {
                matched = hit
            } else if let key = titleAuthorKey(title: entry.title, author: entry.author),
                      let hit = byTitleAuthor[key] {
                matched = hit
            } else {
                unmatched += 1
                continue
            }

            for book in matched where (book.bookIntroduction ?? "").isEmpty {
                book.bookIntroduction = entry.intro
                updated += 1
            }
        }

        return Result(updated: updated, unmatched: unmatched)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func titleAuthorKey(title: String?, author: String?) -> String? {
        guard let title = normalized(title) else { return nil }
        return "\(title)|\(normalized(author) ?? "")"
    }
}
