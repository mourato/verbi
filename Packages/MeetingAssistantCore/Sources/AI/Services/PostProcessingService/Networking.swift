import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

extension PostProcessingService {
    struct ProviderRequestContext {
        let transcription: String
        let prompt: PostProcessingPrompt
        let mode: IntelligenceKernelMode
        let selectionOverride: EnhancementsAISelection?
        let systemPromptOverride: String?
        let timeoutSeconds: TimeInterval
        let requestConfig: AIConfiguration
        let traceContext: RequestTraceContext
        let attempt: Int
        let useLiveSettings: Bool
        let outputLanguageID: String?
    }

    struct CustomProviderRequestContext {
        let mode: IntelligenceKernelMode
        let selectionOverride: EnhancementsAISelection?
        let systemPrompt: String
        let userContent: String
        let timeoutSeconds: TimeInterval
        let requestConfig: AIConfiguration
        let traceContext: RequestTraceContext
        let attempt: Int
        let useLiveSettings: Bool
    }

    // MARK: - Request/Response

    func performAIRequest(context: ProviderRequestContext) async throws -> String {
        let requestStartedAt = Date()
        let config = context.requestConfig
        let apiKey = try getAPIKey(
            selectionOverride: context.selectionOverride,
            mode: context.mode,
            provider: config.provider,
            useLiveSettings: context.useLiveSettings
        )

        let requestPrompts = requestPrompts(for: context, config: config)

        let request = ProviderHTTPClient.Request(
            provider: config.provider,
            baseURL: config.baseURL,
            model: config.selectedModel,
            apiKey: apiKey,
            systemMessage: requestPrompts.systemPrompt,
            userMessage: requestPrompts.userPrompt,
            maxTokens: Constants.maxTokens,
            anthropicAPIVersion: Constants.anthropicAPIVersion,
            timeoutSeconds: context.timeoutSeconds
        )

        AppLogger.debug(
            "Sending post-processing request",
            category: .transcriptionEngine,
            extra: traceExtra(
                from: context.traceContext,
                attempt: context.attempt,
                elapsedMilliseconds: nil,
                extra: ["url": sanitizedURLForLogging(URL(string: config.baseURL) ?? URL(fileURLWithPath: ""))]
            )
        )

        do {
            let output = try await providerHTTPClient.send(request)
            AppLogger.debug(
                "Post-processing provider request succeeded",
                category: .transcriptionEngine,
                extra: traceExtra(
                    from: context.traceContext,
                    attempt: context.attempt,
                    elapsedMilliseconds: Date().timeIntervalSince(requestStartedAt) * 1000
                )
            )
            return output
        } catch let transportError as ProviderHTTPClientError {
            throw postProcessingError(for: transportError)
        }
    }

    private func requestPrompts(
        for context: ProviderRequestContext,
        config: AIConfiguration
    ) -> AIPromptTemplates.RequestPrompts {
        AIPromptTemplates.requestPrompts(
            transcription: context.transcription,
            prompt: context.prompt,
            mode: context.mode,
            selectedModel: config.selectedModel,
            baseSystemPrompt: baseSystemPromptOverride(
                context.systemPromptOverride,
                mode: context.mode,
                useLiveSettings: context.useLiveSettings
            ),
            promptContentTransformer: { cleanPrompt in
                guard self.shouldApplyMeetingLanguagePreference(mode: context.mode, prompt: context.prompt) else {
                    return cleanPrompt
                }
                return self.applyMeetingLanguagePreferenceIfNeeded(
                    to: cleanPrompt,
                    mode: context.mode,
                    outputLanguageID: context.outputLanguageID
                )
            }
        )
    }

    func performCustomAIRequest(context: CustomProviderRequestContext) async throws -> String {
        let requestStartedAt = Date()
        let config = context.requestConfig
        let apiKey = try getAPIKey(
            selectionOverride: context.selectionOverride,
            mode: context.mode,
            provider: config.provider,
            useLiveSettings: context.useLiveSettings
        )

        let request = ProviderHTTPClient.Request(
            provider: config.provider,
            baseURL: config.baseURL,
            model: config.selectedModel,
            apiKey: apiKey,
            systemMessage: context.systemPrompt,
            userMessage: context.userContent,
            maxTokens: Constants.maxTokens,
            anthropicAPIVersion: Constants.anthropicAPIVersion,
            timeoutSeconds: context.timeoutSeconds
        )

        do {
            let output = try await providerHTTPClient.send(request)
            AppLogger.debug(
                "Custom post-processing provider request succeeded",
                category: .transcriptionEngine,
                extra: traceExtra(
                    from: context.traceContext,
                    attempt: context.attempt,
                    elapsedMilliseconds: Date().timeIntervalSince(requestStartedAt) * 1000
                )
            )
            return output
        } catch let transportError as ProviderHTTPClientError {
            throw postProcessingError(for: transportError)
        }
    }

