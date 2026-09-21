import Foundation

struct AIEnrichmentOutcome: Sendable {
    let draft: BookDraft
    let status: LookupSourceStatus
    let evidence: [EnrichmentField: [URL]]
    let rejections: [EnrichmentField: String]
    let tokenUsage: AITokenUsage
}

protocol AIEnriching: Sendable {
    func enrich(draft: BookDraft, targets: Set<EnrichmentField>) async -> AIEnrichmentOutcome
}

struct AIEnrichmentService: AIEnriching, Sendable {
    private let client: any AICompletionClient
    private let config: AIConfig
    private let factTimeout: Duration
    private let introductionTimeout: Duration

    init(
        client: any AICompletionClient,
        config: AIConfig,
        factTimeout: Duration = .seconds(60),
        introductionTimeout: Duration = .seconds(600)
    ) {
        self.client = client
        self.config = config
        self.factTimeout = factTimeout
        self.introductionTimeout = introductionTimeout
    }

    func enrich(draft: BookDraft, targets: Set<EnrichmentField>) async -> AIEnrichmentOutcome {
        guard config.isAvailable else {
            return AIEnrichmentOutcome(
                draft: draft,
                status: .notAttempted,
                evidence: [:],
                rejections: [:],
                tokenUsage: .unknown
            )
        }

        var current = draft
        var evidence: [EnrichmentField: [URL]] = [:]
        var rejections: [EnrichmentField: String] = [:]
        var usage = AITokenUsage.accumulator
        var finalStatus: LookupSourceStatus = .notFound
        defer {
            if !evidence.isEmpty {
                AppLogger.info(
                    AIResearchSourceValidator.verificationDisclaimer,
                    category: "AIEnrichment"
                )
            }
        }

        let factTargets = targets
            .intersection(current.missingFields)
            .subtracting([.aiIntroduction])
        if !factTargets.isEmpty {
            let factClock = ContinuousClock()
            let factDeadline = factClock.now.advanced(by: factTimeout)
            let outputTokenBudgets = [4_096, 8_192]
            for (attempt, outputTokenBudget) in outputTokenBudgets.enumerated() {
                do {
                    let remainingTimeout = factClock.now.duration(to: factDeadline)
                    guard remainingTimeout > .zero else {
                        throw AIEnrichmentTimeoutError.timedOut
                    }
                    let response = try await complete(
                        request: AICompletionRequest(
                            messages: [
                                AIChatMessage(
                                    role: "user",
                                    content: AIEnrichmentContract.retrievalPrompt(for: current, targets: factTargets)
                                )
                            ],
                            temperature: 0,
                            maximumOutputTokens: outputTokenBudget,
                            enableThinking: false,
                            timeoutInterval: Self.timeInterval(from: remainingTimeout)
                        ),
                        timeout: remainingTimeout
                    )
                    guard factClock.now < factDeadline else {
                        throw AIEnrichmentTimeoutError.timedOut
                    }
                    usage.add(response.usage)
                    if response.reachedOutputLimit {
                        finalStatus = .validationRejected(Self.outputLimitMessage)
                        if attempt + 1 < outputTokenBudgets.count {
                            continue
                        }
                        break
                    }
                    let validated = try AIEnrichmentContract.validateRetrievalResponse(
                        response.content,
                        for: current,
                        endpoint: config.endpoint,
                        requestedFields: factTargets
                    )
                    let merged = current.fillingMissingFields(from: validated.candidate, limitedTo: factTargets)
                    if merged != current {
                        finalStatus = .found
                    } else if !validated.rejections.isEmpty {
                        finalStatus = .validationRejected("AI 返回字段未通过证据或格式验证")
                    } else {
                        finalStatus = .notFound
                    }
                    current = merged
                    evidence.merge(validated.evidence) { _, new in new }
                    rejections.merge(validated.rejections) { _, new in new }
                    break
                } catch let error as AIEnrichmentContractError {
                    finalStatus = .validationRejected(String(describing: error))
                    if error == .invalidJSON, attempt + 1 < outputTokenBudgets.count {
                        continue
                    }
                    break
                } catch {
                    usage.add(.unknown)
                    finalStatus = Self.status(for: error)
                    if case .cancelled = finalStatus {
                        return AIEnrichmentOutcome(
                            draft: current,
                            status: finalStatus,
                            evidence: evidence,
                            rejections: rejections,
                            tokenUsage: usage
                        )
                    }
                    break
                }
            }

            switch finalStatus {
            case .retryableFailure, .fatalFailure, .cancelled, .error:
                return AIEnrichmentOutcome(
                    draft: current,
                    status: finalStatus,
                    evidence: evidence,
                    rejections: rejections,
                    tokenUsage: usage
                )
            case .notAttempted, .found, .notFound, .validationRejected:
                break
            }
        }

        if targets.contains(.aiIntroduction), current.missingFields.contains(.aiIntroduction) {
            let completionTokenBudgets = [12_288, 16_384]
            var previousFailure: String?
            for (attempt, completionTokenBudget) in completionTokenBudgets.enumerated() {
                do {
                    let response = try await complete(
                        request: AICompletionRequest(
                            messages: [
                                AIChatMessage(
                                    role: "user",
                                    content: AIIntroductionContract.prompt(
                                        for: current,
                                        previousFailure: previousFailure
                                    )
                                )
                            ],
                            maximumCompletionTokens: completionTokenBudget,
                            enableThinking: true,
                            thinkingBudget: 4_096,
                            timeoutInterval: Self.timeInterval(from: introductionTimeout)
                        ),
                        timeout: introductionTimeout
                    )
                    usage.add(response.usage)
                    if response.reachedOutputLimit {
                        previousFailure = Self.outputLimitMessage
                        rejections[.aiIntroduction] = Self.outputLimitMessage
                        finalStatus = .validationRejected(Self.outputLimitMessage)
                        if attempt + 1 < completionTokenBudgets.count {
                            continue
                        }
                        break
                    }
                    let validated = try AIIntroductionContract.validateResponse(
                        response.content,
                        for: current,
                        endpoint: config.endpoint
                    )
                    let candidate = BookDraft(
                        title: "",
                        author: "",
                        aiIntroduction: validated.text
                    )
                    current = current.fillingMissingFields(from: candidate, limitedTo: [.aiIntroduction])
                    evidence[.aiIntroduction] = validated.sources
                    rejections.removeValue(forKey: .aiIntroduction)
                    finalStatus = .found
                    break
                } catch let error as AIIntroductionValidationError {
                    previousFailure = error.localizedDescription
                    rejections[.aiIntroduction] = error.localizedDescription
                    finalStatus = .validationRejected(error.localizedDescription)
                    if attempt + 1 == completionTokenBudgets.count { break }
                } catch {
                    usage.add(.unknown)
                    finalStatus = Self.status(for: error)
                    break
                }
            }
        }

        return AIEnrichmentOutcome(
            draft: current,
            status: finalStatus,
            evidence: evidence,
            rejections: rejections,
            tokenUsage: usage
        )
    }

