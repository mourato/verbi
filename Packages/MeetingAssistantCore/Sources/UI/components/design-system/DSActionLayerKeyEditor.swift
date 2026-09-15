import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct DSActionLayerKeyEditor: View {
    @Binding private var key: String
    private let title: String
    private let placeholder: String
    private let conflictMessage: String?
    private let maxInputWidth: CGFloat

    public init(
        title: String,
        key: Binding<String>,
        placeholder: String = "—",
        conflictMessage: String? = nil,
        maxInputWidth: CGFloat = 80
    ) {
        self.title = title
        _key = key
        self.placeholder = placeholder
        self.conflictMessage = conflictMessage
        self.maxInputWidth = maxInputWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                TextField(placeholder, text: Binding(
                    get: { key },
                    set: { newValue in
                        key = Self.normalizedKey(from: newValue)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .frame(width: maxInputWidth)
            }

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }
        }
    }

    private static func normalizedKey(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let character = trimmed.first else {
            return ""
        }
        return String(character).uppercased()
    }
}

#Preview {
    DSActionLayerKeyEditor(
        title: "Action",
        key: .constant("A"),
        conflictMessage: nil
    )
    .padding()
}