    private func postProcessingError(for transportError: ProviderHTTPClientError) -> PostProcessingError {
        switch transportError {
        case .invalidURL:
            .invalidURL
        case .noAPIConfigured:
            .noAPIConfigured
        case .invalidResponse:
            .invalidResponse
        case let .apiError(message):
            .apiError(message)
        }
    }

    func shouldRetry(error: Error) -> Bool {
        if (error as NSError).domain == NSURLErrorDomain {
            let code = (error as NSError).code
            if code == NSURLErrorTimedOut ||
                code == NSURLErrorNetworkConnectionLost ||
                code == NSURLErrorCannotConnectToHost
            {
                return true
            }
        }

        if case let PostProcessingError.apiError(message) = error,
           message.contains("429") || message.contains("HTTP 5")
        {
            return true
        }

        if case let PostProcessingError.requestFailed(underlyingError) = error {
            return shouldRetry(error: underlyingError)
        }

        return false
    }

    func getAPIKey(
        selectionOverride: EnhancementsAISelection?,
        mode: IntelligenceKernelMode,
        provider: AIProvider,
        useLiveSettings: Bool = true
    ) throws -> String {
        if useLiveSettings {
            if let selectionOverride,
               let modeKey = settings.enhancementsAPIKey(for: selectionOverride),
               !modeKey.isEmpty
            {
                return modeKey
            }

            if let modeKey = settings.enhancementsAPIKey(for: mode), !modeKey.isEmpty {
                return modeKey
            }
        } else if let registrationID = selectionOverride?.registrationID,
                  let registrationKey = try? KeychainManager.retrieveAPIKey(for: registrationID),
                  !registrationKey.isEmpty
        {
            return registrationKey
        }

        guard let apiKey = try? KeychainManager.retrieveAPIKey(for: provider), !apiKey.isEmpty else {
            throw PostProcessingError.noAPIConfigured
        }
        return apiKey
    }

    private func baseSystemPromptOverride(
        _ systemPromptOverride: String?,
        mode: IntelligenceKernelMode,
        useLiveSettings: Bool
    ) -> String? {
        switch mode {
        case .dictation:
            systemPromptOverride
        case .meeting, .assistant:
            systemPromptOverride ?? (useLiveSettings ? settings.systemPrompt : nil)
        }
    }

    private func shouldApplyMeetingLanguagePreference(
        mode: IntelligenceKernelMode,
        prompt: PostProcessingPrompt
    ) -> Bool {
        guard mode == .meeting else { return false }
        return !prompt.promptText.contains("<INTERNAL_MEETING_TYPE_CLASSIFIER>")
    }

    private func applyMeetingLanguagePreferenceIfNeeded(
        to prompt: String,
        mode: IntelligenceKernelMode,
        outputLanguageID: String?
    ) -> String {
        guard mode == .meeting else { return prompt }

        guard let languageID = outputLanguageID,
              let language = DictationOutputLanguage(rawValue: languageID)
        else {
            return prompt
        }
        let languageInstruction = if language == .original {
            """
            <OUTPUT_LANGUAGE>
            The final summary must be written in the same language spoken in the meeting transcription.
            </OUTPUT_LANGUAGE>
            """
        } else {
            """
            <OUTPUT_LANGUAGE>
            Translate the final output to \(language.instructionDisplayName). This requirement overrides any instruction that says to keep the original language.
            </OUTPUT_LANGUAGE>
            """
        }
        return [prompt, languageInstruction].joined(separator: "\n\n")
    }

    func sanitizedURLForLogging(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.map { item in
                URLQueryItem(name: item.name, value: "REDACTED")
            }
        }

        return components.url?.absoluteString ?? url.absoluteString
    }
}