    private func complete(
        request: AICompletionRequest,
        timeout: Duration
    ) async throws -> AICompletionResponse {
        return try await AIEnrichmentDeadline.run(timeout: timeout) {
            try await client.complete(request: request, config: config)
        }
    }

    private static func timeInterval(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return max(
            0,
            TimeInterval(components.seconds)
                + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }

    private static let outputLimitMessage = "AI 输出达到长度上限，返回内容不完整"

    private static func status(for error: Error) -> LookupSourceStatus {
        if error is CancellationError { return .cancelled }
        if let error = error as? AIEnrichmentTimeoutError {
            return .retryableFailure(error.localizedDescription)
        }
        if let error = error as? AIClientError {
            switch error {
            case .unauthorized, .searchUnsupported, .credentialDestinationMismatch,
                    .endpointUnavailable, .modelUnavailable:
                return .fatalFailure(error.localizedDescription)
            case .server:
                return .retryableFailure(error.localizedDescription)
            case .rateLimited:
                return .fatalFailure(error.localizedDescription)
            case .invalidResponse, .requestTooLarge, .responseTooLarge:
                return .validationRejected(error.localizedDescription)
            }
        }
        if let error = error as? URLError {
            return .retryableFailure(error.localizedDescription)
        }
        if let error = error as? AIEndpointPolicyError {
            switch error {
            case .dnsResolutionFailed:
                return .retryableFailure(error.localizedDescription)
            case .httpsRequired, .credentialsNotAllowed, .fragmentNotAllowed,
                    .missingHost, .privateOrReservedHost:
                return .fatalFailure(error.localizedDescription)
            }
        }
        return .fatalFailure(error.localizedDescription)
    }
}

enum AIEnrichmentTimeoutError: Error, Equatable, LocalizedError {
    case timedOut

    var errorDescription: String? {
        "AI 智能补全超时，已停止；建议改用平台推荐模型后重试"
    }
}

private enum AIEnrichmentDeadline {
    static func run<Value: Sendable>(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        guard timeout > .zero else { throw AIEnrichmentTimeoutError.timedOut }
        return try await AsyncHardDeadline.run(
            timeout: timeout,
            timeoutError: AIEnrichmentTimeoutError.timedOut,
            operation: operation
        )
    }
}
