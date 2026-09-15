import Foundation
import MeetingAssistantCoreDomain

/// Strategy for General meetings (Standard summary).
public struct GeneralMeetingStrategy: PromptStrategy {
    public init() {}

    public var systemPrompt: String {
        "You are an expert meeting assistant. Your goal is to provide a balanced, comprehensive summary of the meeting."
    }

    public func userPrompt(for _: String) -> String {
        """
        Analyze the transcription and provide a summary including:
        - Key Topics Discussed
        - Decisions Made
        - Action Items
        """
    }

    public func promptObject() -> PostProcessingPrompt {
        PostProcessingPrompt(
            title: "General Summary",
            promptText: userPrompt(for: ""),
            icon: "doc.text",
            description: "Standard summary with topics, decisions, and actions.",
            isPredefined: true
        )
    }
}

/// Strategy for Standup meetings (Progress/Blockers focus).
public struct StandupMeetingStrategy: PromptStrategy {
    public init() {}

    public var systemPrompt: String {
        "You are an agile coach assistant. Focus on progress, blockers, and next steps."
    }

    public func userPrompt(for _: String) -> String {
        """
        Analyze the standup meeting transcription and extract:
        - What was done (Progress)
        - What is planned (Next Steps)
        - Blockers/Impediments

        Format as a bulleted list per person if possible.
        """
    }

    public func promptObject() -> PostProcessingPrompt {
        PostProcessingPrompt(
            title: "Standup Report",
            promptText: userPrompt(for: ""),
            icon: "figure.stand",
            description: "Focuses on progress, plans, and blockers.",
            isPredefined: true
        )
    }
}

/// Strategy for Design Reviews (Feedback/Critique focus).
public struct DesignReviewStrategy: PromptStrategy {
    public init() {}

    public var systemPrompt: String {
        "You are a design lead assistant. Focus on design feedback, decisions, and critiques."
    }

    public func userPrompt(for _: String) -> String {
        """
        Analyze the design review transcription and summarize:
        - Design Concepts Presented
        - Feedback Received (Positive/Constructive)
        - Design Decisions/Approvals
        - Action Items for Iteration
        """
    }

    public func promptObject() -> PostProcessingPrompt {
        PostProcessingPrompt(
            title: "Design Review",
            promptText: userPrompt(for: ""),
            icon: "paintbrush",
            description: "Captures design feedback and decisions.",
            isPredefined: true
        )
    }
}
