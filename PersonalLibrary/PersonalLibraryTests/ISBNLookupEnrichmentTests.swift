import Foundation
import Testing
@testable import PersonalLibrary

@Suite("ISBN Lookup Enrichment Tests")
struct ISBNLookupEnrichmentTests {
    @Test("豆瓣译者链接和纯文本统一为逗号分隔")
    func parsesDoubanTranslators() {
        #expect(DoubanBookPage.parse(EnrichmentFixtures.doubanSingleTranslatorHTML)?.translator == "示例译者")
        #expect(DoubanBookPage.parse(EnrichmentFixtures.doubanMultipleTranslatorsHTML)?.translator == "译者甲, 译者乙")
        #expect(DoubanBookPage.parse(EnrichmentFixtures.doubanPlainTextTranslatorHTML)?.translator == "译者丙, 译者丁")
        #expect(DoubanBookPage.parse(EnrichmentFixtures.doubanMixedTranslatorHTML)?.translator == "译者甲, 译者乙")
    }

    @Test("豆瓣标签后的冒号不会污染作者和译者")
    func doubanTrailingColonDoesNotBecomeAName() {
        let page = DoubanBookPage.parse(EnrichmentFixtures.doubanTrailingColonTranslatorHTML)

        #expect(page?.author == "[日] 寄藤文平, [日] 藤田纮一郎")
        #expect(page?.translator == "吴锵煌")
    }

    @Test("豆瓣页面提供独立 ISBN 身份凭据")
    func parsesDoubanISBNIdentityEvidence() {
        #expect(DoubanBookPage.parse(EnrichmentFixtures.doubanSingleTranslatorHTML)?.isbn == "978-7-0200-0220-7")
    }

    @Test("豆瓣页面没有译者标签时译者保持为空")
    func doubanWithoutTranslatorKeepsTranslatorEmpty() {
        let html = EnrichmentFixtures.doubanSingleTranslatorHTML.replacingOccurrences(
            of: #"<span class="pl">译者:</span> <a>示例译者</a><br/>"#,
            with: ""
        )

        #expect(DoubanBookPage.parse(html)?.translator == nil)
    }

