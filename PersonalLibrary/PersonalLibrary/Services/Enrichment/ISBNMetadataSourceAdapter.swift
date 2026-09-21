import Foundation

struct ISBNMetadataSourceAdapter: MetadataSourceLookup, Sendable {
    let source: BookMetadataSource
    private let service: ISBNLookupService
    private let doubanFetcher: DoubanDescriptionFetcher

    init(
        source: BookMetadataSource,
        service: ISBNLookupService,
        doubanFetcher: DoubanDescriptionFetcher = DoubanDescriptionFetcher()
    ) {
        self.source = source
        self.service = service
        self.doubanFetcher = doubanFetcher
    }

    func lookup(draft: BookDraft, missingFields: Set<EnrichmentField>) async -> MetadataSourceLookupResult {
        do {
            let cleanISBN = (draft.isbn ?? "")
                .replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)
                .uppercased()
            let hasValidISBN = cleanISBN.count == 10 || cleanISBN.count == 13
            var isbnValidationRejection: LookupSourceStatus?

            if hasValidISBN {
                let result: ISBNLookupResult?
                switch source {
                case .douban:
                    result = try await service.lookupFromDouban(isbn: cleanISBN)
                case .goodreads:
                    result = try await service.lookupFromGoodreads(isbn: cleanISBN)
                case .openLibrary:
                    result = try await service.lookupFromOpenLibrary(isbn: cleanISBN)
                }
                if let result {
                    if !result.isbnIsSourceVerified {
                        isbnValidationRejection = .validationRejected("ISBN 候选缺少来源凭据")
                    } else if !BookIdentityMatcher.isbnMatches(cleanISBN, result.isbn) {
                        isbnValidationRejection = .validationRejected("ISBN 候选与请求 ISBN 不符")
                    } else if !BookIdentityMatcher.matches(
                        requestedTitle: draft.title,
                        requestedAuthor: draft.author,
                        requestedISBN: cleanISBN,
                        candidateTitle: result.title,
                        candidateAuthor: result.author,
                        candidateISBN: result.isbn
                    ) {
                        isbnValidationRejection = .validationRejected("ISBN 候选书名或作者身份不符")
                    } else {
                        return MetadataSourceLookupResult(
                            candidate: Self.draft(from: result),
                            status: .found
                        )
                    }
                }
            }

            guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return MetadataSourceLookupResult(
                    candidate: nil,
                    status: isbnValidationRejection ?? .notFound
                )
            }

            let result: ISBNLookupResult?
            switch source {
            case .douban:
                if let page = try await doubanFetcher.fetchBookPageByTitle(
                    title: draft.title,
                    author: draft.author
                ) {
                    result = Self.result(from: page, isbn: cleanISBN)
                } else {
                    result = nil
                }
            case .goodreads:
                result = try await service.searchGoodreadsByTitle(title: draft.title, author: draft.author)
            case .openLibrary:
                result = try await service.searchOpenLibraryByTitle(title: draft.title, author: draft.author)
            }
            guard let result else {
                return MetadataSourceLookupResult(
                    candidate: nil,
                    status: isbnValidationRejection ?? .notFound
                )
            }
            guard BookIdentityMatcher.matches(
                requestedTitle: draft.title,
                requestedAuthor: draft.author,
                requestedISBN: nil,
                candidateTitle: result.title,
                candidateAuthor: result.author,
                candidateISBN: nil
            ) else {
                return MetadataSourceLookupResult(
                    candidate: nil,
                    status: .validationRejected("书名或作者身份不符")
                )
            }
            return MetadataSourceLookupResult(
                candidate: Self.draft(from: result),
                status: .found
            )
        } catch is CancellationError {
            return MetadataSourceLookupResult(candidate: nil, status: .cancelled)
        } catch let error as URLError {
            return MetadataSourceLookupResult(candidate: nil, status: .retryableFailure(error.localizedDescription))
        } catch {
            return MetadataSourceLookupResult(candidate: nil, status: .fatalFailure(error.localizedDescription))
        }
    }

    private static func draft(from result: ISBNLookupResult) -> BookDraft {
        BookDraft(
            title: result.title,
            author: result.author,
            translator: result.translator,
            isbn: result.isbn,
            publisher: result.publisher,
            publishDate: PublicationDateParser.parse(result.publishDate),
            totalPages: result.totalPages ?? 0,
            price: result.price,
            bookDescription: result.bookDescription,
            authorDescription: result.authorDescription
        )
    }

    private static func result(from page: DoubanBookPage, isbn: String) -> ISBNLookupResult {
        ISBNLookupResult(
            title: page.title,
            author: page.author ?? "未知作者",
            publisher: page.publisher,
            publishDate: page.publishDate,
            totalPages: page.totalPages,
            price: page.price,
            bookDescription: page.bookDescription,
            authorDescription: page.authorDescription,
            translator: page.translator,
            coverImageURL: page.coverImageURL,
            isbn: page.isbn ?? isbn,
            isbnIsSourceVerified: page.isbn?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        )
    }
}

extension SequentialBookMetadataLookup {
    static func live(service: ISBNLookupService = ISBNLookupService()) -> SequentialBookMetadataLookup {
        SequentialBookMetadataLookup(sources: BookMetadataSource.allCases.map {
            ISBNMetadataSourceAdapter(source: $0, service: service)
        })
    }
}
