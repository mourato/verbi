import Foundation

public struct WebContextTarget: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let displayName: String
    public let urlPatterns: [String]
    public let browserBundleIdentifiers: [String]
    public let forceMarkdownOutput: Bool
    public let outputLanguage: DictationOutputLanguage
    public let autoStartMeetingRecording: Bool
    public let customPromptInstructions: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        urlPatterns: [String],
        browserBundleIdentifiers: [String] = [],
        forceMarkdownOutput: Bool = true,
        outputLanguage: DictationOutputLanguage = .original,
        autoStartMeetingRecording: Bool = false,
        customPromptInstructions: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.urlPatterns = urlPatterns
        self.browserBundleIdentifiers = browserBundleIdentifiers
        self.forceMarkdownOutput = forceMarkdownOutput
        self.outputLanguage = outputLanguage
        self.autoStartMeetingRecording = autoStartMeetingRecording
        self.customPromptInstructions = customPromptInstructions?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case urlPatterns
        case browserBundleIdentifiers
        case forceMarkdownOutput
        case outputLanguage
        case autoStartMeetingRecording
        case customPromptInstructions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        urlPatterns = try container.decode([String].self, forKey: .urlPatterns)
        browserBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .browserBundleIdentifiers) ?? []
        // Legacy entries represented markdown-only targets, so default this to true.
        forceMarkdownOutput = try container.decodeIfPresent(Bool.self, forKey: .forceMarkdownOutput) ?? true
        outputLanguage = try container.decodeIfPresent(DictationOutputLanguage.self, forKey: .outputLanguage) ?? .original
        autoStartMeetingRecording = try container.decodeIfPresent(Bool.self, forKey: .autoStartMeetingRecording) ?? false
        customPromptInstructions = try container.decodeIfPresent(String.self, forKey: .customPromptInstructions)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
