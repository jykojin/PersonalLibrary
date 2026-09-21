import Foundation

protocol BookEnriching: Sendable {
    func enrich(
        _ draft: BookDraft,
        mode: EnrichmentMode,
        localAuthorDescription: String?
    ) async -> EnrichmentOutcome
}

struct EnrichmentCoordinator: BookEnriching, Sendable {
    private let metadataLookup: any BookMetadataLookup
    private let aiEnricher: (any AIEnriching)?

    init(metadataLookup: any BookMetadataLookup, aiEnricher: (any AIEnriching)?) {
        self.metadataLookup = metadataLookup
        self.aiEnricher = aiEnricher
    }

    static func live(configStore: AIConfigStore = .shared) -> EnrichmentCoordinator {
        let config = configStore.load()
        let aiEnricher: (any AIEnriching)? = config.isAvailable
            ? AIEnrichmentService(client: OpenAICompatibleAIClient(), config: config)
            : nil
        return EnrichmentCoordinator(
            metadataLookup: SequentialBookMetadataLookup.live(),
            aiEnricher: aiEnricher
        )
    }

    func enrich(
        _ draft: BookDraft,
        mode: EnrichmentMode,
        localAuthorDescription: String?
    ) async -> EnrichmentOutcome {
        var current = draft
        var sourceReports: [MetadataSourceReport] = []

        if mode == .full,
           current.missingFields.contains(.authorDescription),
           let localAuthorDescription = localAuthorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localAuthorDescription.isEmpty,
           !localAuthorDescription.contains("展开全部") {
            let candidate = BookDraft(
                title: "",
                author: "",
                authorDescription: localAuthorDescription
            )
            current = current.fillingMissingFields(from: candidate, limitedTo: [.authorDescription])
        }

        if mode == .full {
            let metadata = await metadataLookup.lookup(
                draft: current,
                missingFields: current.missingFields.subtracting([.aiIntroduction])
            )
            current = metadata.draft
            sourceReports = metadata.sourceReports
            if metadata.sourceReports.contains(where: { $0.status == .cancelled }) {
                return EnrichmentOutcome(
                    originalDraft: draft,
                    draft: current,
                    sourceReports: sourceReports,
                    termination: .cancelled
                )
            }
        }

        let aiTargets: Set<EnrichmentField>
        switch mode {
        case .full, .aiOnly:
            aiTargets = current.missingFields
        case .aiIntroductionOnly:
            aiTargets = current.missingFields.intersection([.aiIntroduction])
        }

        guard !aiTargets.isEmpty, let aiEnricher else {
            return EnrichmentOutcome(
                originalDraft: draft,
                draft: current,
                sourceReports: sourceReports
            )
        }

        let ai = await aiEnricher.enrich(draft: current, targets: aiTargets)
        return EnrichmentOutcome(
            originalDraft: draft,
            draft: ai.draft,
            sourceReports: sourceReports,
            aiStatus: ai.status,
            evidence: ai.evidence,
            rejections: ai.rejections,
            tokenUsage: ai.tokenUsage,
            termination: ai.status == .cancelled ? .cancelled : .completed
        )
    }
}

extension EnrichmentMode: Equatable {}
