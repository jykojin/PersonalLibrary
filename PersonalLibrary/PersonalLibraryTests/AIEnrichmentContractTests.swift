import Foundation
import Testing
@testable import PersonalLibrary

@Suite("AI Enrichment Contract Tests")
struct AIEnrichmentContractTests {
    @Test("AI 字段逐项验证来源且无来源字段被丢弃")
    func acceptsOnlyIndividuallySourcedFields() throws {
        let json = #"""
        {
          "status": "ok",
          "identity": {"matched_title": "示例图书", "matched_author": "示例作者"},
          "fields": {
            "publisher": {"value": "可靠出版社", "sources": ["https://publisher.example/books/1"]},
            "total_pages": {"value": 320, "sources": []}
          }
        }
        """#
        let draft = BookDraft(title: "示例图书", author: "示例作者")

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: draft,
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            requestedFields: [.publisher, .totalPages]
        )

        #expect(result.candidate.publisher == "可靠出版社")
        #expect(result.candidate.totalPages == 0)
        #expect(result.evidence[.publisher] == [URL(string: "https://publisher.example/books/1")!])
        #expect(result.rejections[.totalPages] == "缺少有效来源")
    }

    @Test("AI endpoint 自身、非法 URL 与无效字段值逐字段拒绝")
    func rejectsInvalidEvidenceAndValuesIndependently() throws {
        let json = #"""
        {
          "status": "ok",
          "identity": {"matched_title": "示例图书", "matched_author": "示例作者"},
          "fields": {
            "publisher": {"value": "可靠出版社", "sources": ["https://dashscope.aliyuncs.com/result/1"]},
            "total_pages": {"value": -5, "sources": ["https://catalog.example/book/1"]},
            "price": {"value": "¥59.00", "sources": ["not a url"]}
          }
        }
        """#

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: BookDraft(title: "示例图书", author: "示例作者"),
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            requestedFields: [.publisher, .totalPages, .price]
        )

        #expect(result.candidate.publisher == nil)
        #expect(result.candidate.totalPages == 0)
        #expect(result.candidate.price == nil)
        #expect(result.rejections[.publisher] == "来源 URL 无效")
        #expect(result.rejections[.totalPages] == "字段值无效")
        #expect(result.rejections[.price] == "来源 URL 无效")
    }

    @Test("AI 来源不能用 Endpoint 主机名的尾点别名自证")
    func rejectsEndpointTrailingDotAliasAsEvidence() throws {
        let json = #"""
        {
          "status": "ok",
          "identity": {"matched_title": "示例图书", "matched_author": "示例作者"},
          "fields": {
            "publisher": {
              "value": "不应接受的出版社",
              "sources": ["https://api.example.com./proof"]
            }
          }
        }
        """#

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: BookDraft(title: "示例图书", author: "示例作者"),
            endpoint: URL(string: "https://api.example.com/v1")!,
            requestedFields: [.publisher]
        )

        #expect(result.candidate.publisher == nil)
        #expect(result.rejections[.publisher] == "来源 URL 无效")
    }

    @Test("AI 来源不能用 Endpoint 的等价 IPv6 写法自证")
    func rejectsEquivalentIPv6EndpointAsEvidence() throws {
        let json = #"""
        {
          "status": "ok",
          "identity": {"matched_title": "示例图书", "matched_author": "示例作者"},
          "fields": {
            "publisher": {
              "value": "不应接受的出版社",
              "sources": ["https://[2001:0db8:0000:0000:0000:0000:0000:0001]/proof"]
            }
          }
        }
        """#

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: BookDraft(title: "示例图书", author: "示例作者"),
            endpoint: URL(string: "https://[2001:db8::1]/v1")!,
            requestedFields: [.publisher]
        )

        #expect(result.candidate.publisher == nil)
        #expect(result.rejections[.publisher] == "来源 URL 无效")
    }

    @Test("AI 来源不能用 Endpoint 的历史 IPv4 或映射地址写法自证")
    func rejectsEquivalentLegacyIPv4EndpointAliasesAsEvidence() throws {
        let aliases = [
            "1572395042",
            "0x5db8d822",
            "93.184.55330",
            "[::ffff:93.184.216.34]"
        ]

        for alias in aliases {
            let json = #"{"status":"ok","identity":{"matched_title":"示例图书","matched_author":"示例作者"},"fields":{"publisher":{"value":"不应接受的出版社","sources":["https://\#(alias)/proof"]}}}"#
            let result = try AIEnrichmentContract.validateRetrievalResponse(
                json,
                for: BookDraft(title: "示例图书", author: "示例作者"),
                endpoint: URL(string: "https://93.184.216.34/v1")!,
                requestedFields: [.publisher]
            )

            #expect(result.candidate.publisher == nil, "未拒绝等价地址：\(alias)")
            #expect(result.rejections[.publisher] == "来源 URL 无效")
        }
    }

    @Test("串书结果与 JSON 外附说明均整次拒绝")
    func rejectsIdentityMismatchAndWrappedJSON() {
        let mismatch = #"""
        {"status":"ok","identity":{"matched_title":"另一本书","matched_author":"示例作者"},"fields":{}}
        """#
        #expect(throws: AIEnrichmentContractError.identityMismatch) {
            try AIEnrichmentContract.validateRetrievalResponse(
                mismatch,
                for: BookDraft(title: "示例图书", author: "示例作者"),
                endpoint: URL(string: "https://api.example.com/v1")!,
                requestedFields: [.publisher]
            )
        }

        let wrapped = "检索结果如下：\n" + mismatch
        #expect(throws: AIEnrichmentContractError.invalidJSON) {
            try AIEnrichmentContract.validateRetrievalResponse(
                wrapped,
                for: BookDraft(title: "示例图书", author: "示例作者"),
                endpoint: URL(string: "https://api.example.com/v1")!,
                requestedFields: [.publisher]
            )
        }
    }

    @Test("书名缺失时用 ISBN 锚定身份并允许 AI 补书名")
    func usesISBNIdentityWhenTitleIsMissing() throws {
        let matchingJSON = #"""
        {
          "status": "ok",
          "identity": {
            "matched_title": "ISBN 找到的书",
            "matched_author": "示例作者",
            "matched_isbn": "978-7-0200-0220-7"
          },
          "fields": {
            "title": {
              "value": "ISBN 找到的书",
              "sources": ["https://catalog.example/books/9787020002207"]
            }
          }
        }
        """#
        let draft = BookDraft(title: "", author: "示例作者", isbn: "9787020002207")

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            matchingJSON,
            for: draft,
            endpoint: URL(string: "https://api.example.com/v1")!,
            requestedFields: [.title]
        )

        #expect(result.candidate.title == "ISBN 找到的书")

        let mismatchedJSON = matchingJSON.replacingOccurrences(
            of: "978-7-0200-0220-7",
            with: "978-7-0200-0221-4"
        )
        #expect(throws: AIEnrichmentContractError.identityMismatch) {
            try AIEnrichmentContract.validateRetrievalResponse(
                mismatchedJSON,
                for: draft,
                endpoint: URL(string: "https://api.example.com/v1")!,
                requestedFields: [.title]
            )
        }
    }

    @Test("书名已知时 AI 事实仍必须匹配 ISBN")
    func knownTitleStillRequiresMatchingISBNForFacts() {
        let json = #"""
        {
          "status": "ok",
          "identity": {
            "matched_title": "示例图书",
            "matched_author": "示例作者",
            "matched_isbn": "9787020002214"
          },
          "fields": {
            "publisher": {
              "value": "不应接受的出版社",
              "sources": ["https://catalog.example/books/9787020002214"]
            }
          }
        }
        """#

        #expect(throws: AIEnrichmentContractError.identityMismatch) {
            try AIEnrichmentContract.validateRetrievalResponse(
                json,
                for: BookDraft(
                    title: "示例图书",
                    author: "示例作者",
                    isbn: "9787020002207"
                ),
                endpoint: URL(string: "https://api.example.com/v1")!,
                requestedFields: [.publisher]
            )
        }
    }

    @Test("书名已知时 AI 事实不能缺少 ISBN 身份")
    func knownTitleRejectsMissingISBNForFacts() {
        let json = #"""
        {
          "status": "ok",
          "identity": {
            "matched_title": "示例图书",
            "matched_author": "示例作者"
          },
          "fields": {
            "publisher": {
              "value": "不应接受的出版社",
              "sources": ["https://catalog.example/books/unknown"]
            }
          }
        }
        """#

        #expect(throws: AIEnrichmentContractError.identityMismatch) {
            try AIEnrichmentContract.validateRetrievalResponse(
                json,
                for: BookDraft(
                    title: "示例图书",
                    author: "示例作者",
                    isbn: "9787020002207"
                ),
                endpoint: URL(string: "https://api.example.com/v1")!,
                requestedFields: [.publisher]
            )
        }
    }

    @Test("ISBN 锚定时拒绝与身份声明不一致的书名字段")
    func rejectsTitleFieldThatContradictsIdentity() throws {
        let json = #"""
        {
          "status": "ok",
          "identity": {
            "matched_title": "ISBN 找到的书",
            "matched_author": "示例作者",
            "matched_isbn": "978-7-0200-0220-7"
          },
          "fields": {
            "title": {
              "value": "另一本书",
              "sources": ["https://catalog.example/books/9787020002207"]
            }
          }
        }
        """#

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: BookDraft(title: "", author: "示例作者", isbn: "9787020002207"),
            endpoint: URL(string: "https://api.example.com/v1")!,
            requestedFields: [.title]
        )

        #expect(result.candidate.title.isEmpty)
        #expect(result.rejections[.title] == "字段值与身份不匹配")
    }

    @Test("ISBN 锚定时拒绝与身份声明不一致的作者字段")
    func rejectsAuthorFieldThatContradictsIdentity() throws {
        let json = #"""
        {
          "status": "ok",
          "identity": {
            "matched_title": "ISBN 找到的书",
            "matched_author": "正确作者",
            "matched_isbn": "978-7-0200-0220-7"
          },
          "fields": {
            "author": {
              "value": "另一位作者",
              "sources": ["https://catalog.example/books/9787020002207"]
            }
          }
        }
        """#

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: BookDraft(title: "", author: "", isbn: "9787020002207"),
            endpoint: URL(string: "https://api.example.com/v1")!,
            requestedFields: [.author]
        )

        #expect(result.candidate.author.isEmpty)
        #expect(result.rejections[.author] == "字段值与身份不匹配")
    }

    @Test("AI 定价必须包含大于零且在合理上限内的金额")
    func rejectsPricesOutsideValidRange() throws {
        let prices = ["-1元", "0元", "CNY 1000001"]

        for price in prices {
            let json = #"""
            {
              "status": "ok",
              "identity": {"matched_title": "示例图书", "matched_author": "示例作者"},
              "fields": {
                "price": {
                  "value": "\#(price)",
                  "sources": ["https://catalog.example/books/1"]
                }
              }
            }
            """#

            let result = try AIEnrichmentContract.validateRetrievalResponse(
                json,
                for: BookDraft(title: "示例图书", author: "示例作者"),
                endpoint: URL(string: "https://api.example.com/v1")!,
                requestedFields: [.price]
            )

            #expect(result.candidate.price == nil)
            #expect(result.rejections[.price] == "字段值无效")
        }
    }

    @Test("AI 页数拒绝小数而不是静默截断")
    func rejectsFractionalPageCount() throws {
        let json = #"""
        {
          "status": "ok",
          "identity": {"matched_title": "示例图书", "matched_author": "示例作者"},
          "fields": {
            "total_pages": {
              "value": 320.5,
              "sources": ["https://catalog.example/books/1"]
            }
          }
        }
        """#

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: BookDraft(title: "示例图书", author: "示例作者"),
            endpoint: URL(string: "https://api.example.com/v1")!,
            requestedFields: [.totalPages]
        )

        #expect(result.candidate.totalPages == 0)
        #expect(result.rejections[.totalPages] == "字段值无效")
    }

    @Test("检索提示使用与响应解析一致的字段名并声明完整 JSON 结构")
    func promptScopesRequestedFields() {
        let prompt = AIEnrichmentContract.retrievalPrompt(
            for: BookDraft(title: "示例图书", author: "示例作者", isbn: "9780000000000"),
            targets: [.publisher, .totalPages, .aiIntroduction]
        )

        #expect(prompt.contains(#""requested_fields":["publisher","total_pages"]"#))
        #expect(!prompt.contains("totalPages"))
        #expect(!prompt.contains("aiIntroduction"))
        #expect(prompt.contains(#""status":"ok""#))
        #expect(prompt.contains(#""matched_title":"核实后的书名""#))
        #expect(prompt.contains(#""publisher":{"value":"核实值","sources":["https://来源页面"]}"#))
        #expect(prompt.contains(#""total_pages":{"value":320,"sources":["https://来源页面"]}"#))
        #expect(prompt.contains("不得返回或修改 ISBN、封面、评分、备注"))
        #expect(prompt.contains("即使所有字段都无法确认，也必须返回 status 为 ok"))
        #expect(prompt.contains("fields 返回空对象"))
    }

    @Test("AI 事实字段超过字符配额时逐字段拒绝")
    func rejectsOversizedTextFields() throws {
        let object: [String: Any] = [
            "status": "ok",
            "identity": ["matched_title": "示例图书", "matched_author": "示例作者"],
            "fields": [
                "publisher": [
                    "value": String(repeating: "社", count: 513),
                    "sources": ["https://publisher.example/books/1"]
                ],
                "book_description": [
                    "value": String(repeating: "介", count: 20_001),
                    "sources": ["https://publisher.example/books/1"]
                ],
                "author_description": [
                    "value": String(repeating: "作", count: 20_001),
                    "sources": ["https://publisher.example/authors/1"]
                ]
            ]
        ]
        let json = String(
            data: try JSONSerialization.data(withJSONObject: object),
            encoding: .utf8
        )!

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: BookDraft(title: "示例图书", author: "示例作者"),
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            requestedFields: [.publisher, .bookDescription, .authorDescription]
        )

        #expect(result.candidate.publisher == nil)
        #expect(result.candidate.bookDescription == nil)
        #expect(result.candidate.authorDescription == nil)
        #expect(result.rejections.count == 3)
    }

    @Test("组合附加符不能绕过 AI 事实字段资源长度限制")
    func rejectsOversizedCombiningSequenceInFactField() throws {
        let oversizedPublisher = "社" + String(repeating: "\u{0301}", count: 3_000)
        let object: [String: Any] = [
            "status": "ok",
            "identity": ["matched_title": "示例图书", "matched_author": "示例作者"],
            "fields": [
                "publisher": [
                    "value": oversizedPublisher,
                    "sources": ["https://publisher.example/books/1"]
                ]
            ]
        ]
        let json = String(
            data: try JSONSerialization.data(withJSONObject: object),
            encoding: .utf8
        )!

        let result = try AIEnrichmentContract.validateRetrievalResponse(
            json,
            for: BookDraft(title: "示例图书", author: "示例作者"),
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            requestedFields: [.publisher]
        )

        #expect(result.candidate.publisher == nil)
        #expect(result.rejections[.publisher] == "字段值无效")
    }
}