    @Test("常规补全将豆瓣译者写入空译者字段")
    func regularLookupFillsMissingTranslatorFromDouban() async {
        let client = DoubanSuggestionHTTPClient()
        let source = ISBNMetadataSourceAdapter(
            source: .douban,
            service: ISBNLookupService(httpClient: client),
            doubanFetcher: DoubanDescriptionFetcher(
                httpClient: client,
                waitForRateLimit: {}
            )
        )
        let draft = BookDraft(title: "示例图书", author: "示例作者")

        let outcome = await SequentialBookMetadataLookup(sources: [source])
            .lookup(draft: draft, missingFields: [.translator, .publishDate])

        #expect(outcome.draft.translator == "示例译者")
        #expect(outcome.draft.publishDate.map {
            Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: $0)
        } == DateComponents(year: 2026, month: 8, day: 1))
        #expect(outcome.sourceReports == [MetadataSourceReport(source: .douban, status: .found)])
    }

    @Test("豆瓣精确版本缺少译者时从身份匹配的其他版本补齐")
    func doubanISBNLookupFillsTranslatorFromAnotherEdition() async {
        let client = DoubanEditionTranslatorHTTPClient()
        let source = ISBNMetadataSourceAdapter(
            source: .douban,
            service: ISBNLookupService(httpClient: client),
            doubanFetcher: DoubanDescriptionFetcher(
                httpClient: client,
                waitForRateLimit: {}
            )
        )
        let draft = BookDraft(
            title: "大便书（纪念版）",
            author: "(日) 藤田纮一郎 / （日）寄藤文平",
            isbn: "9787536486003"
        )

        let result = await source.lookup(draft: draft, missingFields: [.translator])

        #expect(result.status == .found)
        #expect(result.candidate?.title == "大便书（纪念版）")
        #expect(result.candidate?.isbn == "9787536486003")
        #expect(result.candidate?.translator == "吴锵煌")
    }

    @Test("普通来源严格按豆瓣、Goodreads、Open Library 查询且高优先级值胜出")
    func metadataSourcesUseRequiredPriority() async {
        let recorder = MetadataLookupRecorder()
        let lookup = SequentialBookMetadataLookup(sources: [
            StubMetadataSource(
                source: .openLibrary,
                candidate: BookDraft(title: "", author: "", publisher: "Open Library 出版社", totalPages: 320),
                recorder: recorder
            ),
            StubMetadataSource(
                source: .douban,
                candidate: BookDraft(title: "", author: "", publisher: "豆瓣出版社"),
                recorder: recorder
            ),
            StubMetadataSource(
                source: .goodreads,
                candidate: BookDraft(title: "", author: "", publisher: "Goodreads 出版社", bookDescription: "英文简介"),
                recorder: recorder
            )
        ])
        let original = BookDraft(title: "示例图书", author: "示例作者")

        let outcome = await lookup.lookup(draft: original, missingFields: original.missingFields)

        #expect(await recorder.values == [.douban, .goodreads, .openLibrary])
        #expect(outcome.draft.publisher == "豆瓣出版社")
        #expect(outcome.draft.bookDescription == "英文简介")
        #expect(outcome.draft.totalPages == 320)
    }

    @Test("书名相同但作者不同的搜索结果必须拒绝")
    func rejectsWrongAuthorForSameTitle() {
        #expect(BookIdentityMatcher.matches(
            requestedTitle: "挪威的森林",
            requestedAuthor: "村上春树",
            candidateTitle: "挪威的森林（新版）",
            candidateAuthor: "村上春树"
        ))
        #expect(!BookIdentityMatcher.matches(
            requestedTitle: "挪威的森林",
            requestedAuthor: "村上春树",
            candidateTitle: "挪威的森林",
            candidateAuthor: "另一位作者"
        ))
    }

    @Test("身份核验容忍繁简体和版本装饰但仍要求作者匹配")
    func identityMatchingNormalizesChineseVariants() {
        #expect(BookIdentityMatcher.matches(
            requestedTitle: "阅读的故事",
            requestedAuthor: "唐诺",
            candidateTitle: "閱讀的故事（修訂版）",
            candidateAuthor: "唐諾"
        ))
    }

    @Test("身份核验容忍不带括号的中英文版本后缀")
    func identityMatchingNormalizesUnparenthesizedEditionSuffixes() {
        #expect(BookIdentityMatcher.matches(
            requestedTitle: "阅读的故事",
            requestedAuthor: "唐诺",
            candidateTitle: "閱讀的故事 第2版",
            candidateAuthor: "唐諾"
        ))
        #expect(BookIdentityMatcher.matches(
            requestedTitle: "The Example Book",
            requestedAuthor: "Jane Doe",
            candidateTitle: "The Example Book: Second Edition",
            candidateAuthor: "Jane Doe"
        ))
    }

    @Test("普通来源不能仅凭同作者和冒号主标题接受不同副标题")
    func ordinaryLookupRejectsSubtitleVariantWithoutISBNAnchor() {
        #expect(!BookIdentityMatcher.matches(
            requestedTitle: "人生问答",
            requestedAuthor: "成庆",
            candidateTitle: "人生问答：续篇",
            candidateAuthor: "成庆"
        ))
    }

    @Test("作者姓名必须完整匹配，但允许匹配多作者列表中的一人")
    func authorIdentityRejectsSubstringsAndMatchesWholeNames() {
        #expect(!BookIdentityMatcher.matches(
            requestedTitle: "同名图书",
            requestedAuthor: "王安",
            candidateTitle: "同名图书",
            candidateAuthor: "王安石"
        ))
        #expect(BookIdentityMatcher.matches(
            requestedTitle: "合著图书",
            requestedAuthor: "作者乙",
            candidateTitle: "合著图书",
            candidateAuthor: "作者甲 / 作者乙"
        ))
    }

    @Test("Goodreads 和 Open Library 书名查询保留可重试网络错误")
    func titleSearchPreservesRetryableNetworkErrors() async {
        let service = ISBNLookupService(httpClient: ThrowingMetadataHTTPClient())
        let draft = BookDraft(title: "示例图书", author: "示例作者")

        for source in [BookMetadataSource.goodreads, .openLibrary] {
            let result = await ISBNMetadataSourceAdapter(source: source, service: service)
                .lookup(draft: draft, missingFields: draft.missingFields)

            guard case .retryableFailure = result.status else {
                Issue.record("\(source.rawValue) 不应把网络错误伪装成未找到")
                continue
            }
        }
    }

    @Test("ISBN 查询的 HTTP 服务失败不能伪装成未找到")
    func isbnLookupPreservesHTTPFailures() async {
        let service = ISBNLookupService(httpClient: StatusMetadataHTTPClient(statusCode: 503))
        let draft = BookDraft(title: "", author: "", isbn: "9787020002207")

        for source in BookMetadataSource.allCases {
            let result = await ISBNMetadataSourceAdapter(source: source, service: service)
                .lookup(draft: draft, missingFields: draft.missingFields)

            guard case .retryableFailure = result.status else {
                Issue.record("\(source.rawValue) 不应把 HTTP 503 伪装成未找到")
                continue
            }
        }
    }

    @Test("Open Library ISBN 未命中后可按书名作者回退到另一版本")
    func openLibraryFallsBackToTitleAfterISBNMiss() async {
        let client = OpenLibraryFallbackHTTPClient()
        let service = ISBNLookupService(httpClient: client)
        let draft = BookDraft(
            title: "示例图书",
            author: "示例作者",
            isbn: "9787020002207"
        )

        let result = await ISBNMetadataSourceAdapter(source: .openLibrary, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(await client.paths == ["/api/books", "/search.json"])
        #expect(result.status == .found)
        #expect(result.candidate?.publisher == "回退出版社")
        #expect(result.candidate?.totalPages == 288)
        #expect(result.candidate?.isbn == "9787020002214")
    }

    @Test("Open Library 响应中的简介不会进入图书简介或作者简介")
    func openLibraryNeverSuppliesDescriptions() async {
        let service = ISBNLookupService(httpClient: OpenLibraryDescriptionHTTPClient())
        let draft = BookDraft(
            title: "示例图书",
            author: "示例作者",
            isbn: "9787020002207"
        )

        let result = await ISBNMetadataSourceAdapter(source: .openLibrary, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(result.status == .found)
        #expect(result.candidate?.bookDescription == nil)
        #expect(result.candidate?.authorDescription == nil)
    }

    @Test("Goodreads ISBN 与书名入口采用可靠的结构化出版社日期和定价")
    func goodreadsUsesStructuredPublicationFields() async throws {
        let service = ISBNLookupService(httpClient: GoodreadsStructuredHTTPClient())

        let isbnResult = try await service.lookupFromGoodreads(isbn: "9787020002207")
        let titleResult = try await service.searchGoodreadsByTitle(
            title: "示例图书",
            author: "示例作者"
        )

        for result in [isbnResult, titleResult] {
            #expect(result?.publisher == "示例出版社")
            #expect(result?.publishDate == "2024-03-15")
            #expect(result?.price == "CNY 58.00")
        }
    }

    @Test("Goodreads 只采用与结果作者绑定的结构化作者简介")
    func goodreadsUsesStructuredAuthorDescription() async throws {
        let service = ISBNLookupService(httpClient: GoodreadsStructuredHTTPClient())

        let isbnResult = try await service.lookupFromGoodreads(isbn: "9787020002207")
        let titleResult = try await service.searchGoodreadsByTitle(
            title: "示例图书",
            author: "示例作者"
        )

        #expect(isbnResult?.authorDescription == "示例作者的可靠结构化简介。")
        #expect(titleResult?.authorDescription == "示例作者的可靠结构化简介。")
    }

    @Test("书名回退身份冲突时标记验证拒绝")
    func titleFallbackIdentityMismatchIsValidationRejected() async {
        let service = ISBNLookupService(
            httpClient: GoodreadsStructuredHTTPClient(author: "另一位作者")
        )
        let draft = BookDraft(title: "示例图书", author: "示例作者")

        let result = await ISBNMetadataSourceAdapter(source: .goodreads, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(result.status == .validationRejected("书名或作者身份不符"))
        #expect(result.candidate == nil)
    }

    @Test("ISBN 命中返回冲突 ISBN 时标记验证拒绝")
    func isbnLookupIdentityMismatchIsValidationRejected() async {
        let service = ISBNLookupService(
            httpClient: GoodreadsStructuredHTTPClient(isbn: "9787020002214")
        )
        let draft = BookDraft(title: "", author: "", isbn: "9787020002207")

        let result = await ISBNMetadataSourceAdapter(source: .goodreads, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(result.status == .validationRejected("ISBN 候选与请求 ISBN 不符"))
        #expect(result.candidate == nil)
    }

    @Test("ISBN 候选冲突时继续使用同来源书名回退")
    func rejectedISBNCandidateFallsBackToTitle() async {
        let client = GoodreadsRejectedISBNFallbackHTTPClient(
            directISBN: "9787020002214"
        )
        let service = ISBNLookupService(httpClient: client)
        let draft = BookDraft(
            title: "示例图书",
            author: "示例作者",
            isbn: "9787020002207"
        )

        let result = await ISBNMetadataSourceAdapter(source: .goodreads, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(await client.paths == [
            "/book/isbn/9787020002207",
            "/search",
            "/book/show/67890"
        ])
        #expect(result.status == .found)
        #expect(result.candidate?.publisher == "回退出版社")
    }

    @Test("ISBN 候选缺少来源凭据时继续使用同来源书名回退")
    func unverifiedISBNCandidateFallsBackToTitle() async {
        let client = GoodreadsRejectedISBNFallbackHTTPClient(directISBN: nil)
        let service = ISBNLookupService(httpClient: client)
        let draft = BookDraft(
            title: "示例图书",
            author: "示例作者",
            isbn: "9787020002207"
        )

        let result = await ISBNMetadataSourceAdapter(source: .goodreads, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(await client.paths == [
            "/book/isbn/9787020002207",
            "/search",
            "/book/show/67890"
        ])
        #expect(result.status == .found)
        #expect(result.candidate?.publisher == "回退出版社")
    }

    @Test("ISBN 命中但书名或作者冲突时标记验证拒绝")
    func isbnLookupTitleOrAuthorMismatchIsValidationRejected() async {
        let service = ISBNLookupService(
            httpClient: GoodreadsStructuredHTTPClient(author: "另一位作者")
        )
        let draft = BookDraft(
            title: "示例图书",
            author: "示例作者",
            isbn: "9787020002207"
        )

        let result = await ISBNMetadataSourceAdapter(source: .goodreads, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(result.status == .validationRejected("书名或作者身份不符"))
        #expect(result.candidate == nil)
    }

    @Test("同一本书的 ISBN-10 与 ISBN-13 视为相同身份")
    func isbnLookupAcceptsEquivalentISBN10AndISBN13() async {
        let service = ISBNLookupService(
            httpClient: GoodreadsStructuredHTTPClient(isbn: "9780306406157")
        )
        let draft = BookDraft(
            title: "示例图书",
            author: "示例作者",
            isbn: "0-306-40615-2"
        )

        let result = await ISBNMetadataSourceAdapter(source: .goodreads, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(result.status == .found)
        #expect(result.candidate?.publisher == "示例出版社")
    }

    @Test("ISBN-only 查询缺少来源身份凭据时标记验证拒绝")
    func isbnOnlyLookupWithoutProviderISBNIsValidationRejected() async {
        let service = ISBNLookupService(
            httpClient: GoodreadsStructuredHTTPClient(isbn: nil)
        )
        let draft = BookDraft(title: "", author: "", isbn: "9787020002207")

        let result = await ISBNMetadataSourceAdapter(source: .goodreads, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(result.status == .validationRejected("ISBN 候选缺少来源凭据"))
        #expect(result.candidate == nil)
    }

    @Test("不同的异常 ISBN 不能因换算失败而视为同一身份并标记验证拒绝")
    func malformedISBNsDoNotMatch() async {
        let service = ISBNLookupService(
            httpClient: GoodreadsStructuredHTTPClient(isbn: "XXXXXXXXX0")
        )
        let draft = BookDraft(title: "", author: "", isbn: "XXXXXXXXXX")

        let result = await ISBNMetadataSourceAdapter(source: .goodreads, service: service)
            .lookup(draft: draft, missingFields: draft.missingFields)

        #expect(result.status == .validationRejected("ISBN 候选与请求 ISBN 不符"))
        #expect(result.candidate == nil)
    }

    @Test("扫码 ISBN 查询不会接受来源返回的冲突 ISBN")
    func directISBNLookupRejectsConflictingProviderIdentity() async throws {
        let service = ISBNLookupService(httpClient: ISBNLookupChainMismatchHTTPClient())

        let result = try await service.lookup(isbn: "9787020002207")

        #expect(result == nil)
    }

    @Test("扫码 ISBN 查询接受 Google Books 返回的匹配来源凭据")
    func directISBNLookupAcceptsMatchingGoogleBooksIdentity() async throws {
        let service = ISBNLookupService(httpClient: GoogleBooksIdentityHTTPClient())

        let result = try await service.lookup(isbn: "9787020002207")

        #expect(result?.title == "示例图书")
        #expect(result?.isbn == "9787020002207")
        #expect(result?.isbnIsSourceVerified == true)
    }

    @Test("豆瓣书名回退会继续检查建议列表直到书名和作者都匹配")
    func doubanTitleSearchChecksLaterIdentityMatches() async throws {
        let client = DoubanSuggestionHTTPClient()
        let fetcher = DoubanDescriptionFetcher(
            httpClient: client,
            waitForRateLimit: {}
        )

        let page = try await fetcher.fetchBookPageByTitle(title: "示例图书", author: "示例作者")

        #expect(await client.paths == ["/j/subject_suggest", "/subject/1", "/subject/2"])
        #expect(page?.title == "示例图书")
        #expect(page?.author == "示例作者")
    }

    @Test("豆瓣书名回退保留可重试网络错误")
    func doubanTitleSearchPreservesNetworkErrors() async {
        let fetcher = DoubanDescriptionFetcher(
            httpClient: ThrowingMetadataHTTPClient(),
            waitForRateLimit: {}
        )

        do {
            _ = try await fetcher.fetchBookPageByTitle(title: "示例图书", author: "示例作者")
            Issue.record("豆瓣网络错误不应被转换成未找到")
        } catch is URLError {
            // Expected retryable transport failure.
        } catch {
            Issue.record("应保留 URLError，实际为 \(error)")
        }
    }

    @Test("豆瓣建议中的外部地址不会成为后续请求目标")
    func doubanTitleSearchRejectsExternalSuggestionURLs() async throws {
        let client = DoubanSuggestionHTTPClient(includeExternalSuggestion: true)
        let fetcher = DoubanDescriptionFetcher(httpClient: client, waitForRateLimit: {})

        let page = try await fetcher.fetchBookPageByTitle(title: "示例图书", author: "示例作者")

        #expect(page?.title == "示例图书")
        #expect(await client.hosts == ["book.douban.com", "book.douban.com", "book.douban.com"])
    }

    @Test("豆瓣书名回退最多检查五个建议候选")
    func doubanTitleSearchCapsSuggestionFanOut() async throws {
        let client = ManyDoubanSuggestionsHTTPClient(candidateCount: 12)
        let fetcher = DoubanDescriptionFetcher(httpClient: client, waitForRateLimit: {})

        let page = try await fetcher.fetchBookPageByTitle(title: "不存在的书", author: "作者")

        #expect(page == nil)
        #expect(await client.requestedSubjectPaths == [
            "/subject/1", "/subject/2", "/subject/3", "/subject/4", "/subject/5"
        ])
    }

}

private actor MetadataLookupRecorder {
    private(set) var values: [BookMetadataSource] = []

    func record(_ source: BookMetadataSource) {
        values.append(source)
    }
}

private struct StubMetadataSource: MetadataSourceLookup {
    let source: BookMetadataSource
    let candidate: BookDraft
    let recorder: MetadataLookupRecorder

    func lookup(draft: BookDraft, missingFields: Set<EnrichmentField>) async -> MetadataSourceLookupResult {
        await recorder.record(source)
        return MetadataSourceLookupResult(candidate: candidate, status: .found)
    }
}

private struct ThrowingMetadataHTTPClient: HTTPDataClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.timedOut)
    }
}

private struct StatusMetadataHTTPClient: HTTPDataClient {
    let statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }
}

private actor OpenLibraryFallbackHTTPClient: HTTPDataClient {
    private(set) var paths: [String] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        paths.append(url.path)
        let data: Data
        switch url.path {
        case "/api/books":
            data = Data("{}".utf8)
        case "/search.json":
            data = Data("""
            {
              "docs": [{
                "title": "示例图书",
                "author_name": ["示例作者"],
                "publisher": ["回退出版社"],
                "number_of_pages_median": 288,
                "publish_year": [2024],
                "isbn": ["9787020002214"]
              }]
            }
            """.utf8)
        default:
            data = Data()
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct OpenLibraryDescriptionHTTPClient: HTTPDataClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let data = Data("""
        {
          "ISBN:9787020002207": {
            "title": "示例图书",
            "authors": [{"name": "示例作者"}],
            "publishers": [{"name": "示例出版社"}],
            "description": "不应采用的图书简介",
            "author_description": "不应采用的作者简介"
          }
        }
        """.utf8)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor DoubanSuggestionHTTPClient: HTTPDataClient {
    private(set) var paths: [String] = []
    private(set) var hosts: [String] = []
    private let includeExternalSuggestion: Bool

    init(includeExternalSuggestion: Bool = false) {
        self.includeExternalSuggestion = includeExternalSuggestion
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        paths.append(url.path)
        hosts.append(url.host ?? "")
        let data: Data
        switch url.path {
        case "/j/subject_suggest":
            let external = includeExternalSuggestion
                ? "{\"type\":\"b\",\"url\":\"https://127.0.0.1/private\"},"
                : ""
            data = Data("""
            [\(external)
              {"type":"b","url":"https://book.douban.com/subject/1/"},
              {"type":"b","url":"https://book.douban.com/subject/2/"}
            ]
            """.utf8)
        case "/subject/1":
            data = Data(EnrichmentFixtures.doubanSingleTranslatorHTML
                .replacingOccurrences(of: "示例作者", with: "另一位作者").utf8)
        case "/subject/2":
            data = Data(EnrichmentFixtures.doubanSingleTranslatorHTML.utf8)
        default:
            data = Data()
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor DoubanEditionTranslatorHTTPClient: HTTPDataClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let data: Data
        switch url.path {
        case "/isbn/9787536486003":
            data = Data(EnrichmentFixtures.doubanCommemorativeWithoutTranslatorHTML.utf8)
        case "/j/subject_suggest":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "q" })?
                .value
            data = query == "大便书"
                ? Data(#"[{"type":"b","url":"https://book.douban.com/subject/3181927/"}]"#.utf8)
                : Data("[]".utf8)
        case "/subject/3181927":
            data = Data(EnrichmentFixtures.doubanTrailingColonTranslatorHTML.utf8)
        default:
            data = Data()
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor ManyDoubanSuggestionsHTTPClient: HTTPDataClient {
    private let candidateCount: Int
    private(set) var requestedSubjectPaths: [String] = []

    init(candidateCount: Int) {
        self.candidateCount = candidateCount
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let data: Data
        if url.path == "/j/subject_suggest" {
            let suggestions = (1...candidateCount)
                .map { #"{"type":"b","url":"https://book.douban.com/subject/\#($0)/"}"# }
                .joined(separator: ",")
            data = Data("[\(suggestions)]".utf8)
        } else {
            requestedSubjectPaths.append(url.path)
            data = Data(EnrichmentFixtures.doubanSingleTranslatorHTML
                .replacingOccurrences(of: "示例图书", with: "其他图书")
                .utf8)
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct GoodreadsStructuredHTTPClient: HTTPDataClient {
    let author: String
    let authorDescription: String
    let isbn: String?

    init(
        author: String = "示例作者",
        authorDescription: String = "示例作者的可靠结构化简介。",
        isbn: String? = "9787020002207"
    ) {
        self.author = author
        self.authorDescription = authorDescription
        self.isbn = isbn
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let body: String
        if url.path == "/search" {
            body = #"<a href="/book/show/12345">示例图书</a>"#
        } else {
            let isbnProperty = isbn.map { #""isbn": "\#($0)","# } ?? ""
            body = """
            <html><head>
            <script type="application/ld+json">
            {
              "name": "示例图书",
              "author": {
                "name": "\(author)",
                "description": "\(authorDescription)"
              },
              \(isbnProperty)
              "publisher": {"name": "示例出版社"},
              "datePublished": "2024-03-15",
              "numberOfPages": 320,
              "offers": {"price": "58.00", "priceCurrency": "CNY"}
            }
            </script>
            </head><body></body></html>
            """
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private actor GoodreadsRejectedISBNFallbackHTTPClient: HTTPDataClient {
    private let directISBN: String?
    private(set) var paths: [String] = []

    init(directISBN: String?) {
        self.directISBN = directISBN
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        paths.append(url.path)

        let body: String
        switch url.path {
        case "/book/isbn/9787020002207":
            let isbnProperty = directISBN.map { #""isbn": "\#($0)","# } ?? ""
            body = Self.bookHTML(
                isbnProperty: isbnProperty,
                publisher: "不应接受的出版社"
            )
        case "/search":
            body = #"<a href="/book/show/67890">示例图书</a>"#
        case "/book/show/67890":
            body = Self.bookHTML(
                isbnProperty: #""isbn": "9787020002214","#,
                publisher: "回退出版社"
            )
        default:
            body = ""
        }

        return (
            Data(body.utf8),
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    private static func bookHTML(isbnProperty: String, publisher: String) -> String {
        """
        <html><head>
        <script type="application/ld+json">
        {
          "name": "示例图书",
          "author": {"name": "示例作者"},
          \(isbnProperty)
          "publisher": {"name": "\(publisher)"},
          "numberOfPages": 288
        }
        </script>
        </head><body></body></html>
        """
    }
}

private struct ISBNLookupChainMismatchHTTPClient: HTTPDataClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let statusCode: Int
        let body: String

        switch url.host {
        case "book.douban.com":
            statusCode = 404
            body = ""
        case "openlibrary.org":
            statusCode = 200
            body = "{}"
        case "www.googleapis.com":
            statusCode = 200
            body = #"{"items":[]}"#
        case "www.goodreads.com":
            statusCode = 200
            body = """
            <html><head><script type="application/ld+json">
            {
              "name": "另一册书",
              "author": {"name": "另一位作者"},
              "isbn": "9787020002214"
            }
            </script></head><body></body></html>
            """
        default:
            statusCode = 404
            body = ""
        }

        return (
            Data(body.utf8),
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private struct GoogleBooksIdentityHTTPClient: HTTPDataClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let statusCode: Int
        let body: String

        switch url.host {
        case "book.douban.com":
            statusCode = 404
            body = ""
        case "openlibrary.org":
            statusCode = 200
            body = "{}"
        case "www.googleapis.com":
            statusCode = 200
            body = #"{"items":[{"volumeInfo":{"title":"示例图书","authors":["示例作者"],"industryIdentifiers":[{"type":"ISBN_13","identifier":"9787020002207"}]}}]}"#
        default:
            statusCode = 404
            body = ""
        }

        return (
            Data(body.utf8),
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
