import Foundation

enum EnrichmentField: String, CaseIterable, Hashable, Sendable {
    case title
    case author
    case translator
    case publisher
    case publishDate
    case totalPages
    case price
    case bookDescription
    case authorDescription
    case aiIntroduction

    var jsonKey: String {
        switch self {
        case .publishDate: return "publish_date"
        case .totalPages: return "total_pages"
        case .bookDescription: return "book_description"
        case .authorDescription: return "author_description"
        case .aiIntroduction: return "ai_introduction"
        default: return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .title: return "书名"
        case .author: return "作者"
        case .translator: return "译者"
        case .publisher: return "出版社"
        case .publishDate: return "出版日期"
        case .totalPages: return "页数"
        case .price: return "定价"
        case .bookDescription: return "图书简介"
        case .authorDescription: return "作者简介"
        case .aiIntroduction: return "AI简介"
        }
    }
}

struct EnrichmentRejectionDetail: Equatable, Identifiable, Sendable {
    let field: EnrichmentField
    let reason: String

    var id: EnrichmentField { field }
    var fieldName: String { field.displayName }
}

enum EnrichmentMode: Sendable {
    case full
    case aiOnly
    case aiIntroductionOnly
}

enum EnrichmentTermination: Equatable, Sendable {
    case completed
    case cancelled
}

struct EnrichmentOutcome: Equatable, Sendable {
    let originalDraft: BookDraft
    var draft: BookDraft
    var sourceReports: [MetadataSourceReport]
    var aiStatus: LookupSourceStatus
    var evidence: [EnrichmentField: [URL]]
    var rejections: [EnrichmentField: String]
    var tokenUsage: AITokenUsage
    var termination: EnrichmentTermination

    init(
        originalDraft: BookDraft,
        draft: BookDraft,
        sourceReports: [MetadataSourceReport] = [],
        aiStatus: LookupSourceStatus = .notAttempted,
        evidence: [EnrichmentField: [URL]] = [:],
        rejections: [EnrichmentField: String] = [:],
        tokenUsage: AITokenUsage = .unknown,
        termination: EnrichmentTermination = .completed
    ) {
        self.originalDraft = originalDraft
        self.draft = draft
        self.sourceReports = sourceReports
        self.aiStatus = aiStatus
        self.evidence = evidence
        self.rejections = rejections
        self.tokenUsage = tokenUsage
        self.termination = termination
    }

    var changedFields: Set<EnrichmentField> {
        Set(EnrichmentField.allCases.filter { !originalDraft.hasSameValue(as: draft, for: $0) })
    }

    var rejectionDetails: [EnrichmentRejectionDetail] {
        EnrichmentField.allCases.compactMap { field in
            rejections[field].map { EnrichmentRejectionDetail(field: field, reason: $0) }
        }
    }

    var aiIssueDescription: String? {
        switch aiStatus {
        case .retryableFailure, .fatalFailure, .validationRejected, .error:
            return aiStatus.displayText
        case .notAttempted, .found, .noNewFields, .notFound, .cancelled:
            return nil
        }
    }
}
