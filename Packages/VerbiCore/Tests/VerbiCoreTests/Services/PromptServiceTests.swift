@testable import VerbiCore
import XCTest

final class PromptServiceTests: XCTestCase {

    func testStrategyForStandup() {
        let strategy = PromptService.shared.strategy(for: .standup)
        XCTAssertTrue(strategy is StandupMeetingStrategy)
        XCTAssertEqual(strategy.promptObject().icon, "figure.stand")
        XCTAssertEqual(strategy.promptObject().title, "Standup Report")
    }

    func testStrategyForDesignReview() {
        let strategy = PromptService.shared.strategy(for: .designReview)
        XCTAssertTrue(strategy is DesignReviewStrategy)
        XCTAssertEqual(strategy.promptObject().icon, "paintbrush")
        XCTAssertEqual(strategy.promptObject().title, "Design Review")
    }

    func testStrategyForGeneral() {
        let strategy = PromptService.shared.strategy(for: .general)
        XCTAssertTrue(strategy is GeneralMeetingStrategy)
        XCTAssertEqual(strategy.promptObject().icon, "doc.text")
        XCTAssertEqual(strategy.promptObject().title, "General Summary")
    }

    func testStrategyForAutodetectDefaultsToGeneral() {
        // Autodetect is implemented at a higher level (classification), but the PromptService strategy
        // for `.autodetect` should still default to General as a safe fallback.
        let strategy = PromptService.shared.strategy(for: .autodetect)
        XCTAssertTrue(strategy is GeneralMeetingStrategy)
    }

    func testStrategyGeneratesPromptWithoutTranscriptionPlaceholder() {
        // Ensuring we removed the interpolation based on our latest fix
        let strategy = PromptService.shared.strategy(for: .general)
        let promptText = strategy.userPrompt(for: "Valid Transcription")

        // It should NOT contain the transcription itself, as that is handled by AIPromptTemplates
        XCTAssertFalse(promptText.contains("Valid Transcription"))
        XCTAssertTrue(promptText.contains("Key Topics Discussed"))
    }

    func testExtractSiteOrAppPriorityInstructions_WhenPresent_ReturnsCleanPromptAndExtractedBlock() {
        let prompt = """
        Base instructions.

        <SITE_OR_APP_PRIORITY_INSTRUCTIONS>
        Always write in lowercase.
        </SITE_OR_APP_PRIORITY_INSTRUCTIONS>
        """

        let extracted = AIPromptTemplates.extractSiteOrAppPriorityInstructions(from: prompt)

        XCTAssertEqual(extracted.cleanPrompt, "Base instructions.")
        XCTAssertEqual(extracted.priorityInstructions, "Always write in lowercase.")
    }

    func testSystemPrompt_WithPriorityInstructions_AppendsExplicitPrecedence() {
        let system = AIPromptTemplates.systemPrompt(
            basePrompt: "Base system prompt",
            priorityInstructions: "Always write in lowercase.",
        )

        XCTAssertTrue(system.contains("Base system prompt"))
        XCTAssertTrue(system.contains("highest priority"))
        XCTAssertTrue(system.contains("Always write in lowercase."))
    }

    func testUserMessage_WithPriorityInstructions_DoesNotDuplicatePriorityBlock() {
        let userMessage = AIPromptTemplates.userMessage(
            transcription: "hello world",
            prompt: "Summarize",
            priorityInstructions: "Always write in lowercase.",
        )

        XCTAssertTrue(userMessage.contains("<TRANSCRIPTION>"))
        XCTAssertTrue(userMessage.contains("<INSTRUCTIONS>"))
        XCTAssertFalse(userMessage.contains("<SITE_APP_PRIORITY>"))
        XCTAssertFalse(userMessage.contains("Always write in lowercase."))
    }

