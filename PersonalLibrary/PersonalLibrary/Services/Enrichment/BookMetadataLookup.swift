import Foundation

enum BookMetadataSource: String, CaseIterable, Sendable {
    case douban = "豆瓣"
    case goodreads = "Goodreads"
    case openLibrary = "Open Library"

    fileprivate var priority: Int {
        switch self {
        case .douban: return 0
        case .goodreads: return 1
        case .openLibrary: return 2
        }
    }

    var allowedFields: Set<EnrichmentField> {
        switch self {
        case .douban:
            return Set(EnrichmentField.allCases).subtracting([.aiIntroduction])
        case .goodreads:
            return [.title, .author, .publisher, .publishDate, .totalPages, .price,
                    .bookDescription, .authorDescription]
        case .openLibrary:
            return [.title, .author, .publisher, .publishDate, .totalPages]
        }
    }
}

struct MetadataSourceLookupResult: Sendable {
    let candidate: BookDraft?
    let status: LookupSourceStatus
}

struct MetadataSourceReport: Equatable, Sendable {
    let source: BookMetadataSource
    let status: LookupSourceStatus
}

struct MetadataLookupOutcome: Sendable {
    let draft: BookDraft
    let sourceReports: [MetadataSourceReport]
}

protocol MetadataSourceLookup: Sendable {
    var source: BookMetadataSource { get }
    func lookup(draft: BookDraft, missingFields: Set<EnrichmentField>) async -> MetadataSourceLookupResult
}

protocol BookMetadataLookup: Sendable {
    func lookup(draft: BookDraft, missingFields: Set<EnrichmentField>) async -> MetadataLookupOutcome
}

struct SequentialBookMetadataLookup: BookMetadataLookup, Sendable {
    private let sources: [any MetadataSourceLookup]

    init(sources: [any MetadataSourceLookup]) {
        self.sources = sources.sorted { $0.source.priority < $1.source.priority }
    }

    func lookup(draft: BookDraft, missingFields: Set<EnrichmentField>) async -> MetadataLookupOutcome {
        var current = draft
        var reports: [MetadataSourceReport] = []

        for source in sources {
            if Task.isCancelled {
                reports.append(MetadataSourceReport(source: source.source, status: .cancelled))
                break
            }

            let targets = missingFields
                .intersection(current.missingFields)
                .intersection(source.source.allowedFields)
            guard !targets.isEmpty else {
                reports.append(MetadataSourceReport(source: source.source, status: .notAttempted))
                continue
            }

            let sourceResult = await source.lookup(draft: current, missingFields: targets)
            guard let candidate = sourceResult.candidate else {
                reports.append(MetadataSourceReport(source: source.source, status: sourceResult.status))
                continue
            }

            let merged = current.fillingMissingFields(from: candidate, limitedTo: targets)
            let accepted = merged != current
            current = merged
            let status: LookupSourceStatus
            if !accepted, sourceResult.status == .found {
                status = .validationRejected("来源未返回可合入字段")
            } else {
                status = sourceResult.status
            }
            reports.append(MetadataSourceReport(
                source: source.source,
                status: accepted ? .found : status
            ))
        }

        return MetadataLookupOutcome(draft: current, sourceReports: reports)
    }
}
