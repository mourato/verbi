import SwiftUI

public struct SettingsSectionHeader: View {
    private let title: String
    private let description: String?
    private let calloutKind: DSCallout.Kind?
    private let calloutTitle: String?
    private let calloutMessage: String?

    public init(
        title: String,
        description: String? = nil,
        calloutKind: DSCallout.Kind? = nil,
        calloutTitle: String? = nil,
        calloutMessage: String? = nil
    ) {
        self.title = title
        self.description = description
        self.calloutKind = calloutKind
        self.calloutTitle = calloutTitle
        self.calloutMessage = calloutMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            if let description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let calloutKind,
               let calloutTitle,
               let calloutMessage,
               !calloutTitle.isEmpty,
               !calloutMessage.isEmpty
            {
                DSCallout(kind: calloutKind, title: calloutTitle, message: calloutMessage)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Section Header") {
    SettingsSectionHeader(
        title: "Header",
        description: "Short context to help users decide quickly."
    )
    .padding()
}