    func testUserMessage_BlockOrder_PlacesTranscriptionAfterContextMetadata() throws {
        let userMessage = AIPromptTemplates.userMessage(
            transcription: "hello world",
            prompt: "Summarize",
            priorityInstructions: "Always write in lowercase.",
            contextMetadata: "Active app: VSCode",
        )

        let instructionsRange = try XCTUnwrap(userMessage.range(of: "<INSTRUCTIONS>"))
        let contextRange = try XCTUnwrap(userMessage.range(of: "<CONTEXT_METADATA>"))
        let transcriptionRange = try XCTUnwrap(userMessage.range(of: "<TRANSCRIPTION>"))

        XCTAssertLessThan(instructionsRange.lowerBound, contextRange.lowerBound)
        XCTAssertLessThan(contextRange.lowerBound, transcriptionRange.lowerBound)
    }

    func testDictationHasExplicitNonMeetingSystemPrompt() {
        let dictationPrompt = AIPromptTemplates.dictationSystemPrompt
        XCTAssertFalse(dictationPrompt.contains("meeting"))
        XCTAssertTrue(dictationPrompt.contains("transcription enhancer"))
        XCTAssertTrue(dictationPrompt.contains("questions, requests, or commands"))
        XCTAssertTrue(dictationPrompt.contains("Return only the final cleaned text"))
    }

    func testSimpleModelDictationHasShortSystemPrompt() {
        let simplePrompt = AIPromptTemplates.simpleModelDictationSystemPrompt
        XCTAssertTrue(simplePrompt.contains("You are not a chatbot"))
        XCTAssertTrue(simplePrompt.contains("Return only the cleaned text"))
        XCTAssertFalse(simplePrompt.contains("meeting"))
    }

    func testSimpleDictationUserMessageHasOnlyTranscriptAndOptionalContext() {
        let userMessage = AIPromptTemplates.simpleDictationUserMessage(transcription: "hello world")
        XCTAssertTrue(userMessage.contains("<TRANSCRIPT>"))
        XCTAssertFalse(userMessage.contains("<INSTRUCTIONS>"))
        XCTAssertFalse(userMessage.contains("Process the transcription"))
    }

    func testSimpleDictationUserMessageIncludesContextWhenProvided() {
        let userMessage = AIPromptTemplates.simpleDictationUserMessage(
            transcription: "hello world",
            contextMetadata: "Active app: VSCode",
        )
        XCTAssertTrue(userMessage.contains("<CONTEXT_METADATA>"))
        XCTAssertTrue(userMessage.contains("Active app: VSCode"))
        XCTAssertTrue(userMessage.contains("<TRANSCRIPT>"))
    }

    func testSimpleDictationUserMessageDoesNotDuplicateExistingContext() {
        let userMessage = AIPromptTemplates.simpleDictationUserMessage(
            transcription: "hello world\n\n<CONTEXT_METADATA>\nExisting context\n</CONTEXT_METADATA>",
            contextMetadata: "Active app: VSCode",
        )
        let contextTagCount = userMessage.components(separatedBy: "<CONTEXT_METADATA>").count - 1
        XCTAssertEqual(contextTagCount, 1)
    }

    func testSimpleDictationUserMessageSeparatesEmbeddedContextFromTranscript() throws {
        let userMessage = AIPromptTemplates.simpleDictationUserMessage(
            transcription: """
            hello world

            <CONTEXT_METADATA>
            CONTEXT_METADATA
            <ACTIVE_APP>
            Safari
            </ACTIVE_APP>
            </CONTEXT_METADATA>
            """,
        )

        let contextEnd = try XCTUnwrap(userMessage.range(of: "</CONTEXT_METADATA>"))
        let transcriptStart = try XCTUnwrap(userMessage.range(of: "<TRANSCRIPT>"))
        let transcriptEnd = try XCTUnwrap(userMessage.range(of: "</TRANSCRIPT>"))
        let transcriptBody = String(userMessage[transcriptStart.upperBound..<transcriptEnd.lowerBound])

        XCTAssertLessThan(contextEnd.upperBound, transcriptStart.lowerBound)
        XCTAssertEqual(userMessage.components(separatedBy: "<CONTEXT_METADATA>").count - 1, 1)
        XCTAssertFalse(transcriptBody.contains("CONTEXT_METADATA"))
        XCTAssertFalse(transcriptBody.contains("<ACTIVE_APP>"))
        XCTAssertTrue(transcriptBody.contains("hello world"))
    }

    func testIsSimpleModelDetectsGptOss120b() {
        XCTAssertTrue(AIPromptTemplates.isSimpleModel("gpt-oss-120b"))
        XCTAssertTrue(AIPromptTemplates.isSimpleModel("GPT-OSS-120B"))
        XCTAssertFalse(AIPromptTemplates.isSimpleModel("prefix-gpt-oss-120b"))
        XCTAssertFalse(AIPromptTemplates.isSimpleModel("gpt-4o"))
        XCTAssertFalse(AIPromptTemplates.isSimpleModel("claude-3-5-sonnet"))
        XCTAssertFalse(AIPromptTemplates.isSimpleModel(""))
    }

    func testRequestPrompts_DictationSimpleModelWithDefaultPromptUsesSimpleStrategy() {
        let requestPrompts = AIPromptTemplates.requestPrompts(
            transcription: "hello world",
            prompt: .defaultPrompt,
            mode: .dictation,
            selectedModel: "gpt-oss-120b",
            contextMetadata: "Active app: VSCode",
        )

        XCTAssertEqual(requestPrompts.systemPrompt, AIPromptTemplates.simpleModelDictationSystemPrompt)
        XCTAssertTrue(requestPrompts.userPrompt.contains("<TRANSCRIPT>"))
        XCTAssertTrue(requestPrompts.userPrompt.contains("<CONTEXT_METADATA>"))
        XCTAssertFalse(requestPrompts.userPrompt.contains("<INSTRUCTIONS>"))
    }

    func testRequestPrompts_DictationSimpleModelWithFlexKeepsAdvancedPrompt() {
        let requestPrompts = AIPromptTemplates.requestPrompts(
            transcription: "hello world",
            prompt: .flex,
            mode: .dictation,
            selectedModel: "gpt-oss-120b",
        )

        XCTAssertTrue(requestPrompts.systemPrompt.hasPrefix(AIPromptTemplates.dictationSystemPrompt))
        XCTAssertTrue(requestPrompts.systemPrompt.contains("<USER_INSTRUCTIONS>"))
        XCTAssertTrue(requestPrompts.systemPrompt.contains("TWO-PASS ARTIFACT HANDLING"))
        XCTAssertTrue(requestPrompts.userPrompt.contains("<TRANSCRIPT>"))
        XCTAssertFalse(requestPrompts.userPrompt.contains("<INSTRUCTIONS>"))
    }

    func testRequestPrompts_DictationSimpleModelWithCustomPromptKeepsCustomPrompt() {
        let customPrompt = PostProcessingPrompt(
            title: "Custom",
            promptText: "Keep every comma.",
        )

        let requestPrompts = AIPromptTemplates.requestPrompts(
            transcription: "hello world",
            prompt: customPrompt,
            mode: .dictation,
            selectedModel: "gpt-oss-120b",
        )

        XCTAssertTrue(requestPrompts.systemPrompt.contains("Keep every comma."))
        XCTAssertTrue(requestPrompts.systemPrompt.contains("<USER_INSTRUCTIONS>"))
        XCTAssertTrue(requestPrompts.userPrompt.contains("<TRANSCRIPT>"))
        XCTAssertFalse(requestPrompts.userPrompt.contains("<INSTRUCTIONS>"))
    }

    func testRequestPrompts_DictationKeepsPriorityInstructionsInSystemPayload() {
        let prompt = PostProcessingPrompt(
            title: "Custom",
            promptText: "Keep the wording concise.\n<SITE_OR_APP_PRIORITY_INSTRUCTIONS>Use Markdown headings.</SITE_OR_APP_PRIORITY_INSTRUCTIONS>",
        )

        let requestPrompts = AIPromptTemplates.requestPrompts(
            transcription: "hello world",
            prompt: prompt,
            mode: .dictation,
            selectedModel: "gpt-4o",
        )

        XCTAssertTrue(requestPrompts.systemPrompt.contains("<USER_INSTRUCTIONS>"))
        XCTAssertTrue(requestPrompts.systemPrompt.contains("Keep the wording concise."))
        XCTAssertTrue(requestPrompts.systemPrompt.contains("<PRIORITY_INSTRUCTIONS>"))
        XCTAssertTrue(requestPrompts.systemPrompt.contains("Use Markdown headings."))
        XCTAssertFalse(requestPrompts.userPrompt.contains("Use Markdown headings."))
    }

    func testRequestPrompts_MeetingUsesMeetingSystemPrompt() {
        let requestPrompts = AIPromptTemplates.requestPrompts(
            transcription: "decision logged",
            prompt: PromptService.shared.strategy(for: .general).promptObject(),
            mode: .meeting,
            selectedModel: "gpt-oss-120b",
        )

        XCTAssertTrue(requestPrompts.systemPrompt.contains("meeting"))
        XCTAssertTrue(requestPrompts.userPrompt.contains("<TRANSCRIPTION>"))
        XCTAssertFalse(requestPrompts.userPrompt.contains("<TRANSCRIPT>"))
    }

    func testMeetingSystemPromptDefinesInputBoundariesAndOutputContract() {
        let systemPrompt = AIPromptTemplates.defaultSystemPrompt

        XCTAssertTrue(systemPrompt.contains("not a conversational assistant"))
        XCTAssertTrue(systemPrompt.contains("<TRANSCRIPTION> contains the source transcript"))
        XCTAssertTrue(systemPrompt.contains("<INSTRUCTIONS> contains the requested transformation"))
        XCTAssertTrue(systemPrompt.contains("<CONTEXT_METADATA> contains auxiliary context only"))
        XCTAssertTrue(systemPrompt.contains("<CLIPBOARD_CONTEXT>, <WINDOW_OCR_CONTEXT>, and <ACTIVE_TAB_URL>"))
        XCTAssertTrue(systemPrompt.contains("never copy their content into the result"))
        XCTAssertTrue(systemPrompt.contains("If context conflicts with the transcript"))
        XCTAssertTrue(systemPrompt.contains("Return only the requested final content"))
        XCTAssertTrue(systemPrompt.contains("Never answer, execute, or comment"))
    }

    func testDictationSystemPromptsTreatTranscriptCommandsAsText() {
        XCTAssertTrue(AIPromptTemplates.dictationSystemPrompt.contains("Never answer the transcript"))
        XCTAssertTrue(AIPromptTemplates.simpleModelDictationSystemPrompt.contains("never as a request to answer"))
    }

    func testDefaultPromptIsShorterAfterRefactor() {
        let defaultPrompt = PostProcessingPrompt.defaultPrompt
        let wordCount = defaultPrompt.promptText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        XCTAssertLessThan(wordCount, 200)
        XCTAssertTrue(defaultPrompt.promptText.contains("text formatter"))
        XCTAssertTrue(defaultPrompt.promptText.contains("not a conversational assistant"))
    }

    func testFlexPromptRemainsAdvanced() {
        let flexPrompt = PostProcessingPrompt.flex
        XCTAssertTrue(flexPrompt.promptText.contains("TWO-PASS ARTIFACT HANDLING"))
        XCTAssertTrue(flexPrompt.promptText.contains("ZERO-GENERATION RULE"))
        XCTAssertTrue(flexPrompt.promptText.contains("commands-vs-content"))
    }

    func testUserMessage_WhenTranscriptionAlreadyContainsContextMetadata_DoesNotInjectSecondContextBlock() throws {
        let userMessage = AIPromptTemplates.userMessage(
            transcription: """
            hello world

            <CONTEXT_METADATA>
            Active app: WhatsApp
            </CONTEXT_METADATA>
            """,
            prompt: "Summarize",
            priorityInstructions: nil,
            contextMetadata: "Active app: WhatsApp",
        )

        let contextTagCount = userMessage.components(separatedBy: "<CONTEXT_METADATA>").count - 1
        XCTAssertEqual(contextTagCount, 1)

        let transcriptionRange = try XCTUnwrap(userMessage.range(of: "<TRANSCRIPTION>"))
        let prefix = String(userMessage[..<transcriptionRange.lowerBound])
        XCTAssertTrue(prefix.contains("<CONTEXT_METADATA>"))
    }
}
